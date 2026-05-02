#!/usr/bin/env bash
#
# VPS Snapshot — Instalador One-Click
# https://github.com/amonmelo/vps-snapshot
#
# curl -sSL https://raw.githubusercontent.com/amonmelo/vps-snapshot/main/install.sh | sudo bash
#
set -eo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
info()  { echo -e "${CYAN}  [i]${NC} $*"; }
ok()    { echo -e "${GREEN}  [✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}  [!]${NC} $*"; }
die()   { echo -e "${RED}  [✗]${NC} $*" >&2; exit 1; }

# ── Root ──
if (( EUID != 0 )); then
    if command -v sudo &>/dev/null; then exec sudo bash "$0" "$@"; fi
    die "Rode como root: sudo bash install.sh"
fi

INSTALL_TMP="$(mktemp -d /tmp/vps-snapshot-install-XXXXXX)"
trap 'rm -rf "$INSTALL_TMP" /tmp/vps-snapshot-install-rclone-* 2>/dev/null' EXIT

# ── Helpers seguros (sem eval) ──
ask_str() {
    local label="$1" default="${2:-}"
    local prompt
    [[ -n "$default" ]] && prompt="$label [$default]: " || prompt="$label: "
    echo -ne "${CYAN}  ? ${NC}${prompt}"
    IFS= read -r reply || reply=""
    reply="${reply:-$default}"
    echo "$reply"
}

ask_yn() {
    local label="$1" default="${2:-y}"
    local prompt
    [[ "$default" =~ ^[Yy] ]] && prompt="$label [S/n]: " || prompt="$label [s/N]: "
    echo -ne "${CYAN}  ? ${NC}${prompt}"
    IFS= read -r reply || reply=""
    reply="${reply:-$default}"
    [[ "$reply" =~ ^[SsYy]$ ]]
}

ask_choice() {
    local label="$1" default="${2:-1}"; shift 2
    echo -e "${CYAN}  ? ${NC}$label"
    local i=1
    for opt in "$@"; do echo -e "    ${DIM}($i)${NC} $opt"; i=$((i+1)); done
    echo -ne "    ${BOLD}Escolha [$default]: ${NC}"
    IFS= read -r reply || reply=""
    reply="${reply:-$default}"
    echo "$reply"
}

# ── Distro ──
detect_pkg() {
    local id=""
    [[ -f /etc/os-release ]] && id=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"' | head -1)
    case "$id" in
        ubuntu|debian|linuxmint|pop)    echo "apt-get install -y -qq" ;;
        centos|rhel|rocky|almalinux|ol) echo "dnf install -y -q" ;;
        fedora)                         echo "dnf install -y -q" ;;
        amzn)                           echo "yum install -y -q" ;;
        arch|manjaro|endeavouros)       echo "pacman -S --noconfirm" ;;
        alpine)                         echo "apk add --quiet" ;;
        opensuse*|sles)                 echo "zypper install -y -q" ;;
        *) echo "" ;;
    esac
}

install_pkg() {
    local pkg="$1"
    command -v "$pkg" &>/dev/null && return 0
    info "Instalando $pkg..."
    local cmd
    cmd=$(detect_pkg)
    if [[ -n "$cmd" ]]; then
        $cmd "$pkg" 2>/dev/null || \
        apt-get install -y -qq "$pkg" 2>/dev/null || \
        dnf install -y -q "$pkg" 2>/dev/null || \
        pacman -S --noconfirm "$pkg" 2>/dev/null || \
        apk add --quiet "$pkg" 2>/dev/null || \
        die "Nao consegui instalar $pkg"
    else
        apt-get install -y -qq "$pkg" 2>/dev/null || \
        dnf install -y -q "$pkg" 2>/dev/null || \
        pacman -S --noconfirm "$pkg" 2>/dev/null || \
        apk add --quiet "$pkg" 2>/dev/null || \
        die "Nao consegui instalar $pkg"
    fi
}

# ── Instalar Bun ──
install_bun() {
    command -v bun &>/dev/null && { ok "Bun ja instalado ($(bun --version))"; return; }
    info "Instalando Bun..."
    curl -fsSL https://bun.sh/install | bash 2>&1 | tail -3
    # Source bun profile
    export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
    export PATH="$BUN_INSTALL/bin:$PATH"
    command -v bun &>/dev/null || die "Bun nao foi instalado. Instale manualmente: curl -fsSL https://bun.sh/install | bash"
    ok "Bun $(bun --version) instalado"
}

# ── Instalar rclone ──
install_rclone() {
    command -v rclone &>/dev/null && { ok "rclone ja instalado"; return; }
    info "Instalando rclone..."
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        armv7l|armhf) arch="arm-v7" ;;
        *) die "Arquitetura $arch nao suportada" ;;
    esac
    local url="https://downloads.rclone.org/rclone-current-linux-$arch.zip"
    local tmp="/tmp/vps-snapshot-install-rclone"
    mkdir -p "$tmp"
    curl -fsSL "$url" -o "$tmp/rclone.zip" || die "Falha ao baixar rclone"
    # Verificar checksum se disponivel
    if curl -fsSL "${url}.sha256" -o "$tmp/rclone.zip.sha256" 2>/dev/null; then
        (cd "$tmp" && sha256sum -c rclone.zip.sha256) 2>/dev/null || warn "Checksum do rclone nao bateu (pode ser atualizacao recente)"
    fi
    unzip -oq "$tmp/rclone.zip" -d "$tmp/" || die "Falha ao extrair rclone"
    mv "$tmp"/rclone-*/rclone /usr/local/bin/rclone || die "Falha ao mover rclone"
    chmod +x /usr/local/bin/rclone
    rm -rf "$tmp"
    ok "rclone instalado"
}

# ═══════════════════════════════════
# BANNER
# ═══════════════════════════════════
clear
cat << 'BANNER'

 ╔═══════════════════════════════════════════════════╗
 ║                                                   ║
 ║           🛡️  VPS SNAPSHOT                        ║
 ║           Backup completo da sua VPS              ║
 ║           Feito com Bun — rapido e seguro         ║
 ║                                                   ║
 ╚═══════════════════════════════════════════════════╝

BANNER

echo -e "  Sistema: ${BOLD}$(hostname)${NC}"
echo -e "  Kernel:  ${BOLD}$(uname -r)${NC} ($(uname -m))"
echo -e "  Disco:   ${BOLD}$(df -h / | tail -1 | awk '{print $4 " livres"}')${NC}"
echo ""

# ═══════════════════════════════════
# PASSO 1: NOME
# ═══════════════════════════════════
echo -e "${BOLD}${CYAN}── PASSO 1/5 — Nome da VPS ──${NC}\n"
echo "  Cada VPS precisa de um nome unico."
echo "  Exemplos: ${DIM}servidor-web, api-prod, blog-vps${NC}\n"
VPS_NAME=$(ask_str "Nome desta VPS" "$(hostname)")
VPS_NAME=$(echo "$VPS_NAME" | tr -cd 'a-zA-Z0-9_-')
[[ -z "$VPS_NAME" ]] && VPS_NAME="vps-default"
[[ ${#VPS_NAME} -gt 64 ]] && VPS_NAME="${VPS_NAME:0:64}"
ok "Nome: $VPS_NAME"

# ═══════════════════════════════════
# PASSO 2: PROVEDOR
# ═══════════════════════════════════
echo -e "\n${BOLD}${CYAN}── PASSO 2/5 — Provedor de nuvem ──${NC}\n"
echo "  Onde guardar os backups?\n"
PROVIDER=$(ask_choice "Provedor" "1" \
    "Microsoft OneDrive (5 GB gratis)" \
    "Google Drive (15 GB gratis)" \
    "Dropbox (2 GB gratis)" \
    "Amazon S3 / S3-compatible" \
    "Backblaze B2 (10 GB gratis)" \
    "pCloud (10 GB gratis)" \
    "MEGA (20 GB gratis)" \
    "SFTP (seu servidor)")

case "$PROVIDER" in
    1) REMOTE_NAME="onedrive";   FREE_SPACE="5 GB" ;;
    2) REMOTE_NAME="gdrive";     FREE_SPACE="15 GB" ;;
    3) REMOTE_NAME="dropbox";    FREE_SPACE="2 GB" ;;
    4) REMOTE_NAME="s3";         FREE_SPACE="5 GB (free tier)" ;;
    5) REMOTE_NAME="backblaze";  FREE_SPACE="10 GB" ;;
    6) REMOTE_NAME="pcloud";     FREE_SPACE="10 GB" ;;
    7) REMOTE_NAME="mega";       FREE_SPACE="20 GB" ;;
    8) REMOTE_NAME="sftp";       FREE_SPACE="depende" ;;
    *) REMOTE_NAME="remote";     FREE_SPACE="depende" ;;
esac
ok "Provedor: $REMOTE_NAME (~$FREE_SPACE)"

# ═══════════════════════════════════
# PASSO 3: AGENDAMENTO
# ═══════════════════════════════════
echo -e "\n${BOLD}${CYAN}── PASSO 3/5 — Agendamento ──${NC}\n"
SCHEDULE=$(ask_choice "Frequencia" "1" \
    "Diario as 3h (recomendado)" \
    "Diario as 0h" \
    "A cada 12 horas" \
    "A cada 6 horas" \
    "Semanal (domingo 3h)" \
    "Quinzenal (dias 1 e 15)" \
    "Mensal (dia 1)" \
    "Nao agendar (so manual)")

case "$SCHEDULE" in
    1) CRON_EXPR="0 3 * * *";      CRON_DESC="Diario 3h" ;;
    2) CRON_EXPR="0 0 * * *";      CRON_DESC="Diario 0h" ;;
    3) CRON_EXPR="0 */12 * * *";   CRON_DESC="12h" ;;
    4) CRON_EXPR="0 */6 * * *";    CRON_DESC="6h" ;;
    5) CRON_EXPR="0 3 * * 0";      CRON_DESC="Semanal dom" ;;
    6) CRON_EXPR="0 3 1,15 * *";   CRON_DESC="Quinzenal" ;;
    7) CRON_EXPR="0 3 1 * *";      CRON_DESC="Mensal" ;;
    8) CRON_EXPR="";                CRON_DESC="Manual" ;;
    *) CRON_EXPR="";                CRON_DESC="Manual" ;;
esac
ok "Agendamento: $CRON_DESC"

KEEP_BACKUPS=$(ask_str "Quantos backups manter" "5")
[[ "$KEEP_BACKUPS" =~ ^[0-9]+$ ]] || KEEP_BACKUPS=5
(( KEEP_BACKUPS < 1 )) && KEEP_BACKUPS=1
(( KEEP_BACKUPS > 365 )) && KEEP_BACKUPS=365
ok "Retencao: $KEEP_BACKUPS"

# ═══════════════════════════════════
# PASSO 4: OPCOES
# ═══════════════════════════════════
echo -e "\n${BOLD}${CYAN}── PASSO 4/5 — Opcoes (Enter = default) ──${NC}\n"

COMPRESSION=$(ask_str "Compressao (1=rapido 9=maximo)" "6")
[[ "$COMPRESSION" =~ ^[1-9]$ ]] || COMPRESSION=6

SPLIT_SIZE=$(ask_str "Tamanho max por arquivo (ex: 4G, 2G)" "4G")
[[ "$SPLIT_SIZE" =~ ^[0-9]+[MGmgKk]?$ ]] || SPLIT_SIZE="4G"

REMOTE_PATH=$(ask_str "Pasta destino no provedor" "Backup-VPS")
[[ -z "$REMOTE_PATH" ]] && REMOTE_PATH="Backup-VPS"

EXCLUDE_DOCKER="false"
if ask_yn "Excluir imagens Docker? (economiza espaco, sao reinstalaveis)" "y"; then
    EXCLUDE_DOCKER="true"
fi

# ═══════════════════════════════════
# PASSO 5: INSTALACAO
# ═══════════════════════════════════
echo -e "\n${BOLD}${CYAN}── PASSO 5/5 — Instalando ──${NC}\n"

install_pkg zip
install_pkg curl
install_pkg unzip
install_bun
install_rclone

INSTALL_DIR="/opt/vps-snapshot"
mkdir -p "$INSTALL_DIR/src"

# ── Baixar scripts do repo ──
REPO_RAW="https://raw.githubusercontent.com/amonmelo/vps-snapshot/main"
info "Baixando VPS Snapshot..."

# Baixar todos os modulos TS + package.json
SRC_FILES=("package.json" "src/index.ts" "src/config.ts" "src/logger.ts" "src/backup.ts" "src/restore.ts" "src/utils.ts")
download_ok=true

for f in "${SRC_FILES[@]}"; do
    mkdir -p "$INSTALL_DIR/$(dirname "$f")"
    if curl -fsSL "$REPO_RAW/$f" -o "$INSTALL_DIR/$f" 2>/dev/null; then
        : # ok
    else
        warn "Falha ao baixar $f"
        download_ok=false
    fi
done

if ! $download_ok || [[ ! -f "$INSTALL_DIR/src/index.ts" ]] || [[ ! -s "$INSTALL_DIR/src/index.ts" ]]; then
    warn "Nao conseguiu baixar tudo do GitHub. Tentando git clone..."
    if command -v git &>/dev/null; then
        git clone --depth 1 https://github.com/amonmelo/vps-snapshot.git /tmp/vps-snapshot-src 2>/dev/null && \
            cp -r /tmp/vps-snapshot-src/src/*.ts "$INSTALL_DIR/src/" && \
            rm -rf /tmp/vps-snapshot-src && \
            download_ok=true
    fi
    if ! $download_ok; then
        die "Nao conseguiu baixar os scripts. Baixe manualmente:\n  git clone https://github.com/amonmelo/vps-snapshot.git\n  cp src/*.ts $INSTALL_DIR/src/"
    fi
fi

# ── Gerar config ──
info "Gerando configuracao..."
cat > "$INSTALL_DIR/config.json" << CFGEOF
{
  "vpsName": "$VPS_NAME",
  "remoteName": "$REMOTE_NAME",
  "remotePath": "$REMOTE_PATH",
  "keepBackups": $KEEP_BACKUPS,
  "compressionLevel": $COMPRESSION,
  "splitSize": "$SPLIT_SIZE",
  "excludeDockerImages": $EXCLUDE_DOCKER,
  "excludePatterns": [
    "*.log", "*.tmp", "*.pid", "*.sock", "*.swap", "nohup.out",
    "*/node_modules", "*/__pycache__", "*/.cache", "*/.npm",
    "*/.pip", "*/.cargo/registry", "*/go/pkg/mod/cache"
  ],
  "excludePaths": [
    "/proc", "/sys", "/dev", "/run", "/tmp",
    "/snap", "/boot/efi",
    "/var/cache/apt/archives", "/var/cache/yum", "/var/cache/dnf",
    "/var/lib/apt/lists",
    "$INSTALL_DIR", "/tmp/vps-snapshot-*"
  ],
  "preBackupCommands": [],
  "postBackupCommands": []
}
CFGEOF
chmod 600 "$INSTALL_DIR/config.json"
ok "Config: $INSTALL_DIR/config.json"

# ── Symlink global ──
BUN_BIN="${BUN_INSTALL:-$HOME/.bun}/bin/bun"
cat > /usr/local/bin/vps-snapshot << SYMLINK
#!/bin/bash
export PATH="${BUN_INSTALL:-$HOME/.bun}/bin:\$PATH"
exec bun "$INSTALL_DIR/src/index.ts" "\$@"
SYMLINK
chmod +x /usr/local/bin/vps-snapshot
ok "Comando 'vps-snapshot' disponivel"

# ── Configurar rclone ──
echo ""
if rclone listremotes 2>/dev/null | grep -q "^${REMOTE_NAME}:"; then
    ok "$REMOTE_NAME ja configurado"
else
    echo -e "  ${DIM}Voce precisa autorizar o acesso ao provedor.${NC}"
    echo -e "  ${DIM}Se a VPS nao tem navegador, use token manual.${NC}\n"
    if ask_yn "Configurar $REMOTE_NAME agora?" "y"; then
        info "Nome do remote: $REMOTE_NAME"
        rclone config
    else
        warn "Configure depois: sudo rclone config"
    fi
fi

# ── Testar conexao ──
echo ""
info "Testando conexao..."
if rclone lsd "${REMOTE_NAME}:" &>/dev/null 2>&1; then
    ok "$REMOTE_NAME: conectado!"
else
    warn "Nao conectou. Configure: sudo rclone config"
fi

# ── Cron ──
if [[ -n "$CRON_EXPR" ]]; then
    printf '# VPS Snapshot — %s\nSHELL=/bin/bash\nPATH=%s/bin:%s\n%s root /usr/local/bin/vps-snapshot >> %s/cron.log 2>&1\n' \
        "$VPS_NAME" \
        "${BUN_INSTALL:-$HOME/.bun}" \
        "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        "$CRON_EXPR" \
        "$INSTALL_DIR" > /etc/cron.d/vps-snapshot
    chmod 644 /etc/cron.d/vps-snapshot
    ok "Cron: $CRON_DESC"
else
    ok "Sem cron — backup manual"
fi

# ── Teste opcional ──
echo ""
if ask_yn "Rodar backup de teste agora?" "n"; then
    info "Executando backup de teste..."
    if /usr/local/bin/vps-snapshot estimate; then
        ok "Estimativa OK! Para backup completo: sudo vps-snapshot"
    fi
else
    echo -e "  ${DIM}Comandos:${NC}"
    echo -e "  ${CYAN}sudo vps-snapshot estimate${NC}  Estimar tamanho"
    echo -e "  ${CYAN}sudo vps-snapshot${NC}           Backup manual"
fi

# ── Resumo ──
clear
cat << FINAL

 ╔═══════════════════════════════════════════════════╗
 ║                                                   ║
 ║        ✅  VPS SNAPSHOT INSTALADO!                 ║
 ║                                                   ║
 ╚═══════════════════════════════════════════════════╝

  VPS:         $VPS_NAME
  Provedor:    $REMOTE_NAME
  Agendamento: $CRON_DESC
  Retencao:    $KEEP_BACKUPS backups
  Runtime:     Bun $(bun --version)

  ┌──────────────────────────────────────────┐
  │  Comandos:                               │
  │                                          │
  │  vps-snapshot estimate    Estimar tamanho│
  │  vps-snapshot             Backup manual  │
  │  vps-snapshot list        Listar backups │
  │  vps-snapshot browse TS   Navegar        │
  │  vps-snapshot extract TS  Extrair partes │
  │  vps-snapshot full TS     Restaurar tudo │
  │  vps-snapshot log         Ver log        │
  │  vps-snapshot status      Status provedor│
  │  vps-snapshot config      Editar config  │
  └──────────────────────────────────────────┘

  Config:  sudo nano $INSTALL_DIR/config.json
  Log:     sudo tail -f $INSTALL_DIR/backup.log

FINAL
