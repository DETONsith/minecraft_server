#!/usr/bin/env bash
# ==============================================================================
# STONEBLOCK IMPORT & FORGE 1.12.2 SETUP SCRIPT
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}==================================================================${NC}"
echo -e "${CYAN}       IMPORTADOR STONEBLOCK & PREPARADOR FORGE 1.12.2            ${NC}"
echo -e "${CYAN}==================================================================${NC}"

# Carregar config.env se existir
if [ -f "$ROOT_DIR/config/config.env" ]; then
    # shellcheck disable=SC1091
    source "$ROOT_DIR/config/config.env"
fi

SERVER_DIR="$ROOT_DIR/minecraft/server"
DEFAULT_INSTANCE="$HOME/.sklauncher/instances/stoneblock"
INSTANCE_DIR="${1:-$DEFAULT_INSTANCE}"

echo -e "Diretório de destino do servidor: ${BLUE}$SERVER_DIR${NC}"
echo -e "Diretório da instância StoneBlock: ${BLUE}$INSTANCE_DIR${NC}\n"

if [ ! -d "$INSTANCE_DIR" ]; then
    echo -e "${RED}Erro: Instância do Stoneblock não encontrada em: $INSTANCE_DIR${NC}"
    echo "Uso: $0 [caminho/para/instancia/stoneblock]"
    exit 1
fi

mkdir -p "$SERVER_DIR"

# 1. Copiar mods, configs e scripts
echo -e "${YELLOW}[1/5] Copiando mods, configs e scripts do modpack...${NC}"
if [ -d "$INSTANCE_DIR/mods" ]; then
    echo "  -> Copiando mods..."
    rsync -av --delete "$INSTANCE_DIR/mods/" "$SERVER_DIR/mods/"
fi

if [ -d "$INSTANCE_DIR/config" ]; then
    echo "  -> Copiando config..."
    rsync -av "$INSTANCE_DIR/config/" "$SERVER_DIR/config/"
fi

if [ -d "$INSTANCE_DIR/scripts" ]; then
    echo "  -> Copiando CraftTweaker scripts..."
    rsync -av "$INSTANCE_DIR/scripts/" "$SERVER_DIR/scripts/"
fi

if [ -d "$INSTANCE_DIR/resources" ]; then
    echo "  -> Copiando resources..."
    rsync -av "$INSTANCE_DIR/resources/" "$SERVER_DIR/resources/"
fi

if [ -d "$INSTANCE_DIR/structures" ]; then
    echo "  -> Copiando structures..."
    rsync -av "$INSTANCE_DIR/structures/" "$SERVER_DIR/structures/"
fi

echo -e "${GREEN}✓ Arquivos do Modpack copiados com sucesso!${NC}"

# 2. Copiar o Save do Mundo (New World -> world)
echo -e "\n${YELLOW}[2/5] Importando save do mapa...${NC}"
SAVE_SOURCE=""
if [ -d "$INSTANCE_DIR/saves/New World" ]; then
    SAVE_SOURCE="$INSTANCE_DIR/saves/New World"
else
    # Procurar primeiro diretório em saves
    FIRST_SAVE=$(find "$INSTANCE_DIR/saves" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)
    if [ -n "$FIRST_SAVE" ]; then
        SAVE_SOURCE="$FIRST_SAVE"
    fi
fi

if [ -n "$SAVE_SOURCE" ] && [ -d "$SAVE_SOURCE" ]; then
    echo "  -> Encontrado save: $(basename "$SAVE_SOURCE")"
    mkdir -p "$SERVER_DIR/world"
    rsync -av --delete "$SAVE_SOURCE/" "$SERVER_DIR/world/"
    echo -e "${GREEN}✓ Save importado com sucesso para minecraft/server/world!${NC}"
    
    # Sincronizar UUIDs dos jogadores offline
    if [ -f "$ROOT_DIR/scripts/fix_player_uuids.py" ]; then
        python3 "$ROOT_DIR/scripts/fix_player_uuids.py" "$SERVER_DIR/world" "$INSTANCE_DIR"
    fi
else
    echo -e "${YELLOW}Aviso: Nenhum save encontrado em $INSTANCE_DIR/saves. Um novo mundo será gerado ao iniciar.${NC}"
fi

# 3. Detectar Java 8
echo -e "\n${YELLOW}[3/5] Verificando ambiente Java 8...${NC}"
JAVA_EXEC="java"
if [ -n "$JAVA_8_BIN" ] && [ -x "$JAVA_8_BIN" ]; then
    JAVA_EXEC="$JAVA_8_BIN"
elif [ -x "/usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java" ]; then
    JAVA_EXEC="/usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java"
elif [ -x "/usr/lib/jvm/java-8-openjdk-amd64/bin/java" ]; then
    JAVA_EXEC="/usr/lib/jvm/java-8-openjdk-amd64/bin/java"
elif [ -x "/usr/lib/jvm/java-8-openjdk-arm64/jre/bin/java" ]; then
    JAVA_EXEC="/usr/lib/jvm/java-8-openjdk-arm64/jre/bin/java"
elif [ -x "/usr/lib/jvm/temurin-8-jdk-amd64/bin/java" ]; then
    JAVA_EXEC="/usr/lib/jvm/temurin-8-jdk-amd64/bin/java"
fi

echo -e "Usando Java: ${GREEN}$JAVA_EXEC${NC} ($("$JAVA_EXEC" -version 2>&1 | head -n1))"

# 4. Instalar Forge 1.12.2 Server
echo -e "\n${YELLOW}[4/5] Instalando Servidor Forge 1.12.2 (Build 14.23.5.2854)...${NC}"
FORGE_VERSION="1.12.2-14.23.5.2854"
INSTALLER_JAR="forge-${FORGE_VERSION}-installer.jar"
FORGE_JAR="forge-${FORGE_VERSION}.jar"

cd "$SERVER_DIR"

if [ ! -f "$FORGE_JAR" ]; then
    echo "  -> Baixando instalador do Forge 1.12.2..."
    curl -Lo "$INSTALLER_JAR" "https://maven.minecraftforge.net/net/minecraftforge/forge/${FORGE_VERSION}/${INSTALLER_JAR}"
    
    echo "  -> Executando instalação do servidor Forge..."
    "$JAVA_EXEC" -jar "$INSTALLER_JAR" --installServer
    rm -f "$INSTALLER_JAR" "${INSTALLER_JAR}.log"
    echo -e "${GREEN}✓ Forge 1.12.2 Server instalado com sucesso!${NC}"
else
    echo -e "${GREEN}✓ Forge 1.12.2 Server ($FORGE_JAR) já instalado.${NC}"
fi

# 5. Criar EULA, server-icon e server.properties inicial
echo -e "\n${YELLOW}[5/5] Configurando EULA e parâmetros do servidor...${NC}"
echo "eula=true" > "$SERVER_DIR/eula.txt"

if [ -f "$ROOT_DIR/server-icon.png" ]; then
    cp "$ROOT_DIR/server-icon.png" "$SERVER_DIR/server-icon.png"
fi

if [ ! -f "$SERVER_DIR/server.properties" ]; then
    if [ -f "$ROOT_DIR/config/templates/server.properties.template" ]; then
        cp "$ROOT_DIR/config/templates/server.properties.template" "$SERVER_DIR/server.properties"
    fi
fi

cd "$ROOT_DIR"
# Aplicar otimizações automáticas (RCON, online-mode=false, forge.cfg)
bash "$ROOT_DIR/scripts/optimize_server.sh" -q

echo -e "\n${GREEN}==================================================================${NC}"
echo -e "${GREEN}       ✓ STONEBLOCK E SAVE IMPORTADOS COM SUCESSO!                ${NC}"
echo -e "${GREEN}==================================================================${NC}"
echo -e "Para iniciar o servidor, execute:"
echo -e "  ${BLUE}./manager.sh 1${NC} ou use o menu interativo com ${BLUE}./manager.sh${NC}\n"
