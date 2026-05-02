# VPS Snapshot

Backup completo de VPS para nuvem. Feito com [Bun](https://bun.sh/) + `tar` + `rclone`.

**Instalação one-click. Comando global. Restore seletivo. Criptografia GPG.**

```bash
curl -sSL https://raw.githubusercontent.com/amonmelo/vps-snapshot/main/install.sh | sudo bash
```

## Comandos

| Comando | Descrição |
|---------|-----------|
| `vps-snapshot estimate` | Estimar tamanho do backup |
| `vps-snapshot` ou `vps-snapshot run` | Executar backup completo |
| `vps-snapshot list` | Listar backups na nuvem |
| `vps-snapshot browse [timestamp]` | Navegar conteúdo do backup |
| `vps-snapshot extract <ts> <paths> [--dest /dir]` | Extrair arquivos específicos |
| `vps-snapshot full [timestamp]` | Restauração completa |
| `vps-snapshot log [N]` | Ver log (últimas N linhas) |
| `vps-snapshot status` | Status do provedor |
| `vps-snapshot config` | Mostrar configuração |

**Flags globais:** `-v` (debug), `-c /path/config.json` (config alternativo), `-h` (ajuda)

## Como funciona

```
tar (raiz /) → gzip/pigz → [GPG encrypt] → split 4GB → SHA256 manifest → rclone upload → verify
```

1. **Backup**: `tar --one-file-system` da raiz `/` → compressão (pigz paralelo se disponível, senão gzip) → split em partes de 4GB → upload via rclone
2. **Criptografia** (opcional): GPG symmetric (AES256 + passphrase) ou public key. Habilitado no instalador.
3. **Integridade**: SHA256 de cada parte + manifesto. Verificação obrigatória no download — aborta se falhar.
4. **Exclusões padrão**: `/proc`, `/sys`, `/dev`, `/run`, caches, node_modules, Docker images (opcional)
5. **Rotação**: mantém N backups, remove os mais antigos automaticamente
6. **Lock**: `flock` com path imprevisível (`mktemp`) previne backups simultâneos
7. **Retry**: exponential backoff (3 tentativas) para upload/download
8. **Espaço em disco**: verifica 1GB+ livre em `/tmp` antes de iniciar
9. **Temp files**: `mktemp` para todos os paths temporários (sem paths previsíveis)

## Arquitetura

```
vps-snapshot/
  install.sh          # Instalador interativo one-click (bash)
  package.json        # Metadados Bun + bin entry
  README.md
  LICENSE             # MIT
  .gitignore
  src/
    index.ts          # Entry point — parse args, dispatch 9 subcomandos
    config.ts         # Leitura + validação de config.json + input do usuário
    logger.ts         # Logging padronizado [ERROR]/[SUCCESS]/[INFO]/[WARN]/[DEBUG]
    backup.ts         # Motor de backup — decomposto em sub-funções
    restore.ts        # Motor de restore (list, browse, extract, full)
    utils.ts          # rclone wrappers, flock, retry, mktemp, sha256, GPG, pigz
```

**~2050 linhas** (1576 TypeScript + 474 install.sh)

## Provedores suportados

Via [rclone](https://rclone.org/) — ~70 serviços:

| Provedor | Espaço grátis |
|----------|--------------|
| OneDrive | 5 GB |
| Google Drive | 15 GB |
| MEGA | 20 GB |
| Backblaze B2 | 10 GB |
| pCloud | 10 GB |
| Dropbox | 2 GB |
| Amazon S3 | 5 GB (free tier) |
| SFTP | depende |

## Configuração

Após instalação, edite `/opt/vps-snapshot/config.json`:

```json
{
  "vpsName": "meu-servidor",
  "remoteName": "onedrive",
  "remotePath": "Backup-VPS",
  "keepBackups": 5,
  "compressionLevel": 6,
  "splitSize": "4G",
  "excludeDockerImages": true,
  "excludePatterns": ["*.log", "*.tmp"],
  "excludePaths": ["/var/lib/docker/overlay2"],
  "includeSystemInfo": false,
  "encryption": {
    "enabled": false,
    "passphrase": "",
    "recipient": ""
  }
}
```

**Campos:**

| Campo | Tipo | Default | Descrição |
|-------|------|---------|-----------|
| `vpsName` | string | hostname | Nome da VPS (usado na organização da nuvem) |
| `remoteName` | string | `onedrive` | Nome do remote rclone |
| `remotePath` | string | `Backup-VPS` | Pasta raiz no provedor |
| `keepBackups` | number | `5` | Máximo de backups a manter |
| `compressionLevel` | number | `6` | 1 (rápido) a 9 (máximo) |
| `splitSize` | string | `4G` | Tamanho max por parte (para OneDrive) |
| `excludeDockerImages` | bool | `false` | Excluir `/var/lib/docker/*` |
| `excludePatterns` | string[] | `["*.log", ...]` | Glob patterns para excluir |
| `excludePaths` | string[] | `["/proc", ...]` | Paths absolutos para excluir |
| `preBackupCommands` | string[] | `[]` | Comandos antes do backup |
| `postBackupCommands` | string[] | `[]` | Comandos após o backup |
| `includeSystemInfo` | bool | `false` | Incluir hostname/distro/kernel no metadata |
| `encryption.enabled` | bool | `false` | Habilitar GPG |
| `encryption.passphrase` | string | `""` | Senha (symmetric AES256) |
| `encryption.recipient` | string | `""` | Email GPG (public key) |

## Restore

```bash
# Listar backups
sudo vps-snapshot list

# Navegar conteúdo
sudo vps-snapshot browse 20250601030000

# Extrair apenas /etc/nginx e /home/user
sudo vps-snapshot extract 20250601030000 /etc/nginx /home/user --dest /tmp/restored

# Restauração completa (VPS nova!)
sudo vps-snapshot full 20250601030000
```

Após restore completo:
```bash
sudo rm /etc/machine-id && sudo systemd-machine-id-setup && sudo shutdown -r now
```

## Requisitos

- Linux (x86_64 ou ARM64)
- Root
- Conexão com internet
- 1GB+ livre em `/tmp`

O instalador cuida de instalar automaticamente:
- [Bun](https://bun.sh/) (runtime TypeScript)
- [rclone](https://rclone.org/) (transporte para nuvem)
- [pigz](https://zlib.net/pigz/) (gzip paralelo, opcional)
- [GPG](https://gnupg.org/) (se criptografia habilitada)

## Instalador

O instalador é interativo e pergunta:

1. **Nome da VPS** — identificador único
2. **Provedor de nuvem** — OneDrive, Google Drive, S3, etc.
3. **Agendamento** — diário, semanal, quinzenal, mensal ou manual
4. **Opções** — compressão, split, Docker, criptografia GPG, PII
5. **Instalação** — baixa dependências, configura rclone, cria cron

## Segurança

- **Sem eval** — todos os comandos usam `Bun.spawn()` com arrays
- **Lock imprevisível** — `mktemp` para lock file (previne symlink attacks)
- **Input sanitizado** — installer escapa JSON antes de escrever config.json
- **PII controlado** — hostname/distro/kernel NÃO vão no metadata por padrão
- **Integridade obrigatória** — SHA256 verificado no download, `die()` em falha
- **Destino protegido** — `validateDestDir()` bloqueia extração para `/`, `/bin`, `/etc`
- **Timestamp validado** — formato YYYYMMDDHHmmss com range check
- **Path traversal** — `validatePath()` bloqueia `..` em paths
- **GPG** — AES256 symmetric ou public key, passphrase protegida em config (chmod 600)

## Desinstalar

```bash
sudo rm -rf /opt/vps-snapshot
sudo rm /usr/local/bin/vps-snapshot
sudo rm /etc/cron.d/vps-snapshot
sudo rm -rf ~/.bun  # (opcional, remove o Bun)
```

## Licença

MIT
