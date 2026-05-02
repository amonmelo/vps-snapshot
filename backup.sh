#!/usr/bin/env bash
#
# VPS Snapshot - Backup Engine
# Backup completo da VPS com retry, validacao, dry-run
#
# Uso:
#   sudo vps-snapshot              Backup manual
#   sudo vps-snapshot estimate     Estima tamanho
#   sudo vps-snapshot log          Ver log
#   sudo vps-snapshot status       Status no provedor
#   sudo vps-snapshot config       Editar config
#
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

info()  { echo -e "${CYAN}  [i]${NC} $*"; }
ok()    { echo -e "${GREEN}  [✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}  [!]${NC} $*"; }
die()   { echo -e "${RED}  [✗]${NC} $*" >&2; }

# ═══════════════════════════════════════
# LOAD CONFIG
# ═══════════════════════════════════════
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config.sh"
[[ -f "$CONFIG" ]] || die "Config nao encontrada: $CONFIG\nRode o instalador primeiro."
source "$CONFIG"

VPS_NAME="${VPS_NAME:-$(hostname)}"
REMOTE="${REMOTE_NAME}:${REMOTE_PATH}"
LOG_FILE="$SCRIPT_DIR/backup.log"
LOCK_FILE="/tmp/vps-snapshot.lock"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
logn() { echo -n "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

# ═══════════════════════════════════════
# EXCLUDES
# ═══════════════════════════════════════
build_excludes() {
    for p in "${EXCLUDE_VFS[@]}" "${EXCLUDE_MOUNTS[@]}" "${EXCLUDE_SWAP[@]}" "${EXCLUDE_SELF[@]}"; do
        echo "--exclude=$p"
    done
    for p in "${EXCLUDE_CACHE[@]}"; do
        echo "--exclude=$p"
    done
    for p in "${EXCLUDE_TEMP[@]}"; do
        echo "--exclude=$p"
    done
    if [[ "${EXCLUDE_DOCKER_IMAGES:-false}" == "true" ]] && [[ -d /var/lib/docker ]]; then
        echo "--exclude=/var/lib/docker/overlay2"
        echo "--exclude=/var/lib/docker/image"
    fi
}

EXCLUDE_ARGS=()
while IFS= read -r line; do
    EXCLUDE_ARGS+=("$line")
done < <(build_excludes)

# ═══════════════════════════════════════
# COMANDOS INTERNOS
# ═══════════════════════════════════════

# estimate: calcula tamanho sem criar backup
cmd_estimate() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ ESTIMATIVA DE BACKUP ━━━${NC}"
    echo ""

    EXCLUDE_FROM_FILE="/tmp/vps-snapshot-excludes"
    printf '%s\n' "${EXCLUDE_ARGS[@]}" | sed 's/--exclude=//' > "$EXCLUDE_FROM_FILE"

    echo -e "${BOLD}Por pasta:${NC}"
    TOTAL=0
    for d in /*; do
        [[ -d "$d" ]] || continue
        skip=false
        for ex in "${EXCLUDE_VFS[@]}" "${EXCLUDE_MOUNTS[@]}" "${EXCLUDE_SELF[@]}" "${EXCLUDE_SWAP[@]}"; do
            [[ "$d" == "$ex" ]] && skip=true && break
        done
        $skip && continue
        sz=$(du -shx "$d" --exclude-from="$EXCLUDE_FROM_FILE" 2>/dev/null | tail -1 | awk '{print $1}')
        echo -e "  $(printf '%-25s' "$d") $sz"
    done

    RAW=$(du -shx / --exclude-from="$EXCLUDE_FROM_FILE" 2>/dev/null | tail -1 | awk '{print $1}')
    rm -f "$EXCLUDE_FROM_FILE"

    echo ""
    echo -e "  Total bruto:      ${BOLD}$RAW${NC}"
    echo -e "  Estimativa zipada: ${BOLD}~30-50%${NC}"
    echo ""

    if command -v rclone &>/dev/null; then
        info "Verificando espaco livre no provedor..."
        USED=$(rclone about "${REMOTE_NAME}:" --json 2>/dev/null | grep -o '"used":[0-9]*' | grep -o '[0-9]*' || echo "?")
        FREE=$(rclone about "${REMOTE_NAME}:" --json 2>/dev/null | grep -o '"free":[0-9]*' | grep -o '[0-9]*' || echo "?")
        TOTAL_PROVIDER=$(rclone about "${REMOTE_NAME}:" --json 2>/dev/null | grep -o '"total":[0-9]*' | grep -o '[0-9]*' || echo "?")

        if [[ "$FREE" != "?" ]] && [[ "$FREE" =~ ^[0-9]+$ ]]; then
            if (( FREE > 1073741824 )); then
                FREE_GB=$(echo "scale=1; $FREE/1073741824" | bc 2>/dev/null || echo "?")
            else
                FREE_GB="${FREE}B"
            fi
            ok "Espaco livre no provedor: ~${FREE_GB}"
        else
            warn "Nao conseguiu verificar espaco (provedor pode nao suportar)"
        fi
    fi

    # Contar backups existentes
    echo ""
    info "Backups ja existentes:"
    EXISTING=$(rclone lsf "$REMOTE/$VPS_NAME/" --files-only 2>/dev/null | grep -c ".tar.gz" || echo 0)
    echo -e "  $EXISTING arquivos no provedor"

    if [[ "${EXCLUDE_DOCKER_IMAGES:-false}" == "false" ]] && [[ -d /var/lib/docker ]]; then
        DOCKER_SZ=$(du -sh /var/lib/docker 2>/dev/null | awk '{print $1}')
        echo ""
        warn "Docker images: $DOCKER_SZ"
        echo -e "  ${DIM}Ative EXCLUDE_DOCKER_IMAGES=true no config${NC}"
        echo -e "  ${DIM}para economizar esse espaço (imagens sao reinstalaveis)${NC}"
    fi
    echo ""
}

# log: mostra ultimo log
cmd_log() {
    if [[ -f "$LOG_FILE" ]]; then
        echo ""
        echo -e "${BOLD}Log de backup:${NC}"
        tail -50 "$LOG_FILE"
    else
        warn "Nenhum log encontrado."
    fi
}

# status: info do provedor
cmd_status() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ STATUS ━━━${NC}"
    echo ""
    info "VPS: $VPS_NAME"
    info "Provedor: $REMOTE_NAME"
    info "Destino: $REMOTE/$VPS_NAME/"
    echo ""

    if ! rclone lsd "$REMOTE/$VPS_NAME/" &>/dev/null 2>&1; then
        warn "Pasta nao encontrada no provedor (nenhum backup ainda)"
        return
    fi

    echo -e "${BOLD}Backups:${NC}"
    rclone lsf "$REMOTE/$VPS_NAME/" --files-only 2>/dev/null | sort | while read -r f; do
        [[ -z "$f" ]] && continue
        if [[ "$f" == *.part-* ]]; then
            echo -e "  ${DIM}$f (parte)${NC}"
        else
            echo -e "  $f"
        fi
    done
    echo ""

    # Tamanho total
    TOTAL_SZ=$(rclone size "$REMOTE/$VPS_NAME/" --json 2>/dev/null | grep -o '"bytes":[0-9]*' | grep -o '[0-9]*' || echo "0")
    if [[ "$TOTAL_SZ" =~ ^[0-9]+$ ]] && (( TOTAL_SZ > 0 )); then
        if (( TOTAL_SZ > 1073741824 )); then
            echo -e "Total no provedor: ${BOLD}$(echo "scale=2; $TOTAL_SZ/1073741824" | bc 2>/dev/null || echo "?") GB${NC}"
        elif (( TOTAL_SZ > 1048576 )); then
            echo -e "Total no provedor: ${BOLD}$(echo "scale=2; $TOTAL_SZ/1048576" | bc 2>/dev/null || echo "?") MB${NC}"
        fi
    fi
    echo ""
}

# config: abre editor
cmd_config() {
    if command -v nano &>/dev/null; then
        nano "$CONFIG"
    elif command -v vi &>/dev/null; then
        vi "$CONFIG"
    else
        warn "Editor nao encontrado. Edite manualmente: $CONFIG"
    fi
}

# ═══════════════════════════════════════
# RETRY HELPER
# ═══════════════════════════════════════
retry() {
    local cmd="$1" max_retries="${2:-3}" delay="${3:-10}"
    local attempt=1
    while (( attempt <= max_retries )); do
        logn "Tentativa $attempt/$max_retries: "
        if eval "$cmd" 2>&1 | tee -a "$LOG_FILE"; then
            log "OK"
            return 0
        fi
        log "FALHOU"
        if (( attempt < max_retries )); then
            warn "Tentativa $attempt falhou. Aguardando ${delay}s..."
            sleep "$delay"
            delay=$((delay * 2))  # exponential backoff
        fi
        attempt=$((attempt + 1))
    done
    return 1
}

# ═══════════════════════════════════════
# BACKUP PRINCIPAL
# ═══════════════════════════════════════
cmd_backup() {
    # Lock (evita backups paralelos)
    if [[ -f "$LOCK_FILE" ]]; then
        OLD_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if kill -0 "$OLD_PID" 2>/dev/null; then
            die "Ja existe um backup rodando (PID $OLD_PID).\nEspere terminar ou mate: sudo kill $OLD_PID"
        else
            warn "Lock antigo encontrado (PID $OLD_PID morto). Limpando..."
            rm -f "$LOCK_FILE"
        fi
    fi
    echo $$ > "$LOCK_FILE"
    trap 'rm -f "$LOCK_FILE"' EXIT

    TIMESTAMP="$(date +%Y-%m-%d_%Hh%Mm%Ss)"
    echo ""
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${GREEN}  VPS SNAPSHOT — $VPS_NAME${NC}"
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    log "════════════════════════════════════"
    log "BACKUP INICIADO: $TIMESTAMP"

    # Pre-hooks
    for cmd in "${PRE_BACKUP_COMMANDS[@]:-}"; do
        info "Pre-hook: $cmd"
        eval "$cmd" >> "$LOG_FILE" 2>&1 || warn "Pre-hook falhou (continuando)"
    done

    # Checagens
    command -v rclone &>/dev/null || die "rclone nao instalado. Rode o instalador."
    command -v tar &>/dev/null || die "tar nao encontrado."
    command -v gzip &>/dev/null || die "gzip nao encontrado."

    # Testar provedor
    info "Testando provedor: $REMOTE_NAME..."
    if ! rclone lsd "${REMOTE_NAME}:" &>/dev/null; then
        die "Provedor inacessivel.\nReconfigure com: sudo vps-snapshot config\nDepois: sudo rclone config"
    fi
    ok "$REMOTE_NAME: conectado"

    # Checar espaco em disco
    FREE_DISK=$(df /tmp | tail -1 | awk '{print $4}')
    MIN_DISK=$(( 1024 * 1024 ))  # 1GB em KB
    if (( FREE_DISK < MIN_DISK )); then
        die "Disco quase cheio! Apenas $(( FREE_DISK / 1024 ))MB livres em /tmp.\nLimpe espaco antes de fazer backup."
    fi

    # Metadata
    META_FILE="/tmp/vps-snapshot-meta-$TIMESTAMP.txt"
    info "Coletando metadata..."
    cat > "$META_FILE" << META
VPS Snapshot Backup
══════════════════
Data: $(date -Iseconds)
VPS: $VPS_NAME
Hostname: $(hostname)

--- Sistema ---
$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME)
Kernel: $(uname -r) ($(uname -m))
Uptime: $(uptime)

--- Hardware ---
CPU: $(nproc) cores
RAM: $(free -h | grep Mem | awk '{print $2}')
Disk: $(df -h / | tail -1 | awk '{print $2 " total, " $3 " usado, " $4 " livre"}')

--- Rede ---
$(ip -4 addr show 2>/dev/null | grep 'inet ' | grep -v '127.0.0' | awk '{print $2}' || hostname -I)

--- Usuarios (UID >= 1000) ---
$(awk -F: '$3 >= 1000 {print $1 " (UID:" $3 ")"}' /etc/passwd)

--- Docker ---
$(command -v docker &>/dev/null && echo "Versao: $(docker version --format '{{.Server.Version}}' 2>/dev/null)" || echo "Nao instalado")
$(command -v docker &>/dev/null && docker ps -a --format 'Container: {{.Names}} | {{.Image}} | {{.Status}}' 2>/dev/null || true)

--- Services ativos ---
$(systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null | awk '{print $1}' | head -20 || echo "N/A")

--- Crontabs ---
Root: $(crontab -l 2>/dev/null || echo "(vazio)")

--- Pacotes ---
$(command -v dpkg &>/dev/null && echo "DEB: $(dpkg -l 2>/dev/null | grep '^ii' | wc -l) pacotes" || true)
$(command -v rpm &>/dev/null && echo "RPM: $(rpm -qa 2>/dev/null | wc -l) pacotes" || true)

--- Comandos uteis ---
Listar backup:    vps-snapshot list
Navegar:          vps-snapshot browse $TIMESTAMP
Extrair parcial:  vps-snapshot extract $TIMESTAMP /root /etc
Restaurar tudo:   vps-snapshot full $TIMESTAMP
META
ok "Metadata"

    # Estimativa
    info "Estimando tamanho..."
    EST_RAW=$(du -shx / "${EXCLUDE_ARGS[@]}" 2>/dev/null | tail -1 | awk '{print $1}')
    info "Bruto: ~$EST_RAW | Zipado sera menor"
    log "Estimativa bruta: $EST_RAW"

    # Criar backup
    BACKUP_BASE="/tmp/vps-snapshot-${VPS_NAME}-${TIMESTAMP}"
    BACKUP_FILE="${BACKUP_BASE}.tar.gz"

    info "Criando snapshot..."
    START_TIME=$(date +%s)

    if tar czf "$BACKUP_FILE" \
        --one-file-system \
        --warning=no-file-changed \
        --warning=no-file-removed \
        "${EXCLUDE_ARGS[@]}" \
        / 2>> "$LOG_FILE"; then

        END_TIME=$(date +%s)
        DURATION=$(( END_TIME - START_TIME ))

        if [[ ! -f "$BACKUP_FILE" ]]; then
            die "Arquivo de backup nao foi criado!"
        fi

        SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
        ok "Criado: $SIZE em ${DURATION}s"
        log "Arquivo: $BACKUP_FILE ($SIZE, ${DURATION}s)"
    else
        END_TIME=$(date +%s)
        DURATION=$(( END_TIME - START_TIME ))
        die "Falha ao criar backup (apos ${DURATION}s).\nVerifique o log: $LOG_FILE"
    fi

    # Injetar metadata
    tar rf "${BACKUP_FILE%.gz}" \
        --transform="s|tmp/vps-snapshot-meta-${TIMESTAMP}.txt|BACKUP-META.txt|" \
        "$META_FILE" 2>/dev/null || true
    gzip -f "${BACKUP_FILE%.gz}" 2>/dev/null || true
    rm -f "$META_FILE"

    # Validar tar
    info "Validando arquivo..."
    if tar tzf "$BACKUP_FILE" >/dev/null 2>&1; then
        ok "Arquivo valido"
    else
        warn "Arquivo pode estar corrompido! Tentando novamente sem gzip incremental..."
        # Backup sem metadata se deu problema
        rm -f "$BACKUP_FILE"
        tar czf "$BACKUP_FILE" --one-file-system "${EXCLUDE_ARGS[@]}" / 2>> "$LOG_FILE" || true
        if [[ ! -f "$BACKUP_FILE" ]]; then
            die "Falha persiste. Verifique espaco em disco: df -h"
        fi
    fi

    # Split
    SPLIT_FILES=("$BACKUP_FILE")
    if [[ -n "${SPLIT_SIZE:-}" ]]; then
        FILE_BYTES=$(stat -c%s "$BACKUP_FILE" 2>/dev/null || echo 0)
        case "${SPLIT_SIZE: -1}" in
            G|g) LIMIT=$(( ${SPLIT_SIZE%?} * 1073741824 )) ;;
            M|m) LIMIT=$(( ${SPLIT_SIZE%?} * 1048576 )) ;;
            *)   LIMIT=$(( ${SPLIT_SIZE:-4} * 1073741824 )) ;;
        esac
        if (( FILE_BYTES > LIMIT )); then
            info "Dividindo em blocos de ${SPLIT_SIZE}..."
            split -b "$SPLIT_SIZE" "$BACKUP_FILE" "${BACKUP_BASE}.part-"
            rm -f "$BACKUP_FILE"
            mapfile -t SPLIT_FILES < <(ls "${BACKUP_BASE}.part-"* 2>/dev/null)
            ok "${#SPLIT_FILES[@]} partes"
            log "Split: ${#SPLIT_FILES[@]} partes"
        fi
    fi

    # Upload com retry
    DEST="$REMOTE/$VPS_NAME/"
    info "Enviando para $DEST..."
    log "Upload: $DEST"

    UPLOAD_OK=true
    for file in "${SPLIT_FILES[@]}"; do
        fname=$(basename "$file")
        fsize=$(du -sh "$file" | cut -f1)

        if retry "rclone copy '$file' '$DEST' --progress --log-level INFO" 3 15; then
            ok "$fname ($fsize) enviado"
            rm -f "$file"
        else
            warn "$fname falhou apos 3 tentativas"
            warn "Arquivo mantido em: $file"
            UPLOAD_OK=false
        fi
    done

    if ! $UPLOAD_OK; then
        die "Upload falhou. Arquivos mantidos em /tmp/.\nTente manualmente: rclone copy /tmp/vps-snapshot-* $DEST"
    fi

    rm -f "${BACKUP_BASE}"*
    ok "Upload concluido!"

    # Retencao
    info "Aplicando retencao ($KEEP_BACKUPS backups)..."
    REMOTE_LIST=$(rclone lsf "$DEST" --files-only --sort-by modtime --order-by asc 2>/dev/null || true)

    declare -A GROUPS
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        if [[ "$f" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}h[0-9]{2}m[0-9]{2}s) ]]; then
            GROUPS["${BASH_REMATCH[1]}"]+="$f "
        fi
    done <<< "$REMOTE_LIST"

    TOTAL_GROUPS=$(printf '%s\n' "${!GROUPS[@]}" | grep -c . 2>/dev/null || echo 0)
    if (( TOTAL_GROUPS > KEEP_BACKUPS )); then
        DEL=$(( TOTAL_GROUPS - KEEP_BACKUPS ))
        printf '%s\n' "${!GROUPS[@]}" | sort | head -n "$DEL" | while read -r ts; do
            for f in ${GROUPS[$ts]}; do
                rclone deletefile "$DEST/$f" 2>/dev/null || true
                log "Apagado: $f"
            done
        done
        ok "$DEL backups antigos removidos"
    else
        ok "$TOTAL_GROUPS backups no provedor (limite: $KEEP_BACKUPS)"
    fi

    # Post-hooks
    for cmd in "${POST_BACKUP_COMMANDS[@]:-}"; do
        info "Post-hook: $cmd"
        eval "$cmd" >> "$LOG_FILE" 2>&1 || warn "Post-hook falhou"
    done

    # Sucesso final
    log "BACKUP OK: $TIMESTAMP ($SIZE, ${DURATION}s)"
    echo ""
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${GREEN}  BACKUP CONCLUIDO!                       ${NC}"
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  VPS:     $VPS_NAME"
    echo -e "  Tam:     $SIZE"
    echo -e "  Tempo:   ${DURATION}s"
    echo -e "  Destino: $DEST"
    echo ""
    echo -e "  Explorar:  ${CYAN}vps-snapshot browse $TIMESTAMP${NC}"
    echo -e "  Full:      ${CYAN}vps-snapshot full $TIMESTAMP${NC}"
    echo ""
}

# ═══════════════════════════════════════
# ROUTER
# ═══════════════════════════════════════
CMD="${1:-}"

case "$CMD" in
    estimate|size|dry-run)
        cmd_estimate
        ;;
    log|logs)
        cmd_log
        ;;
    status|info)
        cmd_status
        ;;
    config|edit|configure)
        cmd_config
        ;;
    run|backup|"")
        cmd_backup
        ;;
    *)
        echo ""
        echo -e "${BOLD}VPS Snapshot${NC}"
        echo ""
        echo "  vps-snapshot              Backup manual"
        echo "  vps-snapshot estimate     Estimar tamanho"
        echo "  vps-snapshot log          Ver log"
        echo "  vps-snapshot status       Status no provedor"
        echo "  vps-snapshot config       Editar config"
        echo ""
        echo "  vps-snapshot list         Listar backups"
        echo "  vps-snapshot list TS      Ver conteudo"
        echo "  vps-snapshot browse TS    Navegar"
        echo "  vps-snapshot extract TS   Extrair pastas"
        echo "  vps-snapshot full TS      Restaurar tudo"
        echo ""
        ;;
esac
