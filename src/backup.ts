/**
 * VPS Snapshot — Motor de Backup
 * tar -> gzip -> [gpg] -> split -> [sha256] -> rclone upload
 */

import { mkTempDir, mkTempFile, acquireLock, releaseLock, run, rcloneUpload, rcloneRemote, rcloneMkdir, rcloneList, rcloneDelete, systemInfo, generateChecksumManifest, verifyChecksumManifest, gpgEncrypt, checkGpg } from "./utils";
import { logger, die } from "./logger";
import type { SnapshotConfig } from "./config";

const INSTALL_DIR = "/opt/vps-snapshot";
const LOG_FILE = `${INSTALL_DIR}/backup.log`;

// ── Estimate ──

export async function cmdEstimate(config: SnapshotConfig): Promise<void> {
  logger.banner("ESTIMATIVA DE BACKUP");

  const excludes = buildExcludeArgs(config);

  logger.info("Calculando tamanho (sem compressao)...\n");

  const info = systemInfo();
  logger.dim(`  VPS: ${info.hostname} | ${info.distro} | ${info.kernel}`);
  logger.dim(`  Alvo: ${config.remoteName} | ${rcloneRemote(config.remoteName, config.remotePath)}`);
  console.log("");

  // du com exclusoes
  const excludeDu = excludes.map((e) => `--exclude=${e}`).join(" ");
  const cmd = `du -sh --exclude=${excludeDu} / 2>/dev/null | tail -1`;

  try {
    const result = await run(cmd, "estimate");
    const [size] = result.split(/\s+/);
    logger.success(`Tamanho estimado (bruto): ${size}`);

    const sizeNum = parseSizeToBytes(size);
    const compressedLow = formatBytes(sizeNum * 0.35);
    const compressedHigh = formatBytes(sizeNum * 0.6);
    logger.info(`Estimativa comprimida: ~${compressedLow} - ${compressedHigh}`);

    const splitBytes = parseSizeToBytes(config.splitSize);
    const parts = Math.ceil((sizeNum * 0.5) / splitBytes);
    if (parts > 1) {
      logger.info(`Arquivos split (${config.splitSize}): ~${parts} partes`);
    } else {
      logger.info("Arquivo unico (menor que o limite de split)");
    }

    if (config.encryption.enabled) {
      logger.info("Criptografia GPG: habilitada (tamanho final sera similar)");
    }
  } catch (e) {
    logger.warn("Nao conseguiu estimar com du. Tentando com find...");
    try {
      const excludeFind = excludes
        .filter((e) => e.startsWith("/") || e.startsWith("*"))
        .map((e) => `-not -path "${e}" -not -path "${e}/*"`)
        .join(" ");
      await run(`find / -type f ${excludeFind} -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s}'`, "find size");
    } catch {
      die("Nao conseguiu calcular estimativa");
    }
  }
}

// ── Backup ──

export async function cmdBackup(config: SnapshotConfig): Promise<void> {
  logger.banner("BACKUP COMPLETO");
  acquireLock();

  const tmpDir = mkTempDir("vps-snapshot-");
  const timestamp = formatTimestamp();
  const tarFile = `${tmpDir}/${config.vpsName}-${timestamp}.tar`;
  const metaFile = mkTempFile("vps-snapshot-meta-");
  const lockHeld = true;

  logger.info(`VPS: ${config.vpsName}`);
  logger.info(`Temp dir: ${tmpDir}`);
  logger.info(`Timestamp: ${timestamp}`);
  if (config.encryption.enabled) {
    logger.info("Criptografia: habilitada");
    if (!checkGpg()) {
      die("GPG nao encontrado. Instale: apt install gnupg2");
    }
  }

  try {
    // Pre-backup commands
    await runPrePost(config.preBackupCommands, "pre-backup");

    // Gerar metadata ANTES do tar (PII controlado)
    const info = systemInfo();
    const meta = buildMetadata(config, timestamp, info);
    Bun.write(metaFile, JSON.stringify(meta, null, 2));
    logger.debug(`Meta: ${metaFile}`);

    // ── Passo 1: Criar tar (SEM gzip ainda) ──
    logger.info("Criando tar ball...");
    const tarProc = Bun.spawn(["tar", ...buildTarArgs(config, tarFile)], {
      stdout: "pipe",
      stderr: "pipe",
    });

    const tarStderr = (await new Response(tarProc.stderr).text()).trim();
    if (tarProc.exitCode !== 0 && tarStderr) {
      logger.warn(`Tar warnings (normal): ${tarStderr.slice(0, 200)}`);
    }

    // Adicionar metadata AO tar (antes do gzip)
    logger.info("Adicionando metadata...");
    const metaAddCmd = `tar --append -f "${tarFile}" -C /tmp "${metaFile.replace("/tmp/", "")}" 2>/dev/null || true`;
    await run(metaAddCmd, "meta append");

    // Verificar tar
    const tarSize = await run(`stat -c %s "${tarFile}"`, "tar size");
    if (!tarSize || Number(tarSize) < 1024) {
      die("Tar vazio ou muito pequeno. Algo deu errado.");
    }
    logger.info(`Tar criado: ${formatBytes(Number(tarSize))}`);

    // ── Passo 2: Gzip ──
    const gzFile = `${tarFile}.gz`;
    logger.info(`Comprimindo (level ${config.compressionLevel})...`);
    const gzipProc = Bun.spawn([
      "gzip", `-${config.compressionLevel}`, "-c", tarFile,
    ], {
      stdout: Bun.file(gzFile).writer(),
      stderr: "pipe",
    });

    await gzipProc.exited;
    const gzSize = await run(`stat -c %s "${gzFile}"`, "gzip size");
    logger.success(`Comprimido: ${formatBytes(Number(gzSize))} (ratio: ${((1 - Number(gzSize) / Number(tarSize)) * 100).toFixed(0)}%)`);

    // Remover tar uncompressed
    await run(`rm -f "${tarFile}"`);

    // ── Passo 3: GPG (opcional) ──
    let fileToSplit = gzFile;
    if (config.encryption.enabled) {
      logger.info("Criptografando com GPG...");
      const gpgFile = `${gzFile}.gpg`;
      await gpgEncrypt(gzFile, gpgFile, config.encryption);
      const gpgSize = await run(`stat -c %s "${gpgFile}"`, "gpg size");
      logger.success(`Criptografado: ${formatBytes(Number(gpgSize))}`);
      await run(`rm -f "${gzFile}"`);
      fileToSplit = gpgFile;
    }

    // ── Passo 4: Split ──
    const splitDir = mkTempDir("vps-snapshot-split-");
    const ext = config.encryption.enabled ? ".tar.gz.gpg.part" : ".tar.gz.part";
    const splitPrefix = `${config.vpsName}-${timestamp}${ext}`;

    logger.info(`Split ${config.splitSize}...`);
    const splitCmd = `split -b ${config.splitSize} -d -a 2 "${fileToSplit}" "${splitDir}/${splitPrefix}"`;
    await run(splitCmd, "split");

    const splitFiles = (await run(`ls -1 "${splitDir}/${splitPrefix}"*`, "list split")).split("\n").filter(Boolean);
    if (splitFiles.length === 0) {
      die("Split nao gerou nenhum arquivo");
    }
    logger.info(`Split: ${splitFiles.length} parte(s)`);

    // Remover arquivo original antes de split
    await run(`rm -f "${fileToSplit}"`);

    // ── Passo 5: SHA256 checksum manifesto ──
    const manifestFile = `${splitDir}/${splitPrefix}.sha256`;
    logger.info("Gerando checksum SHA256...");
    await generateChecksumManifest(splitDir, manifestFile);
    logger.success(`Manifesto SHA256: ${splitFiles.length} arquivos verificados`);

    // ── Passo 6: Upload ──
    const backupRemote = `${rcloneRemote(config.remoteName, config.remotePath)}/${config.vpsName}/${timestamp}`;
    await rcloneMkdir(backupRemote);

    logger.info("Enviando para nuvem...");
    await rcloneUpload(splitDir, backupRemote, "upload backup");

    // ── Passo 7: Verificar upload (download de volta + checksum) ──
    logger.info("Verificando integridade do upload...");
    const verifyDir = mkTempDir("vps-snapshot-verify-");
    const verifyManifest = `${verifyDir}/${splitPrefix}.sha256`;

    try {
      await run(`rclone copy "${backupRemote}/${splitPrefix}.sha256" "${verifyDir}/" --progress`, "download manifest");
      await verifyChecksumManifest(splitDir, verifyManifest);
    } catch (e) {
      die(`VERIFICACAO DE INTEGRIDADE FALHOU: ${(e as Error).message}\n  O backup pode estar corrompido na nuvem!`);
    } finally {
      await run(`rm -rf "${verifyDir}"`);
    }

    // ── Passo 8: Limpeza local ──
    await run(`rm -rf "${splitDir}" "${gzFile}" "${metaFile}"`);
    logger.success("Temp files limpos");

    // ── Passo 9: Rotacao ──
    await rotateBackups(config);

    // ── Passo 10: Log ──
    appendLog(LOG_FILE, timestamp, "SUCCESS", `${formatBytes(Number(gzSize))}, ${splitFiles.length} partes, SHA256 OK`);

    // Post-backup commands
    await runPrePost(config.postBackupCommands, "pos-backup");

    logger.success(`Backup concluido! ${formatBytes(Number(gzSize))} em ${splitFiles.length} arquivo(s)`);
    logger.dim(`  Remote: ${backupRemote}`);
    if (config.encryption.enabled) {
      logger.dim("  Criptografia: GPG habilitada");
    }

  } catch (e) {
    appendLog(LOG_FILE, timestamp, "FAILED", (e as Error).message);
    throw e;
  } finally {
    try { await run(`rm -rf "${tmpDir}"`); } catch { /* ignore */ }
    if (lockHeld) releaseLock();
  }
}

// ── Rotacao de backups ──

async function rotateBackups(config: SnapshotConfig): Promise<void> {
  logger.info("Verificando rotacao...");
  const baseRemote = `${rcloneRemote(config.remoteName, config.remotePath)}/${config.vpsName}`;
  const dirs = await rcloneList(baseRemote);

  if (dirs.length <= config.keepBackups) {
    logger.info(`${dirs.length}/${config.keepBackups} backups — sem rotacao necessaria`);
    return;
  }

  const toDelete = dirs.slice(config.keepBackups);
  for (const d of toDelete) {
    logger.info(`Removendo backup antigo: ${d}`);
    await rcloneDelete(`${baseRemote}/${d}`);
  }
  logger.success(`Removido ${toDelete.length} backup(s) antigo(s)`);
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

  // PII: so inclui se usuario habilitou explicitamente
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
  logger.info(`Executando ${label} commands...`);
  for (const cmd of commands) {
    logger.debug(`  ${label}: ${cmd}`);
    await run(cmd, label);
  }
}

function appendLog(logFile: string, timestamp: string, status: string, detail: string): void {
  const line = `[${timestamp}] [${status}] ${detail}\n`;
  try {
    Bun.spawnSync(["bash", "-c", `echo '${line}' >> "${logFile}"`]);
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

function formatBytes(bytes: number): string {
  if (bytes === 0) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB"];
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  return `${(bytes / Math.pow(1024, i)).toFixed(1)} ${units[i]}`;
}
