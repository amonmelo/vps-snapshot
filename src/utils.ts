/**
 * VPS Snapshot — Utilitários
 * rclone, flock, retry, mktemp, sistema
 */

import { die, logger } from "./logger";

// ── Execução de shell ──

export async function run(cmd: string, label?: string): Promise<string> {
  logger.debug(`$ ${cmd}`);
  try {
    const proc = $({ stdio: ["pipe", "pipe", "pipe"] }).nothrow();
    const result = await proc`${cmd}`;
    const stdout = result.stdout.toString().trim();
    if (result.exitCode !== 0) {
      const stderr = result.stderr.toString().trim();
      throw new Error(`${label || cmd} falhou (exit ${result.exitCode}): ${stderr || stdout}`);
    }
    return stdout;
  } catch (e) {
    if (e instanceof Error) throw e;
    throw new Error(`${label || cmd} falhou: ${e}`);
  }
}

export async function runQuiet(cmd: string): Promise<number> {
  try {
    const proc = $({ stdio: ["pipe", "pipe", "pipe"] }).nothrow();
    const result = await proc`${cmd}`;
    return result.exitCode ?? 0;
  } catch {
    return -1;
  }
}

// ── Retry com exponential backoff ──

export async function retry<T>(
  fn: () => Promise<T>,
  maxAttempts = 3,
  baseDelayMs = 2000,
  label = "operacao",
): Promise<T> {
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (e) {
      const delay = baseDelayMs * Math.pow(2, attempt - 1);
      if (attempt === maxAttempts) {
        die(`${label} falhou apos ${maxAttempts} tentativas: ${(e as Error).message}`);
      }
      logger.warn(`${label} tentativa ${attempt}/${maxAttempts} falhou. Retentando em ${delay / 1000}s...`);
      await sleep(delay);
    }
  }
  throw new Error("unreachable");
}

// ── Lock com flock ──

let lockFd: number | null = null;
const LOCK_PATH = "/tmp/vps-snapshot.lock";

export function acquireLock(): void {
  if (!lockFd) {
    try {
      lockFd = Bun.open(LOCK_PATH, "w").fd;
      if (!lockFd) throw new Error("nao abriu");
    } catch {
      die("Nao conseguiu criar lock file");
    }
  }

  const result = Bun.spawnSync(["flock", "-n", String(lockFd)], {
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
  });

  if (result.exitCode !== 0) {
    die("Outro backup ja esta rodando. Aguarde ou mate: rm /tmp/vps-snapshot.lock");
  }

  logger.debug("Lock adquirido");
}

export function releaseLock(): void {
  if (lockFd !== null) {
    try { Bun.close(lockFd); } catch { /* ignore */ }
    lockFd = null;
    try { unlinkSync("/tmp/vps-snapshot.lock"); } catch { /* ignore */ }
  }
}

// ── mktemp seguro ──

export function mkTempDir(prefix = "vps-snapshot-"): string {
  const template = `/tmp/${prefix}XXXXXX`;
  const result = Bun.spawnSync(["mktemp", "-d", template], {
    stdout: "pipe",
    stderr: "pipe",
  });
  const dir = result.stdout.toString().trim();
  if (!dir) die("mktemp falhou");
  return dir;
}

export function mkTempFile(prefix = "vps-snapshot-"): string {
  const template = `/tmp/${prefix}XXXXXX`;
  const result = Bun.spawnSync(["mktemp", template], {
    stdout: "pipe",
    stderr: "pipe",
  });
  const file = result.stdout.toString().trim();
  if (!file) die("mktemp falhou");
  return file;
}

// ── Rclone helpers ──

export function rcloneRemote(remoteName: string, remotePath: string): string {
  return `${remoteName}:${remotePath}`;
}

export async function rcloneCheck(remoteName: string): Promise<boolean> {
  const code = await runQuiet(`rclone lsd "${remoteName}:" 2>/dev/null`);
  return code === 0;
}

export async function rcloneMkdir(remote: string): Promise<void> {
  await run(`rclone mkdir "${remote}"`, "rclone mkdir");
}

export async function rcloneUpload(
  local: string,
  remote: string,
  label = "upload",
): Promise<void> {
  await retry(
    async () => {
      await run(
        `rclone copy "${local}" "${remote}" --progress --transfers 4 --checkers 8`,
        label,
      );
    },
    3,
    5000,
    label,
  );
}

export async function rcloneDownload(
  remote: string,
  local: string,
  label = "download",
): Promise<void> {
  await retry(
    async () => {
      await run(
        `rclone copy "${remote}" "${local}" --progress --transfers 4 --checkers 8`,
        label,
      );
    },
    3,
    5000,
    label,
  );
}

export async function rcloneList(remote: string): Promise<string[]> {
  const out = await run(`rclone lsf "${remote}" --sort-by modtime --order-by desc`, "rclone list");
  return out.split("\n").filter(Boolean).map((s) => s.trim());
}

export async function rcloneDelete(remote: string): Promise<void> {
  await run(`rclone purge "${remote}"`, "rclone delete");
}

export async function rcloneSize(remote: string): Promise<string> {
  return await run(`rclone size "${remote}"`, "rclone size");
}

export async function rcloneSpace(remoteName: string): Promise<{ used: string; free: string }> {
  const out = await run(`rclone about "${remoteName}:" --json 2>/dev/null || echo '{}'`, "rclone about");
  try {
    const j = JSON.parse(out);
    return {
      used: formatBytes(j.used ?? 0),
      free: formatBytes(j.free ?? 0),
    };
  } catch {
    return { used: "?", free: "?" };
  }
}

// ── Info do sistema ──

export function systemInfo(): { hostname: string; kernel: string; arch: string; distro: string } {
  const hostname = process.env.HOSTNAME || "unknown";
  const kernel = Bun.spawnSync(["uname", "-r"], { stdout: "pipe" }).stdout.toString().trim();
  const arch = process.arch || Bun.spawnSync(["uname", "-m"], { stdout: "pipe" }).stdout.toString().trim();
  const distro = Bun.spawnSync(["cat", "/etc/os-release"], { stdout: "pipe" })
    .stdout.toString()
    .split("\n")
    .find((l) => l.startsWith("PRETTY_NAME="))
    ?.replace("PRETTY_NAME=", "")
    .replace(/"/g, "")
    .trim() || "Linux";

  return { hostname, kernel, arch, distro };
}

// ── Helpers ──

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

function formatBytes(bytes: number): string {
  if (bytes === 0) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB"];
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  return `${(bytes / Math.pow(1024, i)).toFixed(1)} ${units[i]}`;
}

function unlinkSync(path: string): void {
  try { require("fs").unlinkSync(path); } catch { /* ignore */ }
}
