/**
 * VPS Snapshot — Configuração
 * Lê /opt/vps-snapshot/config.json e valida
 */

import { die } from "./logger";

const CONFIG_PATH = "/opt/vps-snapshot/config.json";

export interface EncryptionConfig {
  enabled: boolean;
  passphrase: string;
  /** email do recipient para gpg --encrypt (se vazio, usa symmetric) */
  recipient: string;
}

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
  /** Incluir info do sistema no metadata (hostname, distro, kernel) */
  includeSystemInfo: boolean;
  /** Criptografia GPG */
  encryption: EncryptionConfig;
}

export function loadConfig(overridePath?: string): SnapshotConfig {
  const path = overridePath || CONFIG_PATH;
  try {
    const file = Bun.file(path);
    const text = file.sizeSync() > 0 ? file.textSync() : "";
    if (!text) die(`Config vazio: ${path}`);
    const json = JSON.parse(text);
    return validate(json, path);
  } catch (e) {
    if ((e as NodeJS.ErrnoException).code === "ENOENT") {
      die(`Config nao encontrado: ${path}\n  Rode o instalador: curl -sSL https://raw.githubusercontent.com/amonmelo/vps-snapshot/main/install.sh | sudo bash`);
    }
    die(`Config invalido (${path}): ${(e as Error).message}`);
  }
}

function validate(raw: Record<string, unknown>, path: string): SnapshotConfig {
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
    includeSystemInfo: raw.includeSystemInfo === true,
    encryption: validateEncryption(raw.encryption),
  };

  if (!config.remoteName || config.remoteName.length < 1) {
    die("remoteName nao pode estar vazio");
  }

  // Validar encryption se habilitado
  if (config.encryption.enabled) {
    if (!config.encryption.recipient && !config.encryption.passphrase) {
      die("encryption habilitado mas sem recipient nem passphrase. Edite config.json");
    }
  }

  return config;
}

function validateEncryption(raw: unknown): EncryptionConfig {
  if (!raw || typeof raw !== "object") {
    return { enabled: false, passphrase: "", recipient: "" };
  }
  const e = raw as Record<string, unknown>;
  return {
    enabled: e.enabled === true,
    passphrase: typeof e.passphrase === "string" ? e.passphrase : "",
    recipient: typeof e.recipient === "string" ? sanitize(e.recipient, 256) : "",
  };
}

// ── Validação de input do usuário ──

/** Valida timestamp no formato YYYYMMDDHHmmss (14 dígitos) */
export function validateTimestamp(ts: string): string {
  const clean = ts.trim();
  if (!/^\d{14}$/.test(clean)) {
    die(`Timestamp invalido: "${clean}"\n  Formato: YYYYMMDDHHmmss (14 digitos)\n  Exemplo: 20250601150000`);
  }
  // Validar intervalo razoável (2020-2099)
  const year = parseInt(clean.slice(0, 4), 10);
  const month = parseInt(clean.slice(4, 6), 10);
  const day = parseInt(clean.slice(6, 8), 10);
  if (year < 2020 || year > 2099) die(`Ano invalido no timestamp: ${year}`);
  if (month < 1 || month > 12) die(`Mes invalido no timestamp: ${month}`);
  if (day < 1 || day > 31) die(`Dia invalido no timestamp: ${day}`);
  return clean;
}

/** Valida path de extração — deve ser absoluto, sem traversal */
export function validatePath(path: string): string {
  const clean = path.trim();
  if (!clean) die("Path vazio");
  if (!clean.startsWith("/")) die(`Path deve ser absoluto (começar com /): ${clean}`);
  if (clean.includes("..")) die(`Path com ".." nao permitido: ${clean}`);
  return clean;
}

/** Valida diretório de destino para extract — não pode ser / ou caminhos críticos */
export function validateDestDir(path: string): string {
  const clean = validatePath(path);
  const FORBIDDEN = ["/", "/bin", "/sbin", "/usr", "/etc", "/boot", "/dev", "/proc", "/sys"];
  if (FORBIDDEN.includes(clean)) {
    die(`Destino proibido: ${clean}. Use um dir temporario como /tmp/restored`);
  }
  return clean;
}

// ── Defaults ──

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

// ── Helpers ──

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
