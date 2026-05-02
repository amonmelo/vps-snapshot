#!/usr/bin/env bun
/**
 * VPS Snapshot — Entry Point
 * Backup completo de VPS para nuvem via rclone
 *
 * Comandos:
 *   vps-snapshot estimate           Estimar tamanho do backup
 *   vps-snapshot [run]              Executar backup
 *   vps-snapshot list               Listar backups na nuvem
 *   vps-snapshot browse [timestamp] Navegar conteudo do backup
 *   vps-snapshot extract <ts> <path> [path...] [--dest /dir]
 *   vps-snapshot full [timestamp]   Restauracao completa
 *   vps-snapshot log [N]            Ver log (ultimas N linhas)
 *   vps-snapshot status             Status do provedor
 *   vps-snapshot config             Mostrar configuracao
 *
 * Flags:
 *   -v, --verbose   Debug logging
 *   -c, --config    Caminho do config.json
 *   -h, --help      Ajuda
 */

import { setVerbose, logger, die } from "./logger";
import { loadConfig } from "./config";
import { systemInfo } from "./utils";
import { cmdEstimate, cmdBackup } from "./backup";
import { cmdList, cmdBrowse, cmdExtract, cmdFullRestore, cmdStatus, cmdLog, cmdConfig } from "./restore";

const VERSION = "1.0.0";

function printHelp(): void {
  console.log(`
  VPS Snapshot v${VERSION} — Backup completo de VPS para nuvem

  USO:
    vps-snapshot <comando> [opcoes]

  COMANDOS:
    estimate             Estimar tamanho do backup
    run                  Executar backup completo
    list                 Listar backups na nuvem
    browse [timestamp]   Navegar conteudo de um backup
    extract <ts> <paths> Extrair arquivos especificos
    full [timestamp]     Restauracao completa (aviso!)
    log [N]              Ver log (default: 20 linhas)
    status               Status do provedor de nuvem
    config               Mostrar configuracao atual

  OPCOES:
    -v, --verbose   Log debug
    -c, --config    Config alternativo
    -h, --help      Esta ajuda

  EXEMPLOS:
    vps-snapshot estimate
    vps-snapshot run
    vps-snapshot list
    vps-snapshot browse 20250601030000
    vps-snapshot extract 20250601030000 /etc/nginx /home/user --dest /tmp/restore
    vps-snapshot full 20250601030000
    vps-snapshot log 50
    vps-snapshot status
`);
}

function parseArgs(args: string[]): { command: string; flags: Record<string, string>; positional: string[] } {
  const flags: Record<string, string> = {};
  const positional: string[] = [];

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "-v" || arg === "--verbose") {
      flags.verbose = "true";
    } else if (arg === "-h" || arg === "--help") {
      flags.help = "true";
    } else if ((arg === "-c" || arg === "--config") && i + 1 < args.length) {
      flags.config = args[++i];
    } else {
      positional.push(arg);
    }
  }

  const command = positional[0] || "run";
  return { command, flags, positional: positional.slice(1) };
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const { command, flags, positional } = parseArgs(args);

  // Verbose
  if (flags.verbose) setVerbose(true);

  // Help
  if (flags.help || command === "help") {
    printHelp();
    process.exit(0);
  }

  // Versao
  if (command === "version" || command === "--version" || command === "-V") {
    console.log(`vps-snapshot v${VERSION}`);
    process.exit(0);
  }

  // Root check para comandos que precisam
  const needsRoot = ["run", "estimate", "full", "extract"];
  if (needsRoot.includes(command) && process.getuid?.() !== 0) {
    die("Execute como root: sudo vps-snapshot " + command);
  }

  // Carregar config
  const config = loadConfig(flags.config);

  // Dispatch
  switch (command) {
    case "estimate":
      await cmdEstimate(config);
      break;

    case "run":
    case "backup":
      await cmdBackup(config);
      break;

    case "list":
    case "ls":
      await cmdList(config);
      break;

    case "browse":
      await cmdBrowse(config, positional[0]);
      break;

    case "extract": {
      if (positional.length < 2) {
        die("Uso: vps-snapshot extract <timestamp> <path1> [path2...] [--dest /dir]");
      }
      const ts = positional[0];
      const paths: string[] = [];
      let destDir = "";
      for (let i = 1; i < positional.length; i++) {
        if (positional[i] === "--dest" && i + 1 < positional.length) {
          destDir = positional[++i];
        } else {
          paths.push(positional[i]);
        }
      }
      await cmdExtract(config, ts, paths, destDir);
      break;
    }

    case "full":
    case "restore":
      await cmdFullRestore(config, positional[0]);
      break;

    case "log":
      await cmdLog(config, Number(positional[0]) || 20);
      break;

    case "status":
      await cmdStatus(config);
      break;

    case "config":
      await cmdConfig(config);
      break;

    default:
      logger.error(`Comando desconhecido: ${command}`);
      printHelp();
      process.exit(1);
  }
}

main().catch((e) => {
  logger.error(`Erro fatal: ${(e as Error).message}`);
  if (process.env.DEBUG) {
    console.error((e as Error).stack);
  }
  process.exit(1);
});
