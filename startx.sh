#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# detecta desktop em português ou inglês
if [ -d "$HOME/Área de Trabalho" ]; then
    DESKTOP="$HOME/Área de Trabalho"
elif [ -d "$HOME/Desktop" ]; then
    DESKTOP="$HOME/Desktop"
else
    mkdir -p "$HOME/Desktop"
    DESKTOP="$HOME/Desktop"
fi

INSTALL_DIR="$HOME/.cache/wine67"
WINE_BIN="$INSTALL_DIR/bin/wine"
WINE_URL="https://github.com/Kron4ek/Wine-Builds/releases/download/11.8/wine-11.8-amd64-wow64.tar.xz"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
MAGENTA='\033[0;35m'

# Detectar ambiente desktop
DESKTOP_SESSION="${DESKTOP_SESSION:-xfce}"
XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-x11}"

# Flags de compatibilidade padrão
DEBUG_MODE=0
COMPAT_LEVEL="medium"  # low, medium, high
USE_DXVK=1
DXVK_HUD=""

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

exibir_logo() {
    clear
    echo -e "${MAGENTA}${BOLD}"
    echo "  ██╗    ██╗██╗███╗   ██╗███████╗ ██████╗ ███████╗"
    echo "  ██║    ██║██║████╗  ██║██╔════╝██╔════╝ ╚════██║"
    echo "  ██║ █╗ ██║██║██╔██╗ ██║█████╗  ███████╗     ██╔╝"
    echo "  ██║███╗██║██║██║╚██╗██║██╔══╝  ██╔═══██╗   ██╔╝ "
    echo "  ╚███╔███╔╝██║██║ ╚████║███████╗╚██████╔╝   ██║  "
    echo "   ╚══╝╚══╝ ╚═╝╚═╝  ╚═══╝╚══════╝ ╚═════╝    ╚═╝  "
    echo -e "${RESET}"
    echo -e "  ${DIM}Wine-Kron4ek wow64 Portable Launcher — sem sudo${RESET}"
    echo -e "  ${DIM}Base: $INSTALL_DIR${RESET}"
    echo -e "  ${DIM}Desktop: $DESKTOP_SESSION | Sessão: $XDG_SESSION_TYPE${RESET}"
    echo ""
}

menu_compatibilidade() {
    echo ""
    echo -e "${BOLD}Selecione o nível de compatibilidade:${RESET}"
    echo ""
    echo -e "  ${YELLOW}[1]${RESET} ${DIM}BAIXO${RESET}   - Máxima compatibilidade (sem DirectX, mais lento)"
    echo -e "  ${YELLOW}[2]${RESET} ${DIM}MÉDIO${RESET}  - Balanceado (DirectX/DXVK padrão)"
    echo -e "  ${YELLOW}[3]${RESET} ${DIM}ALTO${RESET}    - Máxima performance (DXVK HUD + otimizações)"
    echo -e "  ${YELLOW}[4]${RESET} ${DIM}DEBUG${RESET}   - Modo debug com logs detalhados"
    echo ""
    echo -ne "${CYAN}Escolha (1-4): ${RESET}"
    read -r COMPAT_CHOICE

    case "$COMPAT_CHOICE" in
        1)
            COMPAT_LEVEL="low"
            USE_DXVK=0
            DXVK_HUD=""
            ok "Modo: COMPATIBILIDADE (sem DirectX)"
            ;;
        2)
            COMPAT_LEVEL="medium"
            USE_DXVK=1
            DXVK_HUD=""
            ok "Modo: BALANCEADO (DirectX padrão)"
            ;;
        3)
            COMPAT_LEVEL="high"
            USE_DXVK=1
            DXVK_HUD="fps"
            ok "Modo: PERFORMANCE (com HUD de FPS)"
            ;;
        4)
            COMPAT_LEVEL="medium"
            USE_DXVK=1
            DEBUG_MODE=1
            ok "Modo: DEBUG (logs detalhados)"
            ;;
        *)
            aviso "Opção inválida, usando padrão (MÉDIO)"
            COMPAT_LEVEL="medium"
            USE_DXVK=1
            ;;
    esac
}

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
    info "Instalando Wine Kron4ek wow64..."
    local GE_TAR
    GE_TAR=$(buscar_tar)

    if [ -n "$GE_TAR" ]; then
        ok "Arquivo encontrado: $GE_TAR"
    else
        GE_TAR="$INSTALL_DIR/wine-kron4ek.tar.xz"
        baixar "$WINE_URL" "$GE_TAR" "Wine-Kron4ek wow64"
    fi

    local TAR_FLAG TEST_FLAG
    case "$GE_TAR" in
        *.tar.xz) TAR_FLAG="-xJf"; TEST_FLAG="-tJf" ;;
        *.tar.gz) TAR_FLAG="-xzf"; TEST_FLAG="-tzf" ;;
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
    find "$INSTALL_DIR/lib" -type f -exec chmod +x {} \; 2>/dev/null
    find "$INSTALL_DIR/lib64" -type f -exec chmod +x {} \; 2>/dev/null
    ok "Wine instalado!"
}

exibir_logo
menu_compatibilidade

if [ ! -f "$WINE_BIN" ]; then
    instalar_wine
fi

[ ! -x "$WINE_BIN" ] && chmod +x "$WINE_BIN"

ok "Wine: $WINE_BIN"
ok "Versão: $("$WINE_BIN" --version 2>/dev/null || echo 'desconhecida')"

# Configuração do ambiente do wine
export LD_LIBRARY_PATH="$INSTALL_DIR/lib:$INSTALL_DIR/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Detecção de Display (X11 vs Wayland)
if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
    aviso "Detectado Wayland - pode ter incompatibilidades"
    export GDK_BACKEND=x11
    export QT_QPA_PLATFORM=xcb
fi

if [ -z "$DISPLAY" ]; then
    [ -n "$WAYLAND_DISPLAY" ] && export DISPLAY=:0 || export DISPLAY=:0
fi

# Configurações base do Wine
export WINEARCH=win64
export WINE_CPU_TOPOLOGY=4:2
export WINEDLLOVERRIDES="winemenubuilder=d;rpcss=n;ole32=n;midimap=n"
export STAGING_SHARED_MEMORY=1

# Configurações específicas por nível de compatibilidade
if [ "$COMPAT_LEVEL" = "low" ]; then
    export DXVK_FILTER_DEVICE_NAME=""
    export WINE_CPU_TOPOLOGY=2:1
    info "Modo BAIXO: DXVK desativado, CPU reduzida"
elif [ "$COMPAT_LEVEL" = "high" ]; then
    export DXVK_HUD="fps,memory"
    export DXVK_FRAME_RATE=0
    info "Modo ALTO: Performance máxima com HUD"
fi

# Áudio: Detecção melhorada (PipeWire/PulseAudio)
configar_audio() {
    # Verificar PipeWire primeiro
    if pactl info &>/dev/null; then
        local PULSE_SOCKET
        PULSE_SOCKET=$(pactl info 2>/dev/null | grep 'Server String' | awk '{print $3}')
        if [ -n "$PULSE_SOCKET" ]; then
            export PULSE_SERVER="unix:$PULSE_SOCKET"
            ok "Audio: PulseAudio detectado"
            return
        fi
    fi

    # Verificar variáveis de PipeWire
    if [ -S "$XDG_RUNTIME_DIR/pipewire-0" ]; then
        export PIPEWIRE_RUNTIME_DIR="$XDG_RUNTIME_DIR"
        ok "Audio: PipeWire detectado"
        return
    fi

    # Fallback: usar valores padrão
    aviso "Audio: Usando configuração padrão"
}

configar_audio

# Debug mode
if [ $DEBUG_MODE -eq 1 ]; then
    info "Modo DEBUG ativo - criando log..."
    export WINE_DEBUG="+tid,+seh,+relay"
    export DXVK_LOG_LEVEL=debug
    DEBUG_LOG="$INSTALL_DIR/debug_$(date +%s).log"
fi

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
    echo "Jogos encontrados:"
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

# Prefix por jogo
GAME_NAME="$(basename "$SELECTED" .exe | tr -cd '[:alnum:]_-')"
export WINEPREFIX="$INSTALL_DIR/prefixes/$GAME_NAME"
mkdir -p "$WINEPREFIX"

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════╗${RESET}"
echo -e "${GREEN}║ Iniciando: $(basename "$SELECTED")${RESET}"
echo -e "${GREEN}║ Compatibilidade: ${BOLD}$COMPAT_LEVEL${RESET}${GREEN}${RESET}"
echo -e "${GREEN}║ Prefix: $GAME_NAME${RESET}"
if [ $DEBUG_MODE -eq 1 ]; then
    echo -e "${YELLOW}║ Debug Log: $DEBUG_LOG${RESET}"
fi
echo -e "${GREEN}╚═══════════════════════════════════════╝${RESET}"
echo ""

# Executar jogo com captura opcional de erros
if [ $DEBUG_MODE -eq 1 ]; then
    "$WINE_BIN" "$SELECTED" 2>&1 | tee "$DEBUG_LOG"
else
    "$WINE_BIN" "$SELECTED"
fi

EXIT=$?
echo ""
if [ $EXIT -eq 0 ]; then
    ok "Encerrado normalmente."
else
    echo -e "${YELLOW}⚠ Código de saída: $EXIT${RESET}"
    if [ $DEBUG_MODE -eq 1 ]; then
        info "Log salvo em: $DEBUG_LOG"
        echo ""
        echo -e "${DIM}Últimas linhas do log:${RESET}"
        tail -20 "$DEBUG_LOG"
    fi
fi
