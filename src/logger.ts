/**
 * VPS Snapshot — Logger padronizado
 * Formato: [LEVEL] mensagem
 */

type LogLevel = "DEBUG" | "INFO" | "WARN" | "ERROR" | "SUCCESS";

const COLORS: Record<LogLevel, string> = {
  DEBUG: "\x1b[2m",
  INFO: "\x1b[36m",
  WARN: "\x1b[1;33m",
  ERROR: "\x1b[0;31m",
  SUCCESS: "\x1b[0;32m",
};

const RESET = "\x1b[0m";
const DIM = "\x1b[2m";
const BOLD = "\x1b[1m";

let verbose = false;

export function setVerbose(v: boolean) {
  verbose = v;
}

function log(level: LogLevel, msg: string, ...args: unknown[]) {
  if (level === "DEBUG" && !verbose) return;

  const color = COLORS[level];
  const prefix = `${color}[${level}]${RESET}`;
  const text = args.length > 0 ? msg.replace(/%s/g, () => String(args.shift())) : msg;

  if (level === "ERROR") {
    console.error(`${prefix} ${text}`);
  } else {
    console.log(`${prefix} ${text}`);
  }
}

export const logger = {
  debug: (msg: string, ...args: unknown[]) => log("DEBUG", msg, ...args),
  info: (msg: string, ...args: unknown[]) => log("INFO", msg, ...args),
  warn: (msg: string, ...args: unknown[]) => log("WARN", msg, ...args),
  error: (msg: string, ...args: unknown[]) => log("ERROR", msg, ...args),
  success: (msg: string, ...args: unknown[]) => log("SUCCESS", msg, ...args),
  banner: (text: string) => {
    console.log(`\n${BOLD}${COLORS.INFO}${text}${RESET}\n`);
  },
  dim: (text: string) => console.log(`${DIM}${text}${RESET}`),
};

/** Die com mensagem de erro e exit(1) */
export function die(msg: string): never {
  logger.error(msg);
  process.exit(1);
}
