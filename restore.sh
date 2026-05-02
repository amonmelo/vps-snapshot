#!/usr/bin/env bash
#
# VPS Snapshot - Restore Engine
# Restauracao completa, seletiva, browse interativo
#
# Uso:
#   sudo vps-snapshot list              Lista backups disponiveis
#   sudo vps-snapshot list TIMESTAMP    Lista conteudo do backup
#   sudo vps-snapshot browse TIMESTAMP  Navega interativo
#   sudo vps-snapshot extract TS /root  Extrai pastas especificas
#   sudo vps-snapshot full TIMESTAMP    Restaura tudo na raiz
#
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; DIM='\033[2m'; MAGENTA='\033[0;35m'; NC='\033[0m'

info()  { echo -e "${CYAN}  [i]${NC} $*"; }
ok()    { echo -e "${GREEN}  [✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}  [!]${NC} $*"; }
die()   { echo -e "${RED}  [✗]${NC} $*" >&2; exit 1; }

(( EUID == 0 )) || die "Rode como root: sudo vps-snapshot ..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config.sh"
[[ -f "$CONFIG" ]] || die "Config nao encontrada: $CONFIG\nRode o instalador primeiro."
source "$CONFIG"

VPS_NAME="${VPS_NAME:-$(hostname)}"
REMOTE="${REMOTE_NAME}:${REMOTE_PATH}"
CACHE_BASE="/tmp/vps-snapshot-restore"

# ═══════════════════════════════════════
# DOWNLOAD
# ═══════════════════════════════════════
ensure_cache() {
    local ts="$1"
    local cache_dir="$CACHE_BASE/$ts"
    local tar_file

    mkdir -p "$cache_dir"

    tar_file=$(ls "$cache_dir"/*.tar.gz 2>/dev/null | head -1)
    if [[ -n "$tar_file" ]] && [[ -f "$tar_file" ]]; then
        echo "$tar_file"
        return
    fi

    info "Buscando backup '$ts' no provedor..."
    local files
    files=$(rclone lsf "$REMOTE/$VPS_NAME/" --files-only 2>/dev/null | grep "$ts" || true)
    [[ -z "$files" ]] && die "Nenhum backup encontrado com timestamp '$ts'"

    info "Baixando..."
    rclone copy "$REMOTE/$VPS_NAME/" "$cache_dir/" \
        --include="*$ts*" --progress --log-level INFO 2>&1

    # Juntar partes
    local parts
    parts=$(ls "$cache_dir"/*.part-* 2>/dev/null || true)
    if [[ -n "$parts" ]]; then
        info "Juntando partes..."
        local first
        first=$(ls "$cache_dir"/*.part-* | head -1)
        local base_name
        base_name=$(basename "$first" | sed 's/\.part-[a-zA-Z0-9]*//')
        cat "$cache_dir"/*.part-* > "$cache_dir/$base_name"
        rm -f "$cache_dir"/*.part-*
    fi

    tar_file=$(ls "$cache_dir"/*.tar.gz 2>/dev/null | head -1)
    [[ -z "$tar_file" ]] && die "Falha ao baixar backup"
    ok "Download concluido: $(du -sh "$tar_file" | cut -f1)"
    echo "$tar_file"
}

# ═══════════════════════════════════════
# LIST
# ═══════════════════════════════════════
cmd_list() {
    local ts="${1:-}"

    if [[ -z "$ts" ]]; then
        echo ""
        echo -e "${BOLD}${CYAN}━━━ BACKUPS DISPONIVEIS ━━━${NC}"
        echo ""

        local files
        files=$(rclone lsf "$REMOTE/$VPS_NAME/" --files-only --sort-by modtime --order-by desc 2>/dev/null || true)
        if [[ -z "$files" ]]; then
            warn "Nenhum backup em $REMOTE/$VPS_NAME/"
            return
        fi

        declare -A groups
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            if [[ "$f" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}h[0-9]{2}m[0-9]{2}s) ]]; then
                groups["${BASH_REMATCH[1]}"]+="$f "
            fi
        done <<< "$files"

        local n=0
        for t in $(printf '%s\n' "${!groups[@]}" | sort -r); do
            n=$(( n + 1 ))
            local cnt
            cnt=$(echo "${groups[$t]}" | wc -w)
            local first size
            first=$(echo "${groups[$t]}" | awk '{print $1}')
            size=$(rclone size "$REMOTE/$VPS_NAME/$first" --json 2>/dev/null | grep -o '"bytes":[0-9]*' | grep -o '[0-9]*' || echo "0")
            if [[ "$size" =~ ^[0-9]+$ ]] && (( size > 0 )); then
                if (( size > 1073741824 )); then
                    size="$(echo "scale=1; $size/1073741824" | bc 2>/dev/null)G"
                elif (( size > 1048576 )); then
                    size="$(echo "scale=1; $size/1048576" | bc 2>/dev/null)M"
                else
                    size="${size}K"
                fi
            else
                size="?"
            fi
            echo -e "  ${BOLD}#$n${NC}  ${CYAN}$t${NC}  ${DIM}${cnt} arq(s), ~${size}${NC}"
        done

        echo ""
        echo -e "  ${DIM}vps-snapshot list TIMESTAMP     Ver conteudo${NC}"
        echo -e "  ${DIM}vps-snapshot browse TIMESTAMP   Navegar${NC}"
        echo -e "  ${DIM}vps-snapshot extract TS /root   Extrair${NC}"
        echo -e "  ${DIM}vps-snapshot full TIMESTAMP     Restaurar tudo${NC}"
        echo ""
        return
    fi

    # Listar conteudo de um backup especifico
    echo ""
    echo -e "${BOLD}${CYAN}━━━ CONTEUDO: $ts ━━━${NC}"
    echo ""

    local tar_file
    tar_file=$(ensure_cache "$ts")

    echo -e "${BOLD}Top-level:${NC}"
    tar tzf "$tar_file" 2>/dev/null | grep -E '^\./[^/]+/$' | sort | while read -r d; do
        d="${d#./}"
        echo -e "  ${CYAN}${d%/}${NC}"
    done

    echo ""
    echo -e "${BOLD}Pastas com mais arquivos (top 20):${NC}"
    tar tzf "$tar_file" 2>/dev/null | grep -v '/$' | sed 's|^\./||' | cut -d'/' -f1-2 | sort | uniq -c | sort -rn | head -20 | while read -r count path; do
        echo -e "  ${DIM}(${count} arqs)${NC}  ${CYAN}${path}${NC}"
    done

    echo ""
    echo -e "  ${DIM}Para extrair: vps-snapshot extract $ts /root /etc${NC}"
    echo ""
}

# ═══════════════════════════════════════
# BROWSE INTERATIVO
# ═══════════════════════════════════════
cmd_browse() {
    local ts="$1"
    local tar_file
    tar_file=$(ensure_cache "$ts")

    ok "Arquivo: $tar_file ($(du -sh "$tar_file" | cut -f1))"

    # Mostrar meta se tiver
    if tar tzf "$tar_file" 2>/dev/null | grep -q "BACKUP-META.txt"; then
        echo ""
        info "Este backup tem metadata. Digite ${BOLD}meta${NC} para ver."
    fi

    echo ""
    echo -e "${BOLD}${CYAN}Modo Browse${NC} — navegue pelo backup"
    echo ""
    echo -e "  Comandos:"
    echo -e "    ${BOLD}ls${NC} [path]         Lista conteudo (vazio = top-level)"
    echo -e "    ${BOLD}find${NC} [palavra]    Busca arquivos por nome"
    echo -e "    ${BOLD}cat${NC} [path]        Le conteudo de um arquivo"
    echo -e "    ${BOLD}get${NC} [path]        Extrai arquivo/pasta"
    echo -e "    ${BOLD}tree${NC} [path]       Mostra estrutura"
    echo -e "    ${BOLD}top${NC}               Maiores pastas"
    echo -e "    ${BOLD}meta${NC}              Info do sistema no backup"
    echo -e "    ${BOLD}quit${NC}              Sair"
    echo ""

    local browse_path="."
    while true; do
        echo -ne "${BOLD}${MAGENTA}browse:${browse_path}${NC}> "
        read -r cmd args

        case "$cmd" in
            quit|exit|q) break ;;

            ls)
                local prefix="./"
                [[ -n "$args" ]] && prefix="./${args#/}"
                tar tzf "$tar_file" 2>/dev/null | grep "^${prefix}" | head -100
                ;;

            find)
                [[ -z "$args" ]] && { echo "Uso: find palavra"; continue; }
                tar tzf "$tar_file" 2>/dev/null | grep -i "$args" | head -100
                ;;

            cat)
                [[ -z "$args" ]] && { echo "Uso: cat ./caminho/arquivo"; continue; }
                tar xzf "$tar_file" -O "$args" 2>/dev/null || echo "(nao encontrado)"
                ;;

            get)
                [[ -z "$args" ]] && { echo "Uso: get ./caminho"; continue; }
                local out_dir="/tmp/vps-snapshot-extracted"
                mkdir -p "$out_dir"
                if tar xzf "$tar_file" -C "$out_dir" --transform='s|^\./||' "$args" 2>/dev/null; then
                    ok "Extraido em: $out_dir/$args"
                else
                    warn "Nao encontrado: $args"
                fi
                ;;

            tree)
                local prefix="./"
                [[ -n "$args" ]] && prefix="./${args#/}"
                tar tzf "$tar_file" 2>/dev/null | grep "^${prefix}" | sort | head -50 | while read -r line; do
                    # Indentacao baseada na profundidade
                    local depth slashes
                    slashes=$(echo "$line" | tr -cd '/' | wc -c)
                    depth=$((slashes - 1))
                    local indent
                    indent=$(printf '%*s' "$((depth * 2))" '')
                    local name
                    name=$(basename "$line")
                    if [[ "$line" == */ ]]; then
                        echo -e "${CYAN}${indent}${name%/}/${NC}"
                    else
                        echo -e "${indent}${name}"
                    fi
                done
                ;;

            top)
                echo -e "${BOLD}Maiores diretorios:${NC}"
                tar tzf "$tar_file" 2>/dev/null | grep -v '/$' | sed 's|^\./||' | cut -d'/' -f1 | sort | uniq -c | sort -rn | head -20
                ;;

            meta)
                tar xzf "$tar_file" -O "BACKUP-META.txt" 2>/dev/null || echo "(sem metadata)"
                ;;

            cd)
                if [[ -z "$args" ]]; then
                    browse_path="."
                else
                    browse_path="$args"
                fi
                ;;

            *)
                echo -e "  Comandos: ls, find, cat, get, tree, top, meta, cd, quit"
                ;;
        esac
    done
}

# ═══════════════════════════════════════
# EXTRACT SELETIVO
# ═══════════════════════════════════════
cmd_extract() {
    local ts="$1"
    shift
    local paths=("$@")

    [[ ${#paths[@]} -eq 0 ]] && die "Passe pelo menos um caminho.\nUso: vps-snapshot extract TIMESTAMP /root /etc/ssh"

    echo ""
    echo -e "${BOLD}${GREEN}━━━ EXTRACAO SELETIVA ━━━${NC}"
    echo -e "  Pastas: ${paths[*]}"
    echo ""

    local tar_file
    tar_file=$(ensure_cache "$ts")

    # Onde extrair?
    echo -e "  ${BOLD}Extrair onde?${NC}"
    echo "    (1) Pasta temporaria /tmp/vps-snapshot-restore-$ts/ (recomendado, seguro)"
    echo "    (2) Na raiz / (sobrescreve arquivos existentes)"
    echo "    (3) Pasta customizada"
    echo ""
    echo -ne "    ${BOLD}Escolha [1]: ${NC}"
    read -r where
    where="${where:-1}"

    case "$where" in
        1) EXTRACT_TO="/tmp/vps-snapshot-restore-$ts/" ;;
        2) EXTRACT_TO="/" ;;
        3)
            echo -ne "    Caminho: "
            read -r EXTRACT_TO
            ;;
        *) EXTRACT_TO="/tmp/vps-snapshot-restore-$ts/" ;;
    esac

    mkdir -p "$EXTRACT_TO"

    if [[ "$EXTRACT_TO" == "/" ]]; then
        warn "Isso vai sobrescrever arquivos no sistema!"
        echo -ne "    Digite ${BOLD}SIM${NC} para confirmar: "
        read -r confirm
        [[ "$confirm" == "SIM" ]] || die "Cancelado"
    fi

    START_TIME=$(date +%s)
    local extracted=0

    for path in "${paths[@]}"; do
        info "Extraindo: $path → $EXTRACT_TO"

        # Tentar varios formatos de path
        local found=false
        for try in "./$path" "$path" ".${path}" "./${path#/}"; do
            count=$(tar tzf "$tar_file" 2>/dev/null | grep -cE "^(\./)?$path" || echo 0)
            if (( count > 0 )); then
                tar xzf "$tar_file" --transform='s|^\./||' -C "$EXTRACT_TO" \
                    --include="*$path*" 2>/dev/null || \
                tar xzf "$tar_file" --transform='s|^\./||' -C "$EXTRACT_TO" "$try" 2>/dev/null
                ok "$path ($count arquivos)"
                extracted=$(( extracted + count ))
                found=true
                break
            fi
        done

        $found || warn "Nao encontrado: $path"
    done

    END_TIME=$(date +%s)
    echo ""
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${GREEN}  EXTRACAO CONCLUIDA                       ${NC}"
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  Destino: $EXTRACT_TO"
    echo -e "  Arquivos: $extracted"
    echo -e "  Tempo:   $(( END_TIME - START_TIME ))s"
    if [[ "$EXTRACT_TO" != "/" ]]; then
        echo -e "  ${CYAN}ls $EXTRACT_TO${NC} para ver"
    fi
    echo ""
}

# ═══════════════════════════════════════
# FULL RESTORE
# ═══════════════════════════════════════
cmd_full() {
    local ts="$1"

    echo ""
    echo -e "${BOLD}${RED}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${RED}║  RESTAURACAO FULL — VPS INTEIRA          ║${NC}"
    echo -e "${BOLD}${RED}╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Timestamp:  $ts"
    echo -e "  Destino:    / (raiz do sistema)"
    echo ""

    warn "ISSO VAI SOBRESCREVER TODOS OS ARQUIVOS DO SISTEMA!"
    warn "Use SOMENTE em uma VPS nova com a MESMA distro/versao."
    echo ""

    local tar_file
    tar_file=$(ensure_cache "$ts")

    # Mostrar meta
    echo -e "${BOLD}Info do backup:${NC}"
    echo -e "  ${DIM}────────────────────────────────────${NC}"
    tar xzf "$tar_file" -O "BACKUP-META.txt" 2>/dev/null | head -12 || echo "  (sem metadata)"
    echo -e "  ${DIM}────────────────────────────────────${NC}"
    echo ""

    echo -ne "    ${BOLD}Digite RESTAURAR-FULL para continuar: ${NC}"
    read -r confirm
    [[ "$confirm" == "RESTAURAR-FULL" ]] || die "Cancelado"

    START_TIME=$(date +%s)
    info "Extraindo backup na raiz..."
    warn "Isso pode demorar..."

    tar xzf "$tar_file" -C / \
        --warning=no-file-changed \
        --warning=no-file-removed \
        2>&1 | tail -3

    END_TIME=$(date +%s)
    DURATION=$(( END_TIME - START_TIME ))

    # Fix machine-id
    info "Regenerando machine-id..."
    rm -f /etc/machine-id 2>/dev/null || true
    systemd-machine-id-setup 2>/dev/null || true

    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║  RESTAURACAO CONCLUIDA!                 ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════╝${NC}"
    echo -e "  Tempo: ${DURATION}s"
    echo ""
    warn "Proximos passos:"
    echo -e "    1. ${BOLD}sudo reboot${NC}"
    echo -e "    2. Apos reboot, verifique: systemctl status, ip a, docker ps"
    echo -e "    3. Confira usuarios: cat /etc/passwd | grep 1000"
    echo -e "    4. BACKUP-META.txt foi extraido na raiz com info completa"
    echo ""
}

# ═══════════════════════════════════════
# ROUTER
# ═══════════════════════════════════════
CMD="${1:-}"
TS="${2:-}"

case "$CMD" in
    list|ls)
        cmd_list "$TS"
        ;;
    browse|nav)
        [[ -z "$TS" ]] && die "Uso: vps-snapshot browse TIMESTAMP\nTimestamps: vps-snapshot list"
        cmd_browse "$TS"
        ;;
    extract|cp|get)
        [[ -z "$TS" ]] && die "Uso: vps-snapshot extract TIMESTAMP /root /etc/ssh ..."
        shift 2
        [[ $# -eq 0 ]] && die "Passe pelo menos um caminho"
        cmd_extract "$TS" "$@"
        ;;
    full|restore)
        [[ -z "$TS" ]] && die "Uso: vps-snapshot full TIMESTAMP"
        cmd_full "$TS"
        ;;
    "")
        cmd_list
        ;;
    *)
        echo ""
        echo -e "${BOLD}VPS Snapshot — Restore${NC}"
        echo ""
        echo "  vps-snapshot list                Listar backups"
        echo "  vps-snapshot list TIMESTAMP      Ver conteudo"
        echo "  vps-snapshot browse TIMESTAMP    Navegar"
        echo "  vps-snapshot extract TS /path    Extrair pastas"
        echo "  vps-snapshot full TIMESTAMP      Restaurar tudo"
        echo ""
        ;;
esac
