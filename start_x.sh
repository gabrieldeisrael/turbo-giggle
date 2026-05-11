#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Passo 1: sem Desktop — usa cache oculto
INSTALL_DIR="$HOME/.cache/wine67"
WINEPREFIX_DIR="$INSTALL_DIR/prefix32"
WINE_BIN="$INSTALL_DIR/bin/wine"
PROOT_BIN="$INSTALL_DIR/proot"
ROOTFS_DIR="$INSTALL_DIR/rootfs32"

WINE_URL="https://github.com/Kron4ek/Wine-Builds/releases/download/11.8/wine-11.8-amd64-wow64.tar.xz"
PROOT_URL="https://proot.gitlab.io/proot/bin/proot"
# Passo 6: ROOTFS_URL removido (não era usado)

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
MAGENTA='\033[0;35m'

erro()  { echo -e "${RED}❌ $1${RESET}"; exit 1; }
ok()    { echo -e "${GREEN}✔  $1${RESET}"; }
info()  { echo -e "${CYAN}➜  $1${RESET}"; }
aviso() { echo -e "${YELLOW}⚠  $1${RESET}"; }

spinner() {
    local pid=$1
    local msg="${2:-Carregando...}"
    local spin='/-\|'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        local c="${spin:$i:1}"
        echo -ne "\r  ${CYAN}[${c}]${RESET}  ${msg}"
        i=$(( (i+1) % ${#spin} ))
        sleep 0.1
    done
    echo -ne "\r  ${GREEN}[✔]${RESET}  ${msg}\n"
}

clear

echo -e "${MAGENTA}${BOLD}"
echo "  ██╗    ██╗██╗███╗   ██╗███████╗ ██████╗ ███████╗"
echo "  ██║    ██║██║████╗  ██║██╔════╝██╔════╝ ╚════██║"
echo "  ██║ █╗ ██║██║██╔██╗ ██║█████╗  ███████╗     ██╔╝"
echo "  ██║███╗██║██║██║╚██╗██║██╔══╝  ██╔═══██╗   ██╔╝ "
echo "  ╚███╔███╔╝██║██║ ╚████║███████╗╚██████╔╝   ██║  "
echo "   ╚══╝╚══╝ ╚═╝╚═╝  ╚═══╝╚══════╝ ╚═════╝    ╚═╝  "
echo -e "${RESET}"
echo -e "  ${DIM}Wine-Kron4ek Portable Launcher 32-bit — sem sudo${RESET}"
echo -e "  ${DIM}Base: $INSTALL_DIR${RESET}"
echo ""

command -v wget &>/dev/null || command -v curl &>/dev/null || erro "Instale wget ou curl"
command -v tar  &>/dev/null || erro "tar não encontrado"

mkdir -p "$INSTALL_DIR"

baixar() {
    local url="$1" dest="$2" nome="$3"
    if command -v wget &>/dev/null; then
        wget -q -O "$dest" "$url" &
    else
        curl -L -s -o "$dest" "$url" &
    fi
    local dl_pid=$!
    spinner "$dl_pid" "Baixando $nome..."
    wait "$dl_pid"
    [ $? -ne 0 ] && erro "Falha ao baixar $nome"
    command -v file &>/dev/null && file "$dest" 2>/dev/null | grep -qi "HTML\|ASCII text" && \
        { rm -f "$dest"; erro "Servidor retornou erro ao baixar $nome"; }
}

buscar_tar() {
    local resultado=""
    for padrao in "wine-11.8-amd64-wow64.tar.xz" "wine-*.tar.xz" "wine-*.tar.gz" "wine-*.tar"; do
        resultado=$(find "$SCRIPT_DIR" -maxdepth 3 -name "$padrao" 2>/dev/null | head -1)
        [ -n "$resultado" ] && echo "$resultado" && return
        resultado=$(find /media /run/media /mnt -maxdepth 5 -name "$padrao" 2>/dev/null | head -1)
        [ -n "$resultado" ] && echo "$resultado" && return
    done
}

instalar_wine() {
    info "Instalando Wine Kron4ek..."
    mkdir -p "$INSTALL_DIR"

    local GE_TAR
    GE_TAR=$(buscar_tar)

    if [ -n "$GE_TAR" ]; then
        ok "Arquivo encontrado: $GE_TAR"
    else
        GE_TAR="$INSTALL_DIR/wine-kron4ek.tar.xz"
        baixar "$WINE_URL" "$GE_TAR" "Wine-Kron4ek"
    fi

    local TAR_FLAG TEST_FLAG
    case "$GE_TAR" in
        *.tar.xz) TAR_FLAG="-xJf"; TEST_FLAG="-tJf" ;;
        *.tar.gz) TAR_FLAG="-xzf"; TEST_FLAG="-tzf" ;;
        *.tar)
            local FTYPE
            FTYPE=$(file "$GE_TAR" 2>/dev/null || true)
            if echo "$FTYPE" | grep -q "XZ"; then
                TAR_FLAG="-xJf"; TEST_FLAG="-tJf"
            elif echo "$FTYPE" | grep -q "gzip"; then
                TAR_FLAG="-xzf"; TEST_FLAG="-tzf"
            else
                TAR_FLAG="-xf"; TEST_FLAG="-tf"
            fi
            ;;
        *) TAR_FLAG="-xf"; TEST_FLAG="-tf" ;;
    esac

    info "Verificando integridade..."
    tar "$TEST_FLAG" "$GE_TAR" &>/dev/null || erro "Arquivo corrompido."
    ok "Arquivo íntegro."

    tar "$TAR_FLAG" "$GE_TAR" -C "$INSTALL_DIR" --strip-components=1 &
    local tar_pid=$!
    spinner "$tar_pid" "Extraindo Wine (pode demorar)..."
    wait "$tar_pid" || erro "Falha ao extrair. Delete '$INSTALL_DIR' e tente novamente."

    find "$INSTALL_DIR/bin" -type f -exec chmod +x {} \; 2>/dev/null
    ok "Wine instalado!"
}

instalar_proot() {
    if [ ! -f "$PROOT_BIN" ]; then
        baixar "$PROOT_URL" "$PROOT_BIN" "proot"
        chmod +x "$PROOT_BIN"
        ok "proot instalado!"
    else
        ok "proot: ok"
    fi
}

instalar_rootfs() {
    if [ ! -d "$ROOTFS_DIR/lib" ]; then
        local ROOTFS_TAR="$INSTALL_DIR/rootfs32.tar.gz"

        local DEBIAN_URL="https://github.com/gabrieldeisrael/Wine67/releases/download/v1.0/rootfs_i386_wine.tar.xz"
        local FALLBACK_URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86/alpine-minirootfs-3.19.1-x86.tar.gz"

        info "Baixando rootfs Debian i386..."
        if command -v wget &>/dev/null; then
            wget -q -O "$ROOTFS_TAR" "$DEBIAN_URL" &
        else
            curl -L -s -o "$ROOTFS_TAR" "$DEBIAN_URL" &
        fi
        local dl_pid=$!
        spinner "$dl_pid" "Baixando rootfs Debian i386..."
        wait "$dl_pid"
        local dl_exit=$?

        if [ $dl_exit -ne 0 ] || [ ! -s "$ROOTFS_TAR" ] || \
           (command -v file &>/dev/null && file "$ROOTFS_TAR" 2>/dev/null | grep -qi "HTML\|ASCII text"); then
            aviso "Debian falhou. Tentando Alpine x86..."
            rm -f "$ROOTFS_TAR"
            baixar "$FALLBACK_URL" "$ROOTFS_TAR" "Alpine x86"
        fi

        mkdir -p "$ROOTFS_DIR"

        local ROOTFS_FLAG="-xzf"
        command -v file &>/dev/null && file "$ROOTFS_TAR" 2>/dev/null | grep -qi "XZ" && ROOTFS_FLAG="-xJf"

        tar "$ROOTFS_FLAG" "$ROOTFS_TAR" -C "$ROOTFS_DIR" --strip-components=1 2>/dev/null &
        local tar_pid=$!
        spinner "$tar_pid" "Extraindo rootfs..."
        wait "$tar_pid" || erro "Falha ao extrair rootfs. Delete '$ROOTFS_DIR' e tente novamente."
        rm -f "$ROOTFS_TAR"
        ok "rootfs instalado!"
    else
        ok "rootfs: ok"
    fi
}

if [ ! -f "$WINE_BIN" ]; then
    instalar_wine
fi

instalar_proot
instalar_rootfs

[ ! -x "$WINE_BIN" ] && chmod +x "$WINE_BIN"

mkdir -p "$ROOTFS_DIR/opt"

# estrutura básica do rootfs
mkdir -p "$ROOTFS_DIR/root"
mkdir -p "$ROOTFS_DIR/tmp"
mkdir -p "$ROOTFS_DIR/dev/shm"
chmod 1777 "$ROOTFS_DIR/tmp"

# home e tmp isolados
mkdir -p "$INSTALL_DIR/home"
TMP_DIR="$INSTALL_DIR/tmp"
mkdir -p "$TMP_DIR"

ok "Wine: $WINE_BIN"

export WINEPREFIX="$WINEPREFIX_DIR"
mkdir -p "$WINEPREFIX_DIR"
[ -z "$DISPLAY" ] && export DISPLAY=:0

echo ""
echo "Procurando jogos..."

mapfile -t EXES < <(find "$SCRIPT_DIR" -name "*.exe" \
    -not -path "*/.cache/wine67/*" 2>/dev/null | sort)

if [ ${#EXES[@]} -eq 0 ]; then
    echo ""
    echo -ne "  Nenhum .exe encontrado. Digite o caminho: "
    read -r SELECTED
    SELECTED="${SELECTED//\'/}"; SELECTED="${SELECTED//\"/}"
    SELECTED="${SELECTED# }";   SELECTED="${SELECTED% }"
    [ -f "$SELECTED" ] || erro "Arquivo não encontrado: '$SELECTED'"
else
    echo ""
    echo "Jogos:"
    echo ""
    for i in "${!EXES[@]}"; do
        echo -e "  ${YELLOW}[$((i+1))]${RESET} $(basename "${EXES[$i]}")"
    done
    echo ""
    echo -e "  ${CYAN}[0]${RESET} Digitar caminho manualmente"
    echo ""
    echo -ne "${CYAN}Escolha: ${RESET}"
    read -r CHOICE

    if [ "$CHOICE" = "0" ]; then
        echo -ne "  Caminho: "
        read -r SELECTED
        SELECTED="${SELECTED//\'/}"; SELECTED="${SELECTED//\"/}"
        SELECTED="${SELECTED# }";   SELECTED="${SELECTED% }"
    elif [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#EXES[@]}" ]; then
        SELECTED="${EXES[$((CHOICE-1))]}"
    else
        erro "Opção inválida"
    fi
fi

[ -z "$SELECTED" ] && erro "Nenhum arquivo selecionado."
[ ! -f "$SELECTED" ] && erro "Arquivo não encontrado: '$SELECTED'"

# Passo 3: WINEPREFIX por jogo
GAME_NAME="$(basename "$SELECTED" .exe | tr -cd '[:alnum:]_-')"
WINEPREFIX_DIR="$INSTALL_DIR/prefixes/$GAME_NAME"
export WINEPREFIX="$WINEPREFIX_DIR"
mkdir -p "$WINEPREFIX_DIR"

echo ""
echo -e "${GREEN}Iniciando: $(basename "$SELECTED")${RESET}"
echo ""

mkdir -p "$INSTALL_DIR/logs"
LOG_FILE="$INSTALL_DIR/logs/${GAME_NAME}.log"
info "Log: $LOG_FILE"

# permissões corretas no tmp privado + diretório IPC do Wine
chmod 1777 "$TMP_DIR"
mkdir -p "$TMP_DIR/.wine-$(id -u)"
chmod 700  "$TMP_DIR/.wine-$(id -u)"

"$PROOT_BIN" \
    -r "$ROOTFS_DIR" \
    -b "$TMP_DIR:/tmp" \
    -b /tmp/.X11-unix \
    -b /dev \
    -b /proc \
    -b /sys \
    -b /run \
    -b "$INSTALL_DIR:/opt" \
    -b "$INSTALL_DIR/logs:$INSTALL_DIR/logs" \
    -b "$WINEPREFIX_DIR:$WINEPREFIX_DIR" \
    -b "$(dirname "$SELECTED"):$(dirname "$SELECTED")" \
    -b "$INSTALL_DIR/home:$HOME" \
    /bin/sh -c "
        export WINEDEBUG=-all
        export DISPLAY='$DISPLAY'
        export WINEPREFIX='$WINEPREFIX_DIR'
        export LD_LIBRARY_PATH='/opt/lib:/opt/lib64:/opt/lib/wine:/opt/lib64/wine'
        /usr/bin/wine '$SELECTED' &>> '$LOG_FILE'
    "

EXIT=$?
echo ""
[ $EXIT -eq 0 ] && ok "Encerrado." || echo -e "${YELLOW}⚠ Código de saída: $EXIT${RESET}"
