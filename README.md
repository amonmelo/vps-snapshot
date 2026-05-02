<p align="center">
  <h1 align="center">🛡️ VPS Snapshot</h1>
  <p align="center">
    <strong>Backup completo da sua VPS para a nuvem em um comando.</strong><br>
    Igual Hostinger/AWS — snapshot full que restaura a máquina inteira.
  </p>
  <p align="center">
    <img src="https://img.shields.io/badge/Linux-all-blue?logo=linux" alt="Linux">
    <img src="https://img.shields.io/badge/Instalação-1%20comando-green" alt="1 comando">
    <img src="https://img.shields.io/badge/Nuvem-OneDrive%2C%20Drive%2C%20S3%2C%20mais-orange" alt="Provedores">
  </p>
</p>

---

## O que faz

Faz backup **completo** da sua VPS (toda a raiz `/`) e envia para a nuvem.

- ✅ Backup full da máquina inteira (tudo que está no disco)
- ✅ Restauração completa ou seletiva (só as pastas que quiser)
- ✅ Suporta **OneDrive, Google Drive, Dropbox, S3, Backblaze, SFTP** e 70+ provedores
- ✅ Funciona em **qualquer Linux** (Ubuntu, Debian, CentOS, Fedora, Arch, Alpine...)
- ✅ Agendamento automático com cron
- ✅ Compressão e split automático para arquivos grandes
- ✅ Retenção inteligente (mantém X backups, apaga os velhos)
- ✅ Modo dry-run (estima tamanho sem criar nada)
- ✅ Navegação interativa no backup (browse mode)
- ✅ Logs completos de tudo
- ✅ Retry automático em caso de falha
- ✅ Zero dependências pesadas (só tar + rclone)

---

## Instalação

```bash
curl -sSL https://raw.githubusercontent.com/SEU_USER/vps-snapshot/main/install.sh | sudo bash
```

Ou se preferir baixar primeiro:

```bash
wget https://raw.githubusercontent.com/SEU_USER/vps-snapshot/main/install.sh
sudo bash install.sh
```

O instalador é **interativo** — ele te guia passo a passo:

1. Detecta se precisa de sudo e pede automaticamente
2. Pergunta qual provedor de nuvem (OneDrive, Drive, S3...)
3. Configura o acesso (guia até o login no navegador)
4. Pergunta frequência do backup (diário, semanal, customizado)
5. Pergunta quantos backups manter
6. Opcionalmente faz um backup de teste

---

## Uso

### Estimar tamanho (sem criar backup)

```bash
sudo vps-snapshot estimate
```

### Backup manual

```bash
sudo vps-snapshot
```

### Listar backups disponíveis

```bash
sudo vps-snapshot list
```

### Ver o que tem dentro de um backup

```bash
sudo vps-snapshot list 2025-01-15_03h00m00s
```

### Navegar no backup (modo interativo)

```bash
sudo vps-snapshot browse 2025-01-15_03h00m00s
```

### Extrair pastas específicas

```bash
# Extrai só /root e /etc/ssh — pergunta onde salvar
sudo vps-snapshot extract 2025-01-15_03h00m00s /root /etc/ssh

# Restaurar tudo na raiz (para VPS nova)
sudo vps-snapshot full 2025-01-15_03h00m00s
```

### Status e logs

```bash
# Ver ultimo log
sudo vps-snapshot log

# Ver tamanho no provedor
sudo vps-snapshot status

# Reconfigurar
sudo vps-snapshot config
```

---

## O que é salvo (backup full)

| Pastas | Conteúdo |
|--------|----------|
| `/root`, `/home/*` | Usuários, scripts, SSH keys, projetos |
| `/etc/*` | Configurações do sistema, SSH, firewall |
| `/opt/*` | Aplicativos instalados manualmente |
| `/var/www/*` | Sites e aplicações web |
| `/usr/local/*` | Binários e libs customizadas |
| `/srv/*` | Dados de serviços |
| `/var/lib/docker` | Containers e imagens Docker |
| `/etc/systemd/system` | Services customizados |
| `/var/spool/cron` | Crontabs |
| Pacotes instalados | Info salva no BACKUP-META.txt |

## O que NÃO é salvo (lixo recriável)

| Motivo | Pastas |
|--------|--------|
| Filesystem virtual | `/proc`, `/sys`, `/dev`, `/run` |
| Temporário | `/tmp`, `*.tmp`, `*.pid`, `*.sock` |
| Cache de pacotes | `/var/cache/apt`, `/var/cache/yum` |
| Cache de linguagens | `node_modules`, `__pycache__`, `.npm`, `.cache` |
| Swap | `/swapfile` |
| O próprio backup | `/opt/vps-snapshot` |

---

## Provedores suportados

| Provedor | Armazenamento grátis |
|----------|---------------------|
| **Microsoft OneDrive** | 5 GB |
| **Google Drive** | 15 GB |
| **Dropbox** | 2 GB |
| **Amazon S3** | 5 GB (12 meses free tier) |
| **Backblaze B2** | 10 GB |
| **pCloud** | 10 GB |
| **Mega** | 20 GB |
| **SFTP** | Ilimitado (seu servidor) |
| **MinIO** | Local/S3 compatível |
| ... e mais 60+ | [Lista completa do rclone](https://rclone.org/#providers) |

---

## Restauração

### Em uma VPS nova (restauração full):

```bash
# 1. Instala o VPS Snapshot
curl -sSL https://raw.githubusercontent.com/SEU_USER/vps-snapshot/main/install.sh | sudo bash

# 2. Configura o mesmo provedor de nuvem
# (o instalador guia de novo)

# 3. Restaura tudo
sudo vps-snapshot full 2025-01-15_03h00m00s

# 4. Reboot
sudo reboot
```

> **Importante:** A VPS nova deve ter a mesma distro e versão do backup.

### Restauração parcial (só algumas pastas):

```bash
# Extrai em pasta temporária (não sobrescreve nada)
sudo vps-snapshot extract 2025-01-15_03h00m00s /root /etc/ssh
# → Escolhe opção 2 (pasta temporária)
# → Copia manualmente o que precisa
```

---

## Configuração

Após instalar, edite o config:

```bash
sudo nano /opt/vps-snapshot/config.sh
```

Opções disponíveis:

```bash
# Nome da VPS (identifica no provedor)
VPS_NAME="meu-servidor-web"

# Provedor: onedrive, gdrive, s3, dropbox, etc
REMOTE_NAME="onedrive"
REMOTE_PATH="Backup-VPS"

# Retenção: quantos backups manter
KEEP_BACKUPS=5

# Compressão: 1 (rápido) a 9 (máximo)
COMPRESSION_LEVEL=6

# Split: dividir arquivos grandes (para provedores com limite)
SPLIT_SIZE="4G"

# Excluir imagens Docker (economiza espaço, são reinstaláveis)
EXCLUDE_DOCKER_IMAGES=false

# Comandos antes/depois do backup (ex: parar serviços pesados)
PRE_BACKUP_COMMANDS=("systemctl stop meu-app")
POST_BACKUP_COMMANDS=("systemctl start meu-app")
```

---

## Arquitetura

```
VPS Linux ──────rclone (HTTPS)──────> Provedor de Nuvem
    │                                       │
    │  /opt/vps-snapshot/                    │
    │  ├── install.sh   (instalador)         │  Backup-VPS/
    │  ├── backup.sh    (motor de backup)    │  ├── meu-server/
    │  ├── restore.sh   (restauração)        │  │   ├── vps-backup-...tar.gz
    │  ├── config.sh    (configuração)       │  │   ├── vps-backup-...tar.gz.part-aa
    │  ├── backup.log   (log de backups)     │  │   └── BACKUP-META.txt
    │  └── cron.log     (log do agendador)   │  └── outro-server/
    │                                       │
    │  /usr/local/bin/vps-snapshot ──> symlink para backup.sh
    │                                       │
    │  Fluxo:                                │
    │  1. tar.gz full da raiz /              │
    │  2. Split em blocos (se > 4G)          │
    │  3. Upload via rclone                  │
    │  4. Limpa local                        │
    │  5. Limpa velhos (retenção)            │
    └───────────────────────────────────────┘
```

---

## E se falhar?

- **Falha de upload:** O script tenta 3 vezes. Se não conseguir, o arquivo fica em `/tmp/` para retry manual.
- **Falha de disco cheio:** O log avisa. Verifique com `df -h`.
- **Falha de autenticação:** O rclone avisa. Rode `sudo vps-snapshot config` para reconfigurar.
- **Falha no cron:** Verifique com `sudo vps-snapshot log` e `sudo journalctl -u cron`.
- **Provedor cheio:** O script avisa no log. Delete backups velhos ou aumente o plano.

---

## Desinstalação

```bash
sudo rm -rf /opt/vps-snapshot
sudo rm /usr/local/bin/vps-snapshot
sudo rm /etc/cron.d/vps-snapshot
```

---

## Licença

MIT — use como quiser.
