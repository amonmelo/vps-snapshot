/**
 * VPS Snapshot - Motor de Restore
 * list, browse, extract, full restore
 * Com validacao de input e verificacao de integridade
 */

import {
  mkTempDir, run, rcloneRemote, rcloneList,
  rcloneSize, rcloneSpace, rcloneCheck,
  runQuiet, verifyChecksumManifest, gpgDecrypt,
} from "./utils";
import { logger, die } from "./logger";
import { validateTimestamp, validatePath, validateDestDir } from "./config";
import type { SnapshotConfig } from "./config";

// -- List backups --

export async function cmdList(config: SnapshotConfig): Promise<void> {
  logger.banner("BACKUPS DISPONIVEIS");

  const baseRemote = rcloneRemote(config.remoteName, config.remotePath) + "/" + config.vpsName;
  const dirs = await rcloneList(baseRemote);

  if (dirs.length === 0) {
    logger.warn("Nenhum backup encontrado");
    return;
  }

  logger.info("VPS: " + config.vpsName + " | Total: " + dirs.length + " backup(s)\n");

  console.log("  #   Timestamp              Arquivos   Tamanho       Enc");
  console.log("  --  -------------------    -------    --------       ---");

  for (let i = 0; i < dirs.length; i++) {
    const d = dirs[i].trim();
    if (!d) continue;
    const fullRemote = baseRemote + "/" + d;

    let size = "?";
    try { size = await rcloneSize(fullRemote); } catch { /* skip */ }

    let files = "?";
    try {
      const parts = await rcloneList(fullRemote);
      files = String(parts.length);
    } catch { /* skip */ }

    let enc = "?";
    try {
      const parts = await rcloneList(fullRemote);
      enc = parts.some((p) => p.includes(".gpg")) ? "GPG" : "Nao";
    } catch { /* skip */ }

    const num = String(i + 1).padStart(2);
    console.log("  " + num + "  " + d.padEnd(23) + " " + files.padStart(7) + "   " + String(size).padStart(12) + "   " + enc);
  }

  console.log("");
  logger.dim("  Use: vps-snapshot browse <timestamp>  para navegar");
  logger.dim("  Use: vps-snapshot full <timestamp>    para restaurar tudo");
}

// -- Browse (listar conteudo do tar) --

export async function cmdBrowse(config: SnapshotConfig, timestamp?: string): Promise<void> {
  if (!timestamp) {
    await cmdList(config);
    const ts = await askTimestamp();
    return cmdBrowse(config, ts);
  }

  const ts = validateTimestamp(timestamp);
  logger.banner("NAVEGANDO: " + ts);
  const tmpDir = mkTempDir("vps-snapshot-browse-");
  const tarFile = await downloadAndPrepare(config, ts, tmpDir);

  logger.info("Listando conteudo do backup...\n");
  try {
    const out = await run('tar -tzf "' + tarFile + '" | head -100', "browse");
    const lines = out.split("\n").filter(Boolean);
    console.log("  Mostrando " + lines.length + " primeiros itens (de muitos):\n");
    for (const line of lines) {
      console.log("  " + line);
    }
    if (lines.length === 100) {
      logger.dim("\n  ... (lista truncada. Use extract para arquivos especificos)");
    }
    logger.dim("\n  Total de itens no backup: estimando...");
    const total = await run('tar -tzf "' + tarFile + '" | wc -l', "count");
    logger.info("Total: " + total.trim() + " itens");
  } finally {
    await cleanup(tmpDir);
  }
}

// -- Extract (extrair arquivos especificos) --

export async function cmdExtract(
  config: SnapshotConfig,
  timestamp: string,
  patterns: string[],
  destDir: string,
): Promise<void> {
  if (!timestamp || patterns.length === 0) {
    logger.error("Uso: vps-snapshot extract <timestamp> <path1> [path2] ... [--dest /caminho]");
    logger.dim("  Ex: vps-snapshot extract 20250601030000 /etc/nginx /home/user --dest /tmp/restored");
    process.exit(1);
  }

  const ts = validateTimestamp(timestamp);

  const validPatterns: string[] = [];
  for (const p of patterns) {
    if (p === "--dest") continue;
    validPatterns.push(validatePath(p));
  }

  let realDest = destDir || ("/tmp/vps-snapshot-restored-" + ts);
  realDest = validateDestDir(realDest);

  logger.banner("EXTRAINDO: " + ts);
  const tmpDir = mkTempDir("vps-snapshot-extract-");
  const tarFile = await downloadAndPrepare(config, ts, tmpDir);

  await run('mkdir -p "' + realDest + '"', "mkdir dest");

  for (const pattern of validPatterns) {
    logger.info("Extraindo: " + pattern + " -> " + realDest);
    try {
      await run('tar -xzf "' + tarFile + '" -C "' + realDest + '" "' + pattern + '"', "extract " + pattern);
      logger.success("  OK: " + pattern);
    } catch (e) {
      logger.error("  Falha: " + pattern + " - " + (e as Error).message);
    }
  }

  logger.success("\nExtraido para: " + realDest);
  await cleanup(tmpDir);
}

// -- Full Restore --

export async function cmdFullRestore(config: SnapshotConfig, timestamp?: string): Promise<void> {
  if (!timestamp) {
    await cmdList(config);
    const ts = await askTimestamp();
    return cmdFullRestore(config, ts);
  }

  const ts = validateTimestamp(timestamp);
  logger.banner("RESTAURACAO COMPLETA: " + ts);

  console.log("");
  logger.error("  ATENCAO: Isso vai sobrescrever arquivos do sistema!");
  logger.error("  Use SOMENTE em uma VPS nova/reformatada.");
  logger.error("  A restauracao NAO e bit-a-bit - a mesma distro e recomendada.");
  if (config.encryption.enabled) {
    logger.error("  Criptografia detectada - precisa da passphrase correta.");
  }
  console.log("");

  const confirmed = await askConfirm("Restaurar backup " + ts + " nesta VPS?");
  if (!confirmed) {
    logger.info("Restauracao cancelada");
    return;
  }

  const tmpDir = mkTempDir("vps-snapshot-restore-");
  const tarFile = await downloadAndPrepare(config, ts, tmpDir);

  logger.info("Extraindo backup para / (root)...");
  try {
    await runQuiet('tar -xzf "' + tarFile + '" --numeric-owner --overwrite -C / 2>&1');
    logger.success("Extracao concluida!");

    logger.info("Pos-restauracao...");
    await runQuiet("rm -f /etc/machine-id 2>/dev/null");
    await runQuiet("systemd-machine-id-setup 2>/dev/null");
    logger.success("machine-id regenerado");

    logger.dim("\n  IMPORTANTE: Reboot necessario!");
    logger.dim("  sudo shutdown -r now");
  } finally {
    await cleanup(tmpDir);
  }
}

// -- Status --

export async function cmdStatus(config: SnapshotConfig): Promise<void> {
  logger.banner("STATUS");

  const connected = await rcloneCheck(config.remoteName);
  if (connected) {
    logger.success(config.remoteName + ": conectado");
  } else {
    logger.error(config.remoteName + ": NAO conectado");
    logger.dim("  Configure: sudo rclone config");
    return;
  }

  const space = await rcloneSpace(config.remoteName);
  logger.info("Espaco: " + space.used + " usado, " + space.free + " livre");

  const baseRemote = rcloneRemote(config.remoteName, config.remotePath) + "/" + config.vpsName;
  const dirs = await rcloneList(baseRemote);
  logger.info("Backups de " + config.vpsName + ": " + dirs.length);

  if (dirs.length > 0) {
    logger.success("Ultimo backup: " + dirs[0].trim());
  }

  if (config.encryption.enabled) {
    logger.info("Criptografia: GPG habilitada");
  }

  const logFile = "/opt/vps-snapshot/backup.log";
  try {
    const exists = await runQuiet('test -f "' + logFile + '" && echo ok || echo no');
    if (exists === 0) {
      const lastLine = await run('tail -1 "' + logFile + '"', "log");
      logger.info("Ultimo log: " + lastLine);
    }
  } catch { /* ignore */ }
}

// -- Log --

export async function cmdLog(config: SnapshotConfig, lines = 20): Promise<void> {
  const logFile = "/opt/vps-snapshot/backup.log";
  try {
    const out = await run("tail -n " + lines + ' "' + logFile + '"', "log read");
    console.log(out);
  } catch {
    logger.warn("Nenhum log encontrado");
  }
}

// -- Config (mostrar) --

export async function cmdConfig(config: SnapshotConfig): Promise<void> {
  logger.banner("CONFIGURACAO ATUAL");
  const safeConfig: Record<string, unknown> = JSON.parse(JSON.stringify(config));
  if (safeConfig.encryption && (safeConfig.encryption as Record<string, unknown>).passphrase) {
    (safeConfig.encryption as Record<string, unknown>).passphrase = "***";
  }
  console.log(JSON.stringify(safeConfig, null, 2));
  logger.dim("\n  Editar: sudo nano /opt/vps-snapshot/config.json");
}

// -- Helpers internos --

/**
 * Download + concat + [decrypt] + verify integrity
 * Retorna caminho do tar.gz pronto para uso
 */
async function downloadAndPrepare(
  config: SnapshotConfig,
  timestamp: string,
  tmpDir: string,
): Promise<string> {
  const remoteDir = rcloneRemote(config.remoteName, config.remotePath) + "/" + config.vpsName + "/" + timestamp;

  const check = await runQuiet('rclone lsf "' + remoteDir + '" 2>/dev/null | head -1');
  if (!check) {
    die("Backup nao encontrado: " + timestamp + "\n  Use 'vps-snapshot list' para ver disponiveis");
  }

  const partsDir = tmpDir + "/parts";
  await run('mkdir -p "' + partsDir + '"', "mkdir parts");

  logger.info("Baixando backup " + timestamp + "...");
  await run('rclone copy "' + remoteDir + '" "' + partsDir + '" --progress --transfers 4 --checkers 8', "download");

  // -- Verificacao SHA256 --
  const sha256Files = (await run('ls -1 "' + partsDir + '/"*.sha256 2>/dev/null', "find sha256")).split("\n").filter(Boolean);
  if (sha256Files.length > 0) {
    logger.info("Verificando integridade SHA256...");
    for (const shaFile of sha256Files) {
      const manifestPath = partsDir + "/" + shaFile;
      await verifyChecksumManifest(partsDir, manifestPath);
    }
  } else {
    logger.warn("Nenhum manifesto SHA256 encontrado - verificacao de integridade pulada");
    logger.warn("Considere refazer o backup com versao atualizada para ter checksum");
  }

  // Listar parts e concatenar
  const isEncrypted = config.encryption.enabled;
  const ext = isEncrypted ? "*.tar.gz.gpg.part*" : "*.tar.gz.part*";
  const partFiles = (await run('ls -1 "' + partsDir + '/' + ext + '" 2>/dev/null | sort', "list parts")).split("\n").filter(Boolean);

  if (partFiles.length === 0) {
    const singleFiles = (await run('ls -1 "' + partsDir + '/"', "list dir")).split("\n").filter(Boolean);
    const dataFiles = singleFiles.filter((f) => !f.endsWith(".sha256"));
    if (dataFiles.length === 1) {
      const singlePath = partsDir + "/" + dataFiles[0];
      if (isEncrypted && dataFiles[0].endsWith(".gpg")) {
        return await decryptFile(singlePath, tmpDir, timestamp, config);
      }
      return singlePath;
    }
    die("Nenhum arquivo encontrado no backup");
  }

  const concatExt = isEncrypted ? ".tar.gz.gpg" : ".tar.gz";
  const concatFile = tmpDir + "/" + config.vpsName + "-" + timestamp + concatExt;
  const catCmd = partFiles.map((f) => '"' + f + '"').join(" ");
  await run("cat " + catCmd + ' > "' + concatFile + '"', "concat parts");
  logger.info("Concatenado " + partFiles.length + " partes");

  await run('rm -rf "' + partsDir + '"');

  if (isEncrypted) {
    return await decryptFile(concatFile, tmpDir, timestamp, config);
  }

  const testCode = await runQuiet('gzip -t "' + concatFile + '" 2>/dev/null');
  if (testCode !== 0) {
    die("Arquivo gzip corrompido! Download pode ter falhado.");
  }
  logger.success("Arquivo gzip valido");

  return concatFile;
}

async function decryptFile(
  gpgFile: string,
  tmpDir: string,
  timestamp: string,
  config: SnapshotConfig,
): Promise<string> {
  logger.info("Descriptografando com GPG...");
  const gzFile = tmpDir + "/" + config.vpsName + "-" + timestamp + ".tar.gz";
  await gpgDecrypt(gpgFile, gzFile, config.encryption);
  logger.success("Descriptografia OK");

  const testCode = await runQuiet('gzip -t "' + gzFile + '" 2>/dev/null');
  if (testCode !== 0) {
    die("Arquivo gzip corrompido apos descriptografia! Chave errada ou dado corrompido.");
  }
  logger.success("Arquivo gzip valido");

  await run('rm -f "' + gpgFile + '"');
  return gzFile;
}

async function cleanup(tmpDir: string): Promise<void> {
  try { await run('rm -rf "' + tmpDir + '"'); } catch { /* ignore */ }
}

async function askTimestamp(): Promise<string> {
  process.stdout.write("\n  Timestamp do backup: ");
  const ts = await new Promise<string>((resolve) => {
    process.stdin.once("data", (data) => resolve(data.toString().trim()));
    setTimeout(() => resolve(""), 30000);
  });
  if (!ts) die("Timestamp nao fornecido. Use: vps-snapshot browse <timestamp>");
  return ts;
}

async function askConfirm(msg: string): Promise<boolean> {
  process.stdout.write("  [!] " + msg + " [s/N]: ");
  const answer = await new Promise<string>((resolve) => {
    process.stdin.once("data", (data) => resolve(data.toString().trim().toLowerCase()));
    setTimeout(() => resolve("n"), 30000);
  });
  return answer === "s" || answer === "y" || answer === "sim" || answer === "yes";
}
