/**
 * VPS Snapshot — Configuração
 * Lê /opt/vps-snapshot/config.json e valida
 */

import { die, logger } from "./logger";

const CONFIG_PATH = "/opt/vps-snapshot/config.json";

export interface SnapshotConfig {
  vpsName: string;
  remoteName: string;
  remotePath: string;
  keepBackups: number;
  compressionLevel: number;
  splitSize: string;
  excludeDockerImages: boolean;
  excludePatterns: string[];
  excludePaths: string[];
  preBackupCommands: string[];
  postBackupCommands: string[];
}

export function loadConfig(overridePath?: string): SnapshotConfig {
  const path = overridePath || CONFIG_PATH;
  try {
    const raw = Bun.file(path);
    const json = JSON.parse(raw.textSync ? raw.textSync() : "");
    return validate(json);
  } catch (e) {
    if ((e as NodeJS.ErrnoException).code === "ENOENT") {
      die(`Config nao encontrado: ${path}\n  Rode o instalador: curl -sSL https://raw.githubusercontent.com/amonmelo/vps-snapshot/main/install.sh | sudo bash`);
    }
    die(`Config invalido (${path}): ${(e as Error).message}`);
  }
}

function validate(raw: Record<string, unknown>): SnapshotConfig {
  const config: SnapshotConfig = {
    vpsName: sanitize(String(raw.vpsName ?? "vps-default"), 64),
    remoteName: sanitize(String(raw.remoteName ?? "remote"), 128),
    remotePath: sanitize(String(raw.remotePath ?? "Backup-VPS"), 512),
    keepBackups: clamp(Number(raw.keepBackups) || 5, 1, 365),
    compressionLevel: clamp(Number(raw.compressionLevel) || 6, 1, 9),
    splitSize: parseSplitSize(String(raw.splitSize ?? "4G")),
    excludeDockerImages: raw.excludeDockerImages === true,
    excludePatterns: Array.isArray(raw.excludePatterns)
      ? raw.excludePatterns.map((p: unknown) => sanitize(String(p), 256))
      : DEFAULT_PATTERNS,
    excludePaths: Array.isArray(raw.excludePaths)
      ? raw.excludePaths.map((p: unknown) => sanitize(String(p), 512))
      : DEFAULT_PATHS,
    preBackupCommands: Array.isArray(raw.preBackupCommands)
      ? raw.preBackupCommands.map((c: unknown) => String(c))
      : [],
    postBackupCommands: Array.isArray(raw.postBackupCommands)
      ? raw.postBackupCommands.map((c: unknown) => String(c))
      : [],
  };

  if (!config.remoteName || config.remoteName.length < 1) {
    die("remoteName nao pode estar vazio");
  }

  return config;
}

const DEFAULT_PATTERNS = [
  "*.log", "*.tmp", "*.pid", "*.sock", "*.swap", "nohup.out",
  "*/node_modules", "*/__pycache__", "*/.cache", "*/.npm",
  "*/.pip", "*/.cargo/registry", "*/go/pkg/mod/cache",
];

const DEFAULT_PATHS = [
  "/proc", "/sys", "/dev", "/run", "/tmp",
  "/snap", "/boot/efi",
  "/var/cache/apt/archives", "/var/cache/yum", "/var/cache/dnf",
  "/var/lib/apt/lists",
  "/opt/vps-snapshot",
];

function sanitize(s: string, maxLen: number): string {
  return s.replace(/[^\w/.:_ -]/g, "").slice(0, maxLen);
}

function clamp(n: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, n));
}

function parseSplitSize(s: string): string {
  if (/^\d+[MGK]$/i.test(s)) return s.toUpperCase();
  return "4G";
}

export { DEFAULT_PATTERNS, DEFAULT_PATHS };
