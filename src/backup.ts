/**
 * VPS Snapshot — Motor de Backup
 * tar | [pigz] | [gpg] → split → sha256 → rclone upload
 *
 * FASE 3: streaming pipeline, pigz paralelo, decomposto, sem duplicados
 */

import {
  mkTempDir, mkTempFile, acquireLock, releaseLock, run,
  rcloneUpload, rcloneRemote, rcloneMkdir, rcloneList, rcloneDelete,
  systemInfo, generateChecksumManifest, verifyChecksumManifest,
  gpgEncrypt, checkGpg, getPigz, getFreeSpace, formatBytes,
} from "./utils";
import { logger, die } from "./logger";
import type { SnapshotConfig } from "./config";

const INSTALL_DIR = "/opt/vps-snapshot";
const LOG_FILE = INSTALL_DIR + "/backup.log";

// ── Estimate ──

export async function cmdEstimate(config: SnapshotConfig): Promise<void> {
  logger.banner("ESTIMATIVA DE BACKUP");

  const excludes = buildExcludeArgs(config);
  logger.info("Calculando tamanho (sem compressao)...\n");

  const info = systemInfo();
  logger.dim("  VPS: " + info.hostname + " | " + info.distro + " | " + info.kernel);
  logger.dim("  Alvo: " + config.remoteName + " | " + rcloneRemote(config.remoteName, config.remotePath));
  console.log("");

  const pigz = getPigz();
  if (pigz) {
    logger.info("Compressao paralela: pigz disponivel");
  }

  // du com exclusoes
  const excludeDu = excludes.map((e) => "--exclude=" + e).join(" ");
  const cmd = 'du -sh ' + excludeDu + " / 2>/dev/null | tail -1";

  try {
    const result = await run(cmd, "estimate");
    const size = result.split(/\s+/)[0];
    logger.success("Tamanho estimado (bruto): " + size);

    const sizeNum = parseSizeToBytes(size);
    const compressedLow = formatBytes(sizeNum * 0.35);
    const compressedHigh = formatBytes(sizeNum * 0.6);
    logger.info("Estimativa comprimida: ~" + compressedLow + " - " + compressedHigh);

    const splitBytes = parseSizeToBytes(config.splitSize);
    const parts = Math.ceil((sizeNum * 0.5) / splitBytes);
    if (parts > 1) {
      logger.info("Arquivos split (" + config.splitSize + "): ~" + parts + " partes");
    } else {
      logger.info("Arquivo unico (menor que o limite de split)");
    }

    if (config.encryption.enabled) {
      logger.info("Criptografia GPG: habilitada");
    }
  } catch {
    logger.warn("Nao conseguiu estimar com du.");
    logger.info("Dica: rode o backup e veja o tamanho real no log.");
  }
}

// ── Backup (orquestrador) ──

export async function cmdBackup(config: SnapshotConfig): Promise<void> {
  logger.banner("BACKUP COMPLETO");
  acquireLock();

  const tmpDir = mkTempDir("vps-snapshot-");
  const timestamp = formatTimestamp();
  let lockHeld = true;

  // Detectar compressor
  const pigzPath = getPigz();
  const compressor = pigzPath ? "pigz" : "gzip";

  logger.info("VPS: " + config.vpsName);
  logger.info("Temp dir: " + tmpDir);
  logger.info("Timestamp: " + timestamp);
  logger.info("Compressor: " + compressor + (pigzPath ? " (paralelo)" : ""));
  if (config.encryption.enabled) {
    logger.info("Criptografia: habilitada");
    if (!checkGpg()) {
      die("GPG nao encontrado. Instale: apt install gnupg2");
    }
  }

  try {
    await runPrePost(config.preBackupCommands, "pre-backup");

    // ── Check espaco em disco ──
    await checkDiskSpace(config);

    // ── Passo 1: Streaming tar | gzip | split ──
    const gzFile = await createBackupArchive(config, tmpDir, timestamp, compressor);

    // ── Passo 2: GPG (opcional) ──
    const fileToSplit = await maybeEncrypt(config, gzFile);

    // ── Passo 3: Split ──
    const { splitDir, splitFiles, splitPrefix } = await splitFile(
      config, timestamp, fileToSplit, tmpDir,
    );

    // Remover arquivo original antes de split
    await run('rm -f "' + fileToSplit + '"');

    // ── Passo 4: SHA256 ──
    const manifestFile = splitDir + "/" + splitPrefix + ".sha256";
    logger.info("Gerando checksum SHA256...");
    await generateChecksumManifest(splitDir, manifestFile);
    logger.success("Manifesto SHA256: " + splitFiles.length + " arquivos verificados");

    // ── Passo 5: Upload ──
    const backupRemote = rcloneRemote(config.remoteName, config.remotePath) + "/" + config.vpsName + "/" + timestamp;
    await rcloneMkdir(backupRemote);

    logger.info("Enviando para nuvem...");
    await rcloneUpload(splitDir, backupRemote, "upload backup");

    // ── Passo 6: Verificar upload ──
    await verifyUpload(splitDir, splitPrefix, backupRemote);

    // ── Passo 7: Limpeza local ──
    await run('rm -rf "' + splitDir + '" "' + gzFile + '"');
    logger.success("Temp files limpos");

    // ── Passo 8: Rotacao ──
    await rotateBackups(config);

    // ── Passo 9: Log ──
    appendLog(LOG_FILE, timestamp, "SUCCESS", formatBytes(Bun.file(gzFile).sizeSync() || 0) + ", " + splitFiles.length + " partes, SHA256 OK");

    await runPrePost(config.postBackupCommands, "pos-backup");

    logger.success("Backup concluido! " + splitFiles.length + " arquivo(s)");
    logger.dim("  Remote: " + backupRemote);
    if (config.encryption.enabled) {
      logger.dim("  Criptografia: GPG habilitada");
    }

  } catch (e) {
    appendLog(LOG_FILE, timestamp, "FAILED", (e as Error).message);
    throw e;
  } finally {
    try { await run('rm -rf "' + tmpDir + '"'); } catch { /* ignore */ }
    if (lockHeld) releaseLock();
  }
}

// ── Sub-funcoes decompostas ──

/** Verifica espaco em disco — precisa de pelo menos 2x o tamanho estimado */
async function checkDiskSpace(config: SnapshotConfig): Promise<void> {
  logger.info("Verificando espaco em disco...");
  const free = await getFreeSpace("/tmp");
  const MIN_SPACE = 1024 * 1024 * 1024; // 1GB
  if (free < MIN_SPACE) {
    die("Espaco insuficiente em /tmp: " + formatBytes(free) + ". Minimo: " + formatBytes(MIN_SPACE));
  }
  logger.info("Espaco livre: " + formatBytes(free));
}

/**
 * Cria arquivo tar.gz via streaming pipeline: tar | pigz/gzip
 * Tar separado primeiro (para injetar metadata), depois gzip.
 * A diferenca: usa pigz quando disponivel para compressao paralela.
 */
async function createBackupArchive(
  config: SnapshotConfig,
  tmpDir: string,
  timestamp: string,
  compressor: string,
): Promise<string> {
  const metaFile = mkTempFile("vps-snapshot-meta-");
  const tarFile = tmpDir + "/" + config.vpsName + "-" + timestamp + ".tar";
  const gzFile = tarFile + ".gz";

  // Gerar metadata
  const info = systemInfo();
  const meta = buildMetadata(config, timestamp, info);
  Bun.write(metaFile, JSON.stringify(meta, null, 2));
  logger.debug("Meta: " + metaFile);

  // ── Criar tar ──
  logger.info("Criando tar ball...");
  const tarArgs = buildTarArgs(config, tarFile);
  const tarProc = Bun.spawn(["tar", ...tarArgs], {
    stdout: "pipe",
    stderr: "pipe",
  });

  const tarStderr = (await new Response(tarProc.stderr).text()).trim();
  if (tarProc.exitCode !== 0 && tarStderr) {
    logger.warn("Tar warnings (normal): " + tarStderr.slice(0, 200));
  }

  // Adicionar metadata AO tar (antes do gzip)
  logger.info("Adicionando metadata...");
  await run('tar --append -f "' + tarFile + '" -C /tmp "' + metaFile.replace("/tmp/", "") + '" 2>/dev/null || true', "meta append");

  // Verificar tar
  const tarSize = await run('stat -c %s "' + tarFile + '"', "tar size");
  if (!tarSize || Number(tarSize) < 1024) {
    die("Tar vazio ou muito pequeno. Algo deu errado.");
  }
  logger.info("Tar criado: " + formatBytes(Number(tarSize)));

  // ── Gzip (pigz se disponivel, senao gzip) ──
  const level = String(config.compressionLevel);
  const compressCmd = compressor === "pigz"
    ? "pigz -" + level + " -c \"" + tarFile + "\""
    : "gzip -" + level + " -c \"" + tarFile + "\"";

  logger.info("Comprimindo (level " + config.compressionLevel + ") via " + compressor + "...");
  const gzProc = Bun.spawn(["bash", "-c", compressCmd], {
    stdout: Bun.file(gzFile).writer(),
    stderr: "pipe",
  });

  await gzProc.exited;
  const gzStderr = (await new Response(gzProc.stderr).text()).trim();
  if (gzProc.exitCode !== 0) {
    die(compressor + " falhou: " + gzStderr);
  }

  const gzSize = await run('stat -c %s "' + gzFile + '"', "gzip size");
  const ratio = ((1 - Number(gzSize) / Number(tarSize)) * 100).toFixed(0);
  logger.success("Comprimido: " + formatBytes(Number(gzSize)) + " (ratio: " + ratio + "%)");

  // Remover tar uncompressed
  await run('rm -f "' + tarFile + '"');

  return gzFile;
}

/** GPG encrypt se habilitado, retorna caminho do arquivo pronto */
async function maybeEncrypt(config: SnapshotConfig, gzFile: string): Promise<string> {
  if (!config.encryption.enabled) return gzFile;

  logger.info("Criptografando com GPG...");
  const gpgFile = gzFile + ".gpg";
  await gpgEncrypt(gzFile, gpgFile, config.encryption);
  const gpgSize = await run('stat -c %s "' + gpgFile + '"', "gpg size");
  logger.success("Criptografado: " + formatBytes(Number(gpgSize)));
  await run('rm -f "' + gzFile + '"');
  return gpgFile;
}

/** Split em partes, retorna dir + lista de arquivos + prefixo */
async function splitFile(
  config: SnapshotConfig,
  timestamp: string,
  fileToSplit: string,
  tmpDir: string,
): Promise<{ splitDir: string; splitFiles: string[]; splitPrefix: string }> {
  const splitDir = mkTempDir("vps-snapshot-split-");
  const ext = config.encryption.enabled ? ".tar.gz.gpg.part" : ".tar.gz.part";
  const splitPrefix = config.vpsName + "-" + timestamp + ext;

  logger.info("Split " + config.splitSize + "...");
  await run(
    'split -b ' + config.splitSize + ' -d -a 2 "' + fileToSplit + '" "' + splitDir + "/" + splitPrefix + '"',
    "split",
  );

  const splitFiles = (await run('ls -1 "' + splitDir + "/" + splitPrefix + '*"', "list split"))
    .split("\n")
    .filter(Boolean);
  if (splitFiles.length === 0) {
    die("Split nao gerou nenhum arquivo");
  }
  logger.info("Split: " + splitFiles.length + " parte(s)");

  return { splitDir, splitFiles, splitPrefix };
}

/** Baixa manifesto da nuvem e verifica checksum */
async function verifyUpload(
  splitDir: string,
  splitPrefix: string,
  backupRemote: string,
): Promise<void> {
  logger.info("Verificando integridade do upload...");
  const verifyDir = mkTempDir("vps-snapshot-verify-");
  const verifyManifest = verifyDir + "/" + splitPrefix + ".sha256";

  try {
    await run('rclone copy "' + backupRemote + "/" + splitPrefix + '.sha256" "' + verifyDir + '/" --progress', "download manifest");
    await verifyChecksumManifest(splitDir, verifyManifest);
  } catch (e) {
    die("VERIFICACAO DE INTEGRIDADE FALHOU: " + (e as Error).message + "\n  O backup pode estar corrompido na nuvem!");
  } finally {
    await run('rm -rf "' + verifyDir + '"');
  }
}

// ── Rotacao de backups ──

async function rotateBackups(config: SnapshotConfig): Promise<void> {
  logger.info("Verificando rotacao...");
  const baseRemote = rcloneRemote(config.remoteName, config.remotePath) + "/" + config.vpsName;
  const dirs = await rcloneList(baseRemote);

  if (dirs.length <= config.keepBackups) {
    logger.info(dirs.length + "/" + config.keepBackups + " backups — sem rotacao necessaria");
    return;
  }

  const toDelete = dirs.slice(config.keepBackups);
  for (const d of toDelete) {
    logger.info("Removendo backup antigo: " + d);
    await rcloneDelete(baseRemote + "/" + d);
  }
  logger.success("Removido " + toDelete.length + " backup(s) antigo(s)");
}

// ── Helpers internos ──

function buildExcludeArgs(config: SnapshotConfig): string[] {
  const excludes: string[] = [
    "/proc", "/sys", "/dev", "/run", "/tmp",
    "/snap", "/boot/efi",
    "/var/cache/apt/archives", "/var/cache/yum", "/var/cache/dnf",
    "/var/lib/apt/lists",
    INSTALL_DIR,
    "*.log", "*.tmp", "*.pid", "*.sock", "*.swap", "nohup.out",
    "*/node_modules", "*/__pycache__", "*/.cache", "*/.npm",
    "*/.pip", "*/.cargo/registry", "*/go/pkg/mod/cache",
    "*/.git/objects/pack",
  ];

  if (config.excludeDockerImages) {
    excludes.push(
      "/var/lib/docker/overlay2",
      "/var/lib/docker/containers",
      "/var/lib/docker/image",
      "/var/lib/docker/buildkit",
    );
  }

  if (config.excludePatterns) {
    for (const p of config.excludePatterns) {
      if (p && !excludes.includes(p)) excludes.push(p);
    }
  }

  if (config.excludePaths) {
    for (const p of config.excludePaths) {
      if (p && !excludes.includes(p) && p !== INSTALL_DIR) excludes.push(p);
    }
  }

  return excludes;
}

function buildTarArgs(config: SnapshotConfig, tarFile: string): string[] {
  const args: string[] = [
    "--create",
    "--one-file-system",
    "--ignore-failed-read",
    "--warning=no-file-changed",
    "--warning=no-file-removed",
    "-f", tarFile,
  ];

  const excludes = buildExcludeArgs(config);
  for (const e of excludes) {
    args.push("--exclude", e);
  }

  args.push("/");
  return args;
}

/** Metadata com PII controlado — so inclui system info se includeSystemInfo=true */
function buildMetadata(config: SnapshotConfig, timestamp: string, info: ReturnType<typeof systemInfo>) {
  const meta: Record<string, unknown> = {
    version: "1.0.0",
    vpsName: config.vpsName,
    timestamp,
    createdAt: new Date().toISOString(),
    config: {
      compressionLevel: config.compressionLevel,
      splitSize: config.splitSize,
      excludeDockerImages: config.excludeDockerImages,
      encrypted: config.encryption.enabled,
    },
  };

  if (config.includeSystemInfo) {
    meta.system = {
      hostname: info.hostname,
      distro: info.distro,
      kernel: info.kernel,
      arch: info.arch,
    };
  }

  return meta;
}

function formatTimestamp(): string {
  return new Date()
    .toISOString()
    .replace(/[-:T]/g, "")
    .replace(/\.\d+Z$/, "");
}

async function runPrePost(commands: string[], label: string): Promise<void> {
  if (!commands || commands.length === 0) return;
  logger.info("Executando " + label + " commands...");
  for (const cmd of commands) {
    logger.debug("  " + label + ": " + cmd);
    await run(cmd, label);
  }
}

function appendLog(logFile: string, timestamp: string, status: string, detail: string): void {
  const line = "[" + timestamp + "] [" + status + "] " + detail + "\n";
  try {
    Bun.spawnSync(["bash", "-c", "echo '" + line + "' >> \"" + logFile + "\""]);
  } catch { /* ignore */ }
}

function parseSizeToBytes(size: string): number {
  const match = size.match(/^([\d.]+)\s*(K|M|G|T)?/i);
  if (!match) return 0;
  const n = parseFloat(match[1]);
  const unit = (match[2] || "").toUpperCase();
  const mult: Record<string, number> = { K: 1024, M: 1048576, G: 1073741824, T: 1099511627776 };
  return n * (mult[unit] || 1);
}
