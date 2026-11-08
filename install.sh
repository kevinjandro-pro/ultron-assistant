#!/usr/bin/env bash
# ==============================================================================
# Instalador Determinista e Interactivo: Ultrón Assistant para Antigravity
# Protocolo de Cero Suposiciones (Zero-Assumption Protocol)
# ==============================================================================

set -e

GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
BOLD="\033[1m"
NC="\033[0m"

echo -e "${BLUE}${BOLD}"
echo "=========================================================="
echo "    🚀 INSTALADOR AUTÓNOMO: CENTINELA 'HEY ULTRÓN'      "
echo "=========================================================="
echo -e "${NC}"

# ------------------------------------------------------------------------------
# 1. Comprobación de Sistema Operativo y Arquitectura
# ------------------------------------------------------------------------------
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${RED}❌ Este instalador está diseñado exclusivamente para macOS.${NC}"
    exit 1
fi

ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]] && [[ $(sysctl -n sysctl.proc_translated 2>/dev/null) == "1" ]]; then
    echo -e "${YELLOW}⚠️ Advertencia: Estás ejecutando esta terminal bajo emulación Rosetta.${NC}"
    echo "  Se recomienda ejecutar en una terminal nativa ARM64 (Apple Silicon) para mejor rendimiento de Whisper."
fi

# ------------------------------------------------------------------------------
# 2. Comprobación y Resolución de Dependencias Base (ffmpeg, Homebrew)
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}[Fase 1/5] Verificando dependencias del sistema...${NC}"

if ! command -v brew &>/dev/null; then
    echo -e "${YELLOW}⚠️ Homebrew no está instalado en este equipo.${NC}"
    echo "¿Deseas instalar Homebrew ahora para resolver dependencias automáticamente? (s/n)"
    read -r install_brew
    if [[ "$install_brew" =~ ^[sSyY]$ ]]; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null)"
    else
        echo -e "${RED}❌ Se requiere Homebrew o dependencias manuales para continuar.${NC}"
        exit 1
    fi
fi

if ! command -v ffmpeg &>/dev/null; then
    echo -e "${YELLOW}⚠️ 'ffmpeg' no está presente.${NC} Instalando mediante Homebrew..."
    brew install ffmpeg
else
    echo -e "${GREEN}✅ ffmpeg detectado en: $(command -v ffmpeg)${NC}"
fi

if ! command -v python3 &>/dev/null; then
    echo -e "${YELLOW}⚠️ 'python3' no está presente.${NC} Instalando mediante Homebrew..."
    brew install python@3.12
else
    echo -e "${GREEN}✅ Python3 detectado: $(python3 --version)${NC}"
fi

# ------------------------------------------------------------------------------
# 3. Diagnóstico Interactivo de Audio y Micrófono
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}[Fase 2/5] Diagnóstico de hardware de audio y micrófono...${NC}"

detect_microphones() {
    ffmpeg -f avfoundation -list_devices true -i "" 2>&1 | awk '/AVFoundation audio devices:/,0' | grep '\[[0-9]*\]' || true
}

SELECTED_MIC="auto"

while true; do
    MIC_LIST=$(detect_microphones)
    if [[ -z "$MIC_LIST" ]]; then
        echo -e "${RED}⚠️ No se detectó ningún dispositivo de entrada de audio (micrófono).${NC}"
        echo "  - Si tu Mac está en modo 'Clamshell' (tapa cerrada), el micrófono interno se desactiva por seguridad."
        echo "  - Si usas un Mac Studio / Mac Mini, necesitas conectar un micro USB o auriculares."
        echo ""
        echo "Opciones: [R] Conectar y Reintentar | [C] Cancelar instalación"
        read -r -p "Selecciona una opción [r/c]: " mic_choice
        case "$mic_choice" in
            [rR]*)
                echo "Reescaneando dispositivos..."
                sleep 1
                ;;
            *)
                echo -e "${YELLOW}Instalación pausada limpiamente. Vuelve a ejecutar cuando conectes un micrófono.${NC}"
                exit 0
                ;;
        esac
    else
        echo -e "${GREEN}✅ Dispositivos de audio detectados:${NC}"
        echo "$MIC_LIST"
        break
    fi
done

# Prueba rápida de permisos TCC de micrófono
echo -e "\n${BOLD}Verificando permisos de acceso al micrófono en macOS...${NC}"
TEST_AUDIO_FILE="/tmp/ultron_test_mic.wav"
rm -f "$TEST_AUDIO_FILE"
ffmpeg -loglevel error -y -f avfoundation -i ":0" -t 0.5 "$TEST_AUDIO_FILE" 2>/dev/null || true

if [[ ! -s "$TEST_AUDIO_FILE" ]]; then
    echo -e "${YELLOW}⚠️ No se pudo capturar audio de prueba. Es posible que la terminal no tenga permisos de Micrófono en macOS.${NC}"
    echo "¿Deseas abrir Ajustes del Sistema > Privacidad > Micrófono para otorgar permiso? (s/n)"
    read -r -p "[s/n]: " open_tcc
    if [[ "$open_tcc" =~ ^[sSyY]$ ]]; then
        open "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        echo "Presiona ENTER una vez hayas concedido el permiso a tu terminal..."
        read -r
    fi
else
    echo -e "${GREEN}✅ Permiso de micrófono comprobado con éxito.${NC}"
fi
rm -f "$TEST_AUDIO_FILE"

# ------------------------------------------------------------------------------
# 4. Verificación de Antigravity y Puerto CDP
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}[Fase 3/5] Verificando conexión con Antigravity...${NC}"
PORT_FILE="$HOME/Library/Application Support/Antigravity/DevToolsActivePort"

if [[ ! -f "$PORT_FILE" ]]; then
    echo -e "${YELLOW}⚠️ Antigravity no parece estar en ejecución (no se encontró DevToolsActivePort).${NC}"
    echo "¿Deseas iniciar Antigravity ahora para verificar el enlace? (s/n)"
    read -r -p "[s/n]: " start_agy
    if [[ "$start_agy" =~ ^[sSyY]$ ]]; then
        open -a Antigravity 2>/dev/null || echo "No se pudo abrir automáticamente. Por favor ábrelo manualmente."
        echo "Esperando a que Antigravity inicialice el puerto..."
        for i in {1..10}; do
            if [[ -f "$PORT_FILE" ]]; then
                echo -e "${GREEN}✅ Antigravity detectado y vinculado.${NC}"
                break
            fi
            sleep 1
        done
    fi
else
    echo -e "${GREEN}✅ Puerto CDP de Antigravity detectado: $(head -n 1 "$PORT_FILE")${NC}"
fi

# ------------------------------------------------------------------------------
# 5. Despliegue del Entorno Aislado (.venv) y Archivos
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}[Fase 4/5] Desplegando entorno virtual y dependencias...${NC}"

TARGET_DIR="$HOME/.config/ultron-assistant"
mkdir -p "$TARGET_DIR"

if [[ ! -d "$TARGET_DIR/.venv" ]]; then
    echo "Creando entorno virtual aislado en $TARGET_DIR/.venv..."
    python3 -m venv "$TARGET_DIR/.venv"
fi

BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"

RAW_BASE="https://raw.githubusercontent.com/kevinjandro-pro/ultron-assistant/main"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

echo "Descargando / desplegando archivos del asistente..."
if [[ -n "$SCRIPT_DIR" ]] && [[ -f "$SCRIPT_DIR/assistant.py" ]]; then
    cp "$SCRIPT_DIR/assistant.py" "$TARGET_DIR/assistant.py"
    cp "$SCRIPT_DIR/requirements.txt" "$TARGET_DIR/requirements.txt"
    if [[ ! -f "$TARGET_DIR/config.json" ]] && [[ -f "$SCRIPT_DIR/config.example.json" ]]; then
        cp "$SCRIPT_DIR/config.example.json" "$TARGET_DIR/config.json"
    fi
    cp "$SCRIPT_DIR/ultron" "$BIN_DIR/ultron"
else
    echo "Descargando componentes desde GitHub ($RAW_BASE)..."
    curl -fsSL "$RAW_BASE/assistant.py" -o "$TARGET_DIR/assistant.py"
    curl -fsSL "$RAW_BASE/requirements.txt" -o "$TARGET_DIR/requirements.txt"
    if [[ ! -f "$TARGET_DIR/config.json" ]]; then
        curl -fsSL "$RAW_BASE/config.example.json" -o "$TARGET_DIR/config.json"
    fi
    curl -fsSL "$RAW_BASE/ultron" -o "$BIN_DIR/ultron"
fi

chmod +x "$TARGET_DIR/assistant.py"
chmod +x "$BIN_DIR/ultron"

echo "Instalando dependencias de Python (faster-whisper, websockets, numpy)..."
"$TARGET_DIR/.venv/bin/pip" install --quiet --upgrade pip
"$TARGET_DIR/.venv/bin/pip" install --quiet -r "$TARGET_DIR/requirements.txt"

# ------------------------------------------------------------------------------
# 6. Verificación del Comando CLI (ultron) en PATH
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}[Fase 5/5] Verificando comando CLI 'ultron' en PATH...${NC}"

# Asegurar que ~/.local/bin esté en PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    SHELL_RC="$HOME/.zshrc"
    if [[ -f "$HOME/.bash_profile" ]]; then
        SHELL_RC="$HOME/.bash_profile"
    fi
    echo "export PATH=\"$BIN_DIR:\$PATH\"" >> "$SHELL_RC"
    export PATH="$BIN_DIR:$PATH"
    echo -e "${YELLOW}ℹ️ Se agregó $BIN_DIR a tu archivo $SHELL_RC para acceso global.${NC}"
fi

echo -e "\n${GREEN}${BOLD}=========================================================="
echo "    🎉 ¡INSTALACIÓN COMPLETADA CON ÉXITO!                 "
echo "==========================================================${NC}"
echo ""
echo "Comandos disponibles:"
echo "  • ${BOLD}ultron on${NC}      -> Inicia la escucha en segundo plano"
echo "  • ${BOLD}ultron off${NC}     -> Detiene el centinela por completo"
echo "  • ${BOLD}ultron status${NC}  -> Muestra estado y consumo"
echo "  • ${BOLD}ultron logs${NC}    -> Muestra los registros en tiempo real"
echo "  • ${BOLD}ultron test${NC}    -> Ejecuta el autodiagnóstico"
echo ""
echo "Para arrancar ahora mismo, ejecuta:"
echo -e "  ${BOLD}${BLUE}ultron on${NC}\n"
