/**
 * VPS Snapshot — Motor de Restore
 * list, browse, extract, full restore
 */

import { mkTempDir, run, rcloneRemote, rcloneList, rcloneDownload, rcloneSize, rcloneSpace, runQuiet } from "./utils";
import { logger, die } from "./logger";
import type { SnapshotConfig } from "./config";

// ── List backups ──

export async function cmdList(config: SnapshotConfig): Promise<void> {
  logger.banner("BACKUPS DISPONIVEIS");

  const baseRemote = `${rcloneRemote(config.remoteName, config.remotePath)}/${config.vpsName}`;
  const dirs = await rcloneList(baseRemote);

  if (dirs.length === 0) {
    logger.warn("Nenhum backup encontrado");
    return;
  }

  logger.info(`VPS: ${config.vpsName} | Total: ${dirs.length} backup(s)\n`);

  console.log("  #   Timestamp              Arquivos   Tamanho");
  console.log("  ─   ──────────────────     ────────   ───────");

  for (let i = 0; i < dirs.length; i++) {
    const d = dirs[i].trim();
    if (!d) continue;
    const fullRemote = `${baseRemote}/${d}`;

    let size = "?";
    try {
      size = await rcloneSize(fullRemote);
    } catch { /* skip */ }

    // Contar parts
    let files = "?";
    try {
      const parts = await rcloneList(fullRemote);
      files = String(parts.length);
    } catch { /* skip */ }

    const num = String(i + 1).padStart(2);
    console.log(`  ${num}  ${d.padEnd(23)} ${files.padStart(7)}   ${size}`);
  }

  console.log("");
  logger.dim("  Use: vps-snapshot browse <timestamp>  para navegar");
  logger.dim("  Use: vps-snapshot full <timestamp>    para restaurar tudo");
}

// ── Browse (listar conteudo do tar) ──

export async function cmdBrowse(config: SnapshotConfig, timestamp?: string): Promise<void> {
  if (!timestamp) {
    // Listar e pedir escolha
    await cmdList(config);
    const ts = await askTimestamp();
    return cmdBrowse(config, ts);
  }

  logger.banner(`NAVEGANDO: ${timestamp}`);
  const tmpDir = mkTempDir("vps-snapshot-browse-");
  const tarFile = await downloadAndConcat(config, timestamp, tmpDir);

  logger.info("Listando conteudo do backup...\n");
  try {
    const out = await run(`tar -tzf "${tarFile}" | head -100`, "browse");
    const lines = out.split("\n").filter(Boolean);
    console.log(`  Mostrando ${lines.length} primeiros itens (de muitos):\n`);
    for (const line of lines) {
      console.log(`  ${line}`);
    }
    if (lines.length === 100) {
      logger.dim("\n  ... (lista truncada. Use extract para arquivos especificos)");
    }
    logger.dim(`\n  Total de itens no backup: estimando...`);
    const total = await run(`tar -tzf "${tarFile}" | wc -l`, "count");
    logger.info(`Total: ${total.trim()} itens`);
  } finally {
    await cleanup(tmpDir, tarFile);
  }
}

// ── Extract (extrair arquivos especificos) ──

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

  logger.banner(`EXTRAINDO: ${timestamp}`);
  const tmpDir = mkTempDir("vps-snapshot-extract-");
  const tarFile = await downloadAndConcat(config, timestamp, tmpDir);

  // Garantir dest dir
  const realDest = destDir || `/tmp/vps-snapshot-restored-${timestamp}`;
  await run(`mkdir -p "${realDest}"`, "mkdir dest");

  for (const pattern of patterns) {
    if (pattern === "--dest") continue;
    logger.info(`Extraindo: ${pattern} -> ${realDest}`);
    try {
      await run(
        `tar -xzf "${tarFile}" -C "${realDest}" "${pattern}"`,
        `extract ${pattern}`,
      );
      logger.success(`  OK: ${pattern}`);
    } catch (e) {
      logger.error(`  Falha: ${pattern} — ${(e as Error).message}`);
    }
  }

  logger.success(`\nExtraido para: ${realDest}`);
  await cleanup(tmpDir, tarFile);
}

// ── Full Restore ──

export async function cmdFullRestore(config: SnapshotConfig, timestamp?: string): Promise<void> {
  if (!timestamp) {
    await cmdList(config);
    const ts = await askTimestamp();
    return cmdFullRestore(config, ts);
  }

  logger.banner(`RESTAURACAO COMPLETA: ${timestamp}`);

  // Aviso critico
  console.log("");
  logger.error("  ATENCAO: Isso vai sobrescrever arquivos do sistema!");
  logger.error("  Use SOMENTE em uma VPS nova/reformatada.");
  logger.error("  A restauracao NAO e bit-a-bit — a mesma distro e recomendada.");
  console.log("");

  // Confirmacao interativa
  const confirmed = await askConfirm(`Restaurar backup ${timestamp} nesta VPS?`);
  if (!confirmed) {
    logger.info("Restauracao cancelada");
    return;
  }

  const tmpDir = mkTempDir("vps-snapshot-restore-");
  const tarFile = await downloadAndConcat(config, timestamp, tmpDir);

  logger.info("Extraindo backup para / (root)...");
  try {
    const result = await runQuiet(
      `tar -xzf "${tarFile}" --numeric-owner --overwrite -C / 2>&1`,
    );

    logger.success("Extracao concluida!");

    // Pos-restore: regenerar machine-id
    logger.info("Pos-restauracao...");
    await runQuiet("rm -f /etc/machine-id 2>/dev/null");
    await runQuiet("systemd-machine-id-setup 2>/dev/null");
    logger.success("machine-id regenerado");

    logger.dim("\n  IMPORTANTE: Reboot necessario!");
    logger.dim("  sudo shutdown -r now");
  } finally {
    await cleanup(tmpDir, tarFile);
  }
}

// ── Status ──

export async function cmdStatus(config: SnapshotConfig): Promise<void> {
  logger.banner("STATUS");

  const connected = await rcloneCheck(config.remoteName);
  if (connected) {
    logger.success(`${config.remoteName}: conectado`);
  } else {
    logger.error(`${config.remoteName}: NAO conectado`);
    logger.dim("  Configure: sudo rclone config");
    return;
  }

  const space = await rcloneSpace(config.remoteName);
  logger.info(`Espaco: ${space.used} usado, ${space.free} livre`);

  const baseRemote = `${rcloneRemote(config.remoteName, config.remotePath)}/${config.vpsName}`;
  const dirs = await rcloneList(baseRemote);
  logger.info(`Backups de ${config.vpsName}: ${dirs.length}`);

  // Ultimo backup
  if (dirs.length > 0) {
    logger.success(`Ultimo backup: ${dirs[0].trim()}`);
  }

  // Log file
  const logFile = "/opt/vps-snapshot/backup.log";
  try {
    const exists = await runQuiet(`test -f "${logFile}" && echo ok || echo no`);
    if (exists === 0) {
      const lastLine = await run(`tail -1 "${logFile}"`, "log");
      logger.info(`Ultimo log: ${lastLine}`);
    }
  } catch { /* ignore */ }
}

// ── Log ──

export async function cmdLog(config: SnapshotConfig, lines = 20): Promise<void> {
  const logFile = "/opt/vps-snapshot/backup.log";
  try {
    const out = await run(`tail -n ${lines} "${logFile}"`, "log read");
    console.log(out);
  } catch {
    logger.warn("Nenhum log encontrado");
  }
}

// ── Config (mostrar) ──

export async function cmdConfig(config: SnapshotConfig): Promise<void> {
  logger.banner("CONFIGURACAO ATUAL");
  console.log(JSON.stringify(config, null, 2));
  logger.dim("\n  Editar: sudo nano /opt/vps-snapshot/config.json");
}

// ── Helpers internos ──

async function downloadAndConcat(
  config: SnapshotConfig,
  timestamp: string,
  tmpDir: string,
): Promise<string> {
  const remoteDir = `${rcloneRemote(config.remoteName, config.remotePath)}/${config.vpsName}/${timestamp}`;

  // Verificar se backup existe
  const check = await runQuiet(`rclone lsf "${remoteDir}" 2>/dev/null | head -1`);
  if (!check) {
    die(`Backup nao encontrado: ${timestamp}\n  Use 'vps-snapshot list' para ver disponiveis`);
  }

  // Download das parts
  const partsDir = `${tmpDir}/parts`;
  await run(`mkdir -p "${partsDir}"`, "mkdir parts");

  logger.info(`Baixando backup ${timestamp}...`);
  await run(`rclone copy "${remoteDir}" "${partsDir}" --progress --transfers 4 --checkers 8`, "download");

  // Listar parts e concatenar
  const partFiles = (await run(`ls -1 "${partsDir}"/*.part* 2>/dev/null | sort`, "list parts")).split("\n").filter(Boolean);

  if (partFiles.length === 0) {
    // Talvez seja um unico arquivo
    const singleFile = (await run(`ls -1 "${partsDir}/"`, "list dir")).split("\n").filter(Boolean);
    if (singleFile.length === 1) {
      return `${partsDir}/${singleFile[0]}`;
    }
    die("Nenhum arquivo encontrado no backup");
  }

  // Concatenar
  const tarGzFile = `${tmpDir}/${config.vpsName}-${timestamp}.tar.gz`;
  const catCmd = partFiles.map((f) => `"${f}"`).join(" ");
  await run(`cat ${catCmd} > "${tarGzFile}"`, "concat parts");
  logger.info(`Concatenado ${partFiles.length} partes`);

  // Limpar parts
  await run(`rm -rf "${partsDir}"`);

  // Verificar gzip
  const testCode = await runQuiet(`gzip -t "${tarGzFile}" 2>/dev/null`);
  if (testCode !== 0) {
    die("Arquivo gzip corrompido! Download pode ter falhado.");
  }
  logger.success("Arquivo gzip valido");

  return tarGzFile;
}

async function cleanup(tmpDir: string, tarFile?: string): Promise<void> {
  try {
    await run(`rm -rf "${tmpDir}"`);
  } catch { /* ignore */ }
}

async function askTimestamp(): Promise<string> {
  process.stdout.write("\n  Timestamp do backup: ");
  const ts = await new Promise<string>((resolve) => {
    process.stdin.once("data", (data) => {
      resolve(data.toString().trim());
    });
    // Timeout 30s
    setTimeout(() => resolve(""), 30000);
  });

  if (!ts) {
    die("Timestamp nao fornecido. Use: vps-snapshot browse <timestamp>");
  }
  return ts;
}

async function askConfirm(msg: string): Promise<boolean> {
  process.stdout.write(`  [!] ${msg} [s/N]: `);
  const answer = await new Promise<string>((resolve) => {
    process.stdin.once("data", (data) => {
      resolve(data.toString().trim().toLowerCase());
    });
    setTimeout(() => resolve("n"), 30000);
  });
  return answer === "s" || answer === "y" || answer === "sim" || answer === "yes";
}
