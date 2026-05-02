#!/usr/bin/env bash
#
# VPS Snapshot - Instalador Interativo
# https://github.com/SEU_USER/vps-snapshot
#
# Uso: curl -sSL https://raw.githubusercontent.com/SEU_USER/vps-snapshot/main/install.sh | sudo bash
#
set -euo pipefail

# ═══════════════════════════════════════
# CORES E HELPERS
# ═══════════════════════════════════════
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

info()  { echo -e "${CYAN}  [i]${NC} $*"; }
ok()    { echo -e "${GREEN}  [✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}  [!]${NC} $*"; }
die()   { echo -e "${RED}  [✗]${NC} $*" >&2; exit 1; }
step()  { echo -e "\n${BOLD}${CYAN}── $1 ──${NC}"; }
ask()   {
    local label="$1" var="$2" default="${3:-}"
    local prompt
    if [[ -n "$default" ]]; then
        prompt="$label [$default]: "
    else
        prompt="$label: "
    fi
    echo -ne "${CYAN}  ? ${NC}${prompt}"
    read -r reply
    reply="${reply:-$default}"
    reply="${reply:-$default}"
    eval "$var=\"\$reply\""
}
ask_yn() {
    local label="$1" default="${2:-y}"
    local y n prompt
    if [[ "$default" =~ ^[Yy]$ ]]; then
        prompt="$label [S/n]: "; y="S"; n="n"
    else
        prompt="$label [s/N]: "; y="s"; n="N"
    fi
    echo -ne "${CYAN}  ? ${NC}${prompt}"
    read -r reply
    reply="${reply:-$default}"
    [[ "$reply" =~ ^[SsYy]$ ]]
}
ask_choice() {
    local label="$1" default="${2:-1}"; shift 2
    echo -e "${CYAN}  ? ${NC}$label"
    local i=1
    for opt in "$@"; do
        echo -e "    ${DIM}($i)${NC} $opt"
        i=$((i+1))
    done
    echo -ne "    ${BOLD}Escolha [$default]: ${NC}"
    read -r reply
    reply="${reply:-$default}"
    echo "$reply"
}

# ═══════════════════════════════════════
# SUDO CHECK
# ═══════════════════════════════════════
ensure_root() {
    if (( EUID != 0 )); then
        warn "Precisa de root (sudo). Tentando elevar..."
        if command -v sudo &>/dev/null; then
            exec sudo bash "$0" "$@"
        else
            die "Rode como root: sudo bash install.sh"
        fi
    fi
}
ensure_root "$@"

# ═══════════════════════════════════════
# DISTRO DETECT
# ═══════════════════════════════════════
detect_distro() {
    DISTRO_ID=""
    DISTRO_VERSION=""
    if [[ -f /etc/os-release ]]; then
        DISTRO_ID=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"' | head -1)
        DISTRO_VERSION=$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"' | head -1)
    fi

    case "$DISTRO_ID" in
        ubuntu|debian|linuxmint|pop)       PKG_CMD="apt-get install -y -qq" ;;
        centos|rhel|rocky|almalinux|ol)    PKG_CMD="dnf install -y -q" ;;
        fedora)                            PKG_CMD="dnf install -y -q" ;;
        amzn)                              PKG_CMD="yum install -y -q" ;;
        arch|manjaro|endeavouros)          PKG_CMD="pacman -S --noconfirm" ;;
        alpine)                            PKG_CMD="apk add --quiet" ;;
        opensuse*|sles)                    PKG_CMD="zypper install -y -q" ;;
        *)                                 PKG_CMD="" ;;
    esac
}

install_pkg() {
    local pkg="$1"
    command -v "$pkg" &>/dev/null && return 0
    info "Instalando $pkg..."
    if [[ -n "$PKG_CMD" ]]; then
        eval "$PKG_CMD $pkg" 2>/dev/null
    else
        # Fallback: tentar varios
        apt-get install -y -qq "$pkg" 2>/dev/null || \
        dnf install -y -q "$pkg" 2>/dev/null || \
        yum install -y -q "$pkg" 2>/dev/null || \
        pacman -S --noconfirm "$pkg" 2>/dev/null || \
        apk add --quiet "$pkg" 2>/dev/null || \
        die "Nao consegui instalar $pkg. Instale manualmente."
    fi
}

# ═══════════════════════════════════════
# INSTALL RCLONE
# ═══════════════════════════════════════
install_rclone() {
    command -v rclone &>/dev/null && { ok "rclone ja instalado"; return; }
    info "Instalando rclone..."
    local arch; arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        armv7l|armhf) arch="arm-v7" ;;
        *) die "Arquitetura $arch nao suportada" ;;
    esac
    local url="https://downloads.rclone.org/rclone-current-linux-$arch.zip"
    curl -fsSL "$url" -o /tmp/rclone.zip || die "Falha ao baixar rclone de $url"
    unzip -oq /tmp/rclone.zip -d /tmp/ || die "Falha ao extrair rclone"
    mv /tmp/rclone-*/rclone /usr/local/bin/rclone 2>/dev/null || die "Falha ao mover rclone"
    chmod +x /usr/local/bin/rclone
    rm -rf /tmp/rclone.zip /tmp/rclone-*
    ok "rclone instalado"
}

# ═══════════════════════════════════════
# BANNER
# ═══════════════════════════════════════
clear
cat << 'BANNER'

 ╔═══════════════════════════════════════════════════╗
 ║                                                   ║
 ║           🛡️  VPS SNAPSHOT                        ║
 ║           Backup completo da sua VPS              ║
 ║           Um comando pra instalar                 ║
 ║           Um comando pra backupar                 ║
 ║           Um comando pra restaurar                ║
 ║                                                   ║
 ╚═══════════════════════════════════════════════════╝

BANNER

detect_distro

echo -e "  Sistema:  ${BOLD}$(hostname)${NC}"
[[ -n "$DISTRO_ID" ]] && echo -e "  Distro:   ${BOLD}${DISTRO_ID} ${DISTRO_VERSION}${NC}"
echo -e "  Kernel:   ${BOLD}$(uname -r)${NC} ($(uname -m))"
echo -e "  Disco:    ${BOLD}$(df -h / | tail -1 | awk '{print $4 " livres"}')${NC}"
echo ""

# ═══════════════════════════════════════
# PASSO 1: NOME DA VPS
# ═══════════════════════════════════════
step "PASSO 1/5 — Identificar a VPS"
echo ""
echo -e "  Cada VPS precisa de um nome unico."
echo -e "  Isso cria uma pasta separada no provedor de nuvem."
echo -e "  Exemplos: ${DIM}servidor-web, api-prod, meu-ubuntu, blog-vps${NC}"
echo ""
ask "Nome desta VPS" VPS_NAME "$(hostname)"
# Limpar caracteres problematicos
VPS_NAME=$(echo "$VPS_NAME" | tr -cd 'a-zA-Z0-9_-')
ok "Nome: $VPS_NAME"

# ═══════════════════════════════════════
# PASSO 2: PROVEDOR DE NUVEM
# ═══════════════════════════════════════
step "PASSO 2/5 — Escolher provedor de nuvem"
echo ""
echo -e "  Onde voce quer guardar os backups?"
echo ""
PROVIDER=$(ask_choice "Provedor" "1" \
    "Microsoft OneDrive (5 GB gratis)" \
    "Google Drive (15 GB gratis)" \
    "Dropbox (2 GB gratis)" \
    "Amazon S3 / S3-compatible" \
    "Backblaze B2 (10 GB gratis)" \
    "pCloud (10 GB gratis)" \
    "MEGA (20 GB gratis)" \
    "SFTP (seu proprio servidor)" \
    "Outro (rclone suporta 70+ provedores)")

case "$PROVIDER" in
    1) REMOTE_TYPE="onedrive";   REMOTE_NAME="onedrive";    FREE_SPACE="5 GB" ;;
    2) REMOTE_TYPE="drive";      REMOTE_NAME="gdrive";      FREE_SPACE="15 GB" ;;
    3) REMOTE_TYPE="dropbox";    REMOTE_NAME="dropbox";     FREE_SPACE="2 GB" ;;
    4) REMOTE_TYPE="s3";         REMOTE_NAME="s3";          FREE_SPACE="5 GB (free tier)" ;;
    5) REMOTE_TYPE="b2";         REMOTE_NAME="backblaze";   FREE_SPACE="10 GB" ;;
    6) REMOTE_TYPE="pcloud";     REMOTE_NAME="pcloud";      FREE_SPACE="10 GB" ;;
    7) REMOTE_TYPE="mega";       REMOTE_NAME="mega";        FREE_SPACE="20 GB" ;;
    8) REMOTE_TYPE="sftp";       REMOTE_NAME="sftp";        FREE_SPACE="depende do servidor" ;;
    *) REMOTE_TYPE="other";      REMOTE_NAME="remote";      FREE_SPACE="depende do provedor" ;;
esac

ok "Provedor: $REMOTE_TYPE (espaco livre ~$FREE_SPACE)"

# ═══════════════════════════════════════
# PASSO 3: AGENDAMENTO
# ═══════════════════════════════════════
step "PASSO 3/5 — Agendamento"
echo ""
echo -e "  Com que frequencia fazer backup?"
echo -e "  Lembre-se: backups frequentes = menos risco de perder dados"
echo ""
SCHEDULE=$(ask_choice "Frequencia" "1" \
    "Diario as 3h da manha (recomendado)" \
    "Diario as 0h (meia-noite)" \
    "A cada 12 horas" \
    "A cada 6 horas" \
    "Semanal (domingo 3h)" \
    "Quinzenal (dias 1 e 15 as 3h)" \
    "Mensal (dia 1 as 3h)" \
    "Nao agendar (so manual)" \
    "Customizado")

case "$SCHEDULE" in
    1) CRON_EXPR="0 3 * * *";         CRON_DESC="Diario as 3h" ;;
    2) CRON_EXPR="0 0 * * *";         CRON_DESC="Diario as 0h" ;;
    3) CRON_EXPR="0 */12 * * *";      CRON_DESC="A cada 12h" ;;
    4) CRON_EXPR="0 */6 * * *";       CRON_DESC="A cada 6h" ;;
    5) CRON_EXPR="0 3 * * 0";         CRON_DESC="Semanal (domingo 3h)" ;;
    6) CRON_EXPR="0 3 1,15 * *";      CRON_DESC="Quinzenal (dias 1 e 15)" ;;
    7) CRON_EXPR="0 3 1 * *";         CRON_DESC="Mensal (dia 1)" ;;
    8) CRON_EXPR="";                   CRON_DESC="Manual (sem cron)" ;;
    9)
        echo -ne "    ${BOLD}Expressao cron: ${NC}"
        read -r CRON_EXPR
        CRON_DESC="Customizado: $CRON_EXPR"
        ;;
esac
ok "Agendamento: $CRON_DESC"

echo ""
ask "Quantos backups manter no provedor" KEEP_BACKUPS "5"
KEEP_BACKUPS="${KEEP_BACKUPS:-5}"
# Validar numero
[[ "$KEEP_BACKUPS" =~ ^[0-9]+$ ]] || KEEP_BACKUPS=5
ok "Retencao: $KEEP_BACKUPS backups"

# ═══════════════════════════════════════
# PASSO 4: OPCOES AVANCADAS
# ═══════════════════════════════════════
step "PASSO 4/5 — Opcoes (tudo tem default, so aperte Enter)"
echo ""

ask "Nivel de compressao (1=rapido, 9=maximo)" COMPRESSION_LEVEL "6"
[[ "$COMPRESSION_LEVEL" =~ ^[1-9]$ ]] || COMPRESSION_LEVEL=6

ask "Tamanho maximo por arquivo (ex: 4G, 2G, 1G)" SPLIT_SIZE "4G"

if ask_yn "Excluir imagens Docker do backup? (economiza MUITO espaco, sao reinstalaveis com docker pull)" "y"; then
    EXCLUDE_DOCKER_IMAGES="true"
else
    EXCLUDE_DOCKER_IMAGES="false"
fi

ask "Pasta de destino no provedor" REMOTE_PATH "Backup-VPS"

# ═══════════════════════════════════════
# PASSO 5: INSTALACAO
# ═══════════════════════════════════════
step "PASSO 5/5 — Instalando"
echo ""

# Deps
info "Instalando dependencias..."
install_pkg zip
install_pkg curl
install_pkg unzip

# rclone
install_rclone

# Criar diretorio
INSTALL_DIR="/opt/vps-snapshot"
mkdir -p "$INSTALL_DIR"

# ═══════════════════════════════════════
# GERAR CONFIG.SH
# ═══════════════════════════════════════
info "Gerando configuracao..."
cat > "$INSTALL_DIR/config.sh" << CFGEOF
#!/usr/bin/env bash
# ═══════════════════════════════════════
# VPS Snapshot - Config
# Gerado automaticamente pelo instalador
# Edite com: sudo nano $INSTALL_DIR/config.sh
# ═══════════════════════════════════════

# Nome da VPS (pasta no provedor)
VPS_NAME="$VPS_NAME"

# Provedor (nome do remote do rclone)
REMOTE_NAME="$REMOTE_NAME"

# Pasta destino no provedor
REMOTE_PATH="$REMOTE_PATH"

# Quantos backups manter
KEEP_BACKUPS=$KEEP_BACKUPS

# Compressao (1-9)
COMPRESSION_LEVEL=$COMPRESSION_LEVEL

# Split size (arquivos maiores sao divididos)
SPLIT_SIZE="$SPLIT_SIZE"

# Excluir imagens Docker
EXCLUDE_DOCKER_IMAGES=$EXCLUDE_DOCKER_IMAGES

# ── Exclusoes ──
EXCLUDE_VFS=(/proc /sys /dev /run /tmp)
EXCLUDE_MOUNTS=(/snap /boot/efi)
EXCLUDE_CACHE=(
    /var/cache/apt/archives /var/cache/yum /var/cache/dnf /var/cache/apt
    /var/lib/apt/lists "*/node_modules" "*/__pycache__" "*/.cache"
    "*/.npm" "*/.pip" "*/.cargo/registry"
)
EXCLUDE_TEMP=(*.log *.tmp *.pid *.sock *.swap nohup.out)
EXCLUDE_SWAP=(/swapfile)
EXCLUDE_SELF=($INSTALL_DIR /tmp/vps-snapshot-*)

# Comandos antes/depois do backup (descomente se precisar):
# PRE_BACKUP_COMMANDS=("systemctl stop meu-app")
# POST_BACKUP_COMMANDS=("systemctl start meu-app")
PRE_BACKUP_COMMANDS=()
POST_BACKUP_COMMANDS=()
CFGEOF
chmod 600 "$INSTALL_DIR/config.sh"
ok "Config criado"

# ═══════════════════════════════════════
# GERAR BACKUP.SH E RESTORE.SH
# (download dos scripts do repo)
# ═══════════════════════════════════════
info "Baixando scripts..."

REPO_RAW="https://raw.githubusercontent.com/SEU_USER/vps-snapshot/main"

for script in backup.sh restore.sh; do
    if curl -fsSL "$REPO_RAW/$script" -o "$INSTALL_DIR/$script" 2>/dev/null; then
        chmod +x "$INSTALL_DIR/$script"
        ok "$script baixado"
    else
        warn "Nao consegui baixar $script do GitHub"
        warn "Voce pode copiar manualmente depois"
        # Criar stub
        echo "#!/bin/bash echo 'Script nao instalado. Copie $script para $INSTALL_DIR/'" > "$INSTALL_DIR/$script"
        chmod +x "$INSTALL_DIR/$script"
    fi
done

# Criar o comando global (symlink)
ln -sf "$INSTALL_DIR/backup.sh" /usr/local/bin/vps-snapshot 2>/dev/null || true
ok "Comando 'vps-snapshot' disponivel"

# ═══════════════════════════════════════
# CONFIGURAR PROVEDOR
# ═══════════════════════════════════════
echo ""
echo -e "  ${BOLD}Agora vamos conectar com o $REMOTE_TYPE...${NC}"
echo ""

if rclone listremotes 2>/dev/null | grep -q "^${REMOTE_NAME}:"; then
    ok "$REMOTE_NAME ja configurado no rclone"
else
    echo -e "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${DIM}Voce vai precisar de uma conta no $REMOTE_TYPE${NC}"
    echo -e "  ${DIM}e autorizar o acesso. O instalador do rclone${NC}"
    echo -e "  ${DIM}vai abrir um link no navegador para voce logar.${NC}"
    echo ""
    echo -e "  ${DIM}Se a VPS nao tem navegador (headless), escolha${NC}"
    echo -e "  ${DIM}a opcao 'token manual' - voce abre o link no${NC}"
    echo -e "  ${DIM}seu celular ou PC e cola o codigo aqui.${NC}"
    echo -e "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    if ask_yn "Configurar $REMOTE_TYPE agora?" "y"; then
        echo ""
        info "Iniciando configuracao do rclone..."
        echo -e "  ${DIM}Dica: nome do remote = ${BOLD}${REMOTE_NAME}${NC}"
        echo ""
        rclone config
    else
        echo ""
        warn "Sem o provedor configurado, o backup nao funciona."
        echo -e "  Configure depois com:"
        echo -e "    ${CYAN}sudo rclone config${NC}"
        echo -e "  Ou refaca a instalacao:"
        echo -e "    ${CYAN}sudo bash install.sh${NC}"
        echo ""
    fi
fi

# ═══════════════════════════════════════
# TESTAR CONEXAO
# ═══════════════════════════════════════
echo ""
info "Testando conexao com $REMOTE_TYPE..."
if rclone lsd "${REMOTE_NAME}:" &>/dev/null; then
    ok "${REMOTE_NAME}: conectado!"
else
    warn "${REMOTE_NAME}: nao conseguiu conectar. Verifique a configuracao."
    echo -e "  ${CYAN}sudo rclone config${NC} para reconfigurar"
fi

# ═══════════════════════════════════════
# CRON
# ═══════════════════════════════════════
if [[ -n "$CRON_EXPR" ]]; then
    cat > /etc/cron.d/vps-snapshot << CRONEOF
# VPS Snapshot - $VPS_NAME
# Instalado: $(date)
# Frequencia: $CRON_DESC ($CRON_EXPR)
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
$CRON_EXPR root $INSTALL_DIR/backup.sh >> $INSTALL_DIR/cron.log 2>&1
CRONEOF
    chmod 644 /etc/cron.d/vps-snapshot
    ok "Cron agendado: $CRON_DESC"
else
    ok "Sem cron - backup so manual"
fi

# ═══════════════════════════════════════
# BACKUP DE TESTE
# ═══════════════════════════════════════
echo ""
if ask_yn "Quer rodar um backup de teste agora?" "n"; then
    echo ""
    info "Executando backup de teste..."
    echo ""
    if "$INSTALL_DIR/backup.sh"; then
        ok "Backup de teste OK! Verifique o provedor."
    else
        warn "Backup de teste falhou. Veja o log:"
        echo -e "  ${CYAN}sudo vps-snapshot log${NC}"
    fi
else
    echo -e "  ${DIM}Para estimar tamanho sem criar backup:${NC}"
    echo -e "  ${CYAN}sudo vps-snapshot estimate${NC}"
fi

# ═══════════════════════════════════════
# RESUMO FINAL
# ═══════════════════════════════════════
clear
cat << FINAL

 ╔═══════════════════════════════════════════════════╗
 ║                                                   ║
 ║        ✅  VPS SNAPSHOT INSTALADO!                 ║
 ║                                                   ║
 ╚═══════════════════════════════════════════════════╝

  VPS:         $VPS_NAME
  Provedor:    $REMOTE_TYPE
  Agendamento: $CRON_DESC
  Retencao:    $KEEP_BACKUPS backups

  ┌─────────────────────────────────────────────┐
  │  Comandos disponiveis:                      │
  │                                             │
  │  vps-snapshot estimate     Estima tamanho   │
  │  vps-snapshot              Backup manual    │
  │  vps-snapshot list         Lista backups    │
  │  vps-snapshot list TS      Ver conteudo     │
  │  vps-snapshot browse TS    Navegar no bkp   │
  │  vps-snapshot extract TS   Extrair partes   │
  │  vps-snapshot full TS      Restaurar tudo   │
  │  vps-snapshot log          Ver ultimo log   │
  │  vps-snapshot status       Ver no provedor  │
  │  vps-snapshot config       Reconfigurar     │
  │                                             │
  └─────────────────────────────────────────────┘

  TS = timestamp do backup (ex: 2025-01-15_03h00m00s)

  Config:   sudo nano /opt/vps-snapshot/config.sh
  Log:      sudo tail -f /opt/vps-snapshot/backup.log

FINAL
