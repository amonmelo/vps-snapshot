# VPS Snapshot

Backup completo de VPS para nuvem. Feito com [Bun](https://bun.sh/) + `tar` + `rclone`.

**Instalação one-click. Comando global. Restore seletivo.**

```
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

## Arquitetura

```
vps-snapshot/
  install.sh          # Instalador one-click (bash)
  package.json        # Metadados + bin entry
  config.json         # Gerado pelo instalador
  src/
    index.ts          # Entry point — parse args, dispatch
    config.ts         # Leitura + validação de config.json
    logger.ts         # Logging padronizado [INFO]/[ERROR]/etc
    backup.ts         # Motor de backup (tar → gzip → split → upload)
    restore.ts        # Motor de restore (list, browse, extract, full)
    utils.ts          # Rclone, flock, retry, mktemp, sistema
```

## Como funciona

1. **Backup**: `tar --one-file-system` da raiz `/` → gzip → split 4GB → rclone upload
2. **Exclusões padrão**: `/proc`, `/sys`, `/dev`, `/run`, caches, node_modules, Docker images (opcional)
3. **Rotação**: mantém N backups, remove os mais antigos
4. **Lock**: `flock` previne backups simultâneos
5. **Retry**: exponential backoff para upload/download
6. **Temp files**: `mktemp` para todos os paths temporários

## Provedores suportados

Via [rclone](https://rclone.org/) — ~70 serviços:

OneDrive, Google Drive, Dropbox, Amazon S3, Backblaze B2, pCloud, MEGA, SFTP, e mais.

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
  "excludePaths": ["/var/lib/docker/overlay2"]
}
```

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
# Após restore:
sudo rm /etc/machine-id && sudo systemd-machine-id-setup && sudo shutdown -r now
```

## Requisitos

- Linux (x86_64 ou ARM64)
- Root
- Conexão com internet
- ~200MB de espaço temporário para compressão

O instalador cuida de instalar Bun e rclone automaticamente.

## Desinstalar

```bash
sudo rm -rf /opt/vps-snapshot
sudo rm /usr/local/bin/vps-snapshot
sudo rm /etc/cron.d/vps-snapshot
```

## Licença

MIT
