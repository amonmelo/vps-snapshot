<p align="center">
  <img src="assets/logo.svg" alt="VPS Snapshot" width="480">
</p>

<p align="center">
  <strong>English</strong> · <a href="README.pt-BR.md">Portugues</a>
</p>

<p align="center">
  <strong>Full-disk VPS backup to the cloud. One command to install, one command to run.</strong>
</p>

<p align="center">
  <a href="#-quick-start">Quick Start</a> ·
  <a href="#-features">Features</a> ·
  <a href="#-supported-providers">Providers</a> ·
  <a href="#%EF%B8%8F-configuration">Configuration</a> ·
  <a href="#-security">Security</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Bun-1.0.0-black?style=flat-square&logo=bun&logoColor=white" alt="Bun">
  <img src="https://img.shields.io/badge/License-MIT-blue?style=flat-square" alt="MIT License">
  <img src="https://img.shields.io/badge/Linux-x86__64%20%7C%20ARM64-yellow?style=flat-square&logo=linux&logoColor=white" alt="Linux">
  <img src="https://img.shields.io/badge/Cloud-70%2B%20providers-ff69b4?style=flat-square" alt="Providers">
  <img src="https://img.shields.io/badge/Install-1%20command-success?style=flat-square" alt="One command install">
</p>

---

## Why?

Most VPS backup tools are either too complex (Borg, Duplicity) or too limited (simple cron + rsync). **VPS Snapshot hits the sweet spot** — full disk snapshot with selective restore, encrypted, verified, and ready in 60 seconds.

**The problem it solves:** Your VPS has custom configs, scripts, SSH keys, cron jobs, Docker setups that took hours to configure. If it dies, you're starting from zero. VPS Snapshot captures *everything* and lets you restore *exactly* what you need.

---

## Quick Start

```bash
# Install (one command — interactive installer)
curl -sSL https://raw.githubusercontent.com/amonmelo/vps-snapshot/main/install.sh | sudo bash
```

That's it. The installer handles everything:

```
 ╔═══════════════════════════════════════════════════╗
 ║           VPS SNAPSHOT                            ║
 ║           Backup completo da sua VPS              ║
 ║           Feito com Bun — rapido e seguro         ║
 ╚═══════════════════════════════════════════════════╝

  Sistema: my-server
  Kernel:  6.6.87 (x86_64)
  Disco:   45G livres

  ? Nome desta VPS [my-server]:
  ? Provedor [OneDrive (5 GB gratis)]:
  ? Frequencia [Diario as 3h (recomendado)]:
  ? Compressao (1=rapido 9=maximo) [6]:
  ? Criptografar backups com GPG? [s/N]:

  [✓] Bun 1.3.13 instalado
  [✓] rclone instalado
  [✓] pigz instalado (compressao paralela disponivel)
  [✓] Cron: Diario 3h

  Comandos:
    sudo vps-snapshot estimate    Estimar tamanho
    sudo vps-snapshot             Backup manual
    sudo vps-snapshot list        Listar backups
```

### First backup

```bash
# Estimate size first (recommended)
sudo vps-snapshot estimate

# Run your first backup
sudo vps-snapshot
```

### Restore

```bash
# List available backups
sudo vps-snapshot list

# Browse what's inside
sudo vps-snapshot browse 20250601150000

# Extract specific paths
sudo vps-snapshot extract 20250601150000 /etc/nginx /home/user --dest /tmp/restored

# Full restore (on a fresh VPS!)
sudo vps-snapshot full 20250601150000
```

---

## Features

- **One-command install** — Interactive guided installer, zero dependencies knowledge required
- **Full disk snapshot** — Captures `/root`, `/home`, `/etc`, `/opt`, `/var`, Docker configs, cron jobs, SSH keys, systemd services
- **Selective restore** — Extract only `/etc/nginx` or `/home/user`, not the entire backup
- **Browse mode** — Navigate backup contents without downloading everything
- **70+ cloud providers** — OneDrive, Google Drive, Dropbox, S3, Backblaze, SFTP, and more via rclone
- **GPG encryption** — AES-256 symmetric or public key encryption (optional)
- **SHA-256 verification** — Mandatory integrity check on upload and download. Fails closed, never silently.
- **Auto-split** — Splits large backups into 4GB parts (OneDrive upload limit)
- **Parallel compression** — Uses `pigz` when available, falls back to `gzip`
- **Auto rotation** — Keep N backups, oldest deleted automatically
- **Cron scheduling** — Daily, weekly, biweekly, monthly, or manual
- **Works everywhere** — Ubuntu, Debian, CentOS, Fedora, Arch, Alpine, SUSE, any x86_64 or ARM64 Linux

---

## Supported Providers

| Provider | Free Tier | Setup |
|----------|-----------|-------|
| Microsoft OneDrive | 5 GB | OAuth (browser or token) |
| Google Drive | 15 GB | OAuth |
| MEGA | 20 GB | OAuth |
| Backblaze B2 | 10 GB | API key |
| pCloud | 10 GB | OAuth |
| Dropbox | 2 GB | OAuth |
| Amazon S3 | 5 GB | Access key |
| SFTP | — | Host + credentials |

...and 60+ more via [rclone](https://rclone.org/#providers).

---

## How It Works

```
tar (root /)
  → pigz (parallel compress)
    → [GPG encrypt]
      → split (4GB parts)
        → SHA-256 manifest
          → rclone upload
            → verify integrity
```

**What gets backed up:** Everything on disk — system configs, user files, Docker setups, SSH keys, cron jobs, systemd services, custom scripts.

**What gets excluded** (auto):

| Category | Paths |
|----------|-------|
| Virtual filesystems | `/proc`, `/sys`, `/dev`, `/run` |
| Package caches | `/var/cache/apt`, `/var/cache/yum`, `/var/cache/dnf` |
| Language caches | `node_modules`, `__pycache__`, `.cache`, `.npm` |
| Build caches | `.cargo/registry`, `go/pkg/mod` |
| Docker images | `/var/lib/docker/*` (optional) |
| Swap | `/swapfile` |
| Tool itself | `/opt/vps-snapshot` |

All exclusions are configurable via `config.json`.

---

## Configuration

Edit `/opt/vps-snapshot/config.json` after install:

```json
{
  "vpsName": "my-server",
  "remoteName": "onedrive",
  "remotePath": "Backup-VPS",
  "keepBackups": 5,
  "compressionLevel": 6,
  "splitSize": "4G",
  "excludeDockerImages": true,
  "encryption": {
    "enabled": false,
    "passphrase": "",
    "recipient": ""
  },
  "includeSystemInfo": false
}
```

<details>
<summary>Full config reference</summary>

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `vpsName` | string | hostname | VPS identifier (used in cloud folder structure) |
| `remoteName` | string | `onedrive` | rclone remote name |
| `remotePath` | string | `Backup-VPS` | Root folder in cloud provider |
| `keepBackups` | number | `5` | Max backups to retain (auto-rotation) |
| `compressionLevel` | number | `6` | 1 (fast) to 9 (max) |
| `splitSize` | string | `4G` | Max size per part (cloud upload limit) |
| `excludeDockerImages` | bool | `false` | Exclude Docker image layers (~2GB+ savings) |
| `excludePatterns` | string[] | `["*.log", ...]` | Glob patterns to exclude |
| `excludePaths` | string[] | `["/proc", ...]` | Absolute paths to exclude |
| `preBackupCommands` | string[] | `[]` | Shell commands before backup |
| `postBackupCommands` | string[] | `[]` | Shell commands after backup |
| `includeSystemInfo` | bool | `false` | Include hostname/distro in metadata |
| `encryption.enabled` | bool | `false` | Enable GPG encryption |
| `encryption.passphrase` | string | `""` | Symmetric passphrase (AES-256) |
| `encryption.recipient` | string | `""` | GPG recipient email (public key) |

</details>

---

## All Commands

| Command | Description |
|---------|-------------|
| `vps-snapshot` | Run backup |
| `vps-snapshot estimate` | Estimate backup size |
| `vps-snapshot list` | List backups in cloud |
| `vps-snapshot browse [ts]` | Browse backup contents |
| `vps-snapshot extract <ts> <paths> [--dest /dir]` | Extract specific paths |
| `vps-snapshot full [ts]` | Full restore (fresh VPS) |
| `vps-snapshot log [N]` | Show last N log lines |
| `vps-snapshot status` | Provider status + space |
| `vps-snapshot config` | Display current config |

Global flags: `-v` (verbose), `-c /path/config.json` (custom config), `-h` (help)

---

## Security

| Layer | Implementation |
|-------|---------------|
| **No eval** | All shell commands use `Bun.spawn()` with argument arrays — never string interpolation |
| **Unpredictable lock** | `flock` with `mktemp` path — prevents symlink attacks on `/tmp` |
| **Input sanitization** | Installer escapes `\ " \n \r \t` before writing `config.json` — prevents JSON injection |
| **PII control** | Hostname, distro, kernel excluded from metadata by default (`includeSystemInfo: false`) |
| **Mandatory integrity** | SHA-256 verified on every download — `die()` on mismatch, never silent |
| **Protected restore** | `validateDestDir()` blocks extraction to `/`, `/bin`, `/usr`, `/etc`, `/boot` |
| **Path traversal** | `validatePath()` rejects `..` in all user-provided paths |
| **GPG encryption** | AES-256 symmetric or public key. Passphrase stored in `config.json` with `chmod 600` |
| **Timestamp validation** | Enforces `YYYYMMDDHHmmss` format with range checks |

---

## Architecture

```
vps-snapshot/
  install.sh          Interactive installer (474 lines, bash)
  src/
    index.ts          Entry point — arg parsing + dispatch
    config.ts         Config loader + input validation
    logger.ts         Standardized logging [ERROR/SUCCESS/INFO/WARN/DEBUG]
    backup.ts         Backup engine — tar, compress, encrypt, split, upload
    restore.ts        Restore engine — list, browse, extract, full
    utils.ts          rclone, flock, retry, mktemp, sha256, GPG, pigz
```

**Runtime:** [Bun](https://bun.sh/) — 3x faster than Node.js, native TypeScript, zero config.  
**Transport:** [rclone](https://rclone.org/) — battle-tested, 70+ cloud backends, auto-refresh OAuth tokens.

---

## Requirements

- Linux (x86_64 or ARM64)
- Root access
- Internet connection
- 1 GB+ free in `/tmp`

The installer handles all dependencies automatically:
- Bun, rclone, pigz, GPG (if encryption enabled), zip, curl

---

## Uninstall

```bash
sudo rm -rf /opt/vps-snapshot
sudo rm /usr/local/bin/vps-snapshot
sudo rm /etc/cron.d/vps-snapshot
```

---

## License

[MIT](LICENSE) — use it however you want.

---

<p align="center">
  Built with <a href="https://bun.sh/">Bun</a> · Powered by <a href="https://rclone.org/">rclone</a>
</p>
