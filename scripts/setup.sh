#!/usr/bin/env bash
# ==============================================================================
# MINECRAFT SERVER TEMPLATE - BOOTSTRAP & INSTALLER
# ==============================================================================
set -e

# Determinar o diretório raiz do repositório
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}==================================================================${NC}"
echo -e "${BLUE}       INSTALADOR & PREPARADOR DO MODELO DE SERVIDOR MINECRAFT     ${NC}"
echo -e "${BLUE}==================================================================${NC}"

# 1. Configurar config.env
if [ ! -f "config/config.env" ] && [ ! -f "config.env" ]; then
    echo -e "${YELLOW}[1/5] Criando config/config.env a partir do template...${NC}"
    mkdir -p config
    cp config/config.env.example config/config.env
    echo -e "${GREEN}✓ config/config.env criado!${NC}"
else
    echo -e "${GREEN}✓ Arquivo config.env já existente.${NC}"
fi

# 2. Instalar dependências base do sistema operacional
echo -e "\n${YELLOW}[2/5] Verificando dependências do sistema...${NC}"
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    if sudo -n true 2>/dev/null; then
        SUDO="sudo"
    fi
fi

if command -v apt-get &> /dev/null && [ -n "$SUDO" -o "$(id -u)" -eq 0 ]; then
    $SUDO apt-get update -y || true
    $SUDO apt-get install -y \
        python3 \
        python3-pip \
        python3-venv \
        curl \
        wget \
        tar \
        unzip \
        net-tools \
        rclone \
        gnupg \
        lsb-release 2>/dev/null || true
    echo -e "${GREEN}✓ Dependências base verificadas.${NC}"
fi

# 3. Garantir Java 8 (Obrigatório para Forge 1.12.2 / Stoneblock)
echo -e "\n${YELLOW}[3/5] Verificando Java 8 (Adoptium / OpenJDK 8)...${NC}"
JAVA8_READY=false

# Checar se já temos algum Java 8 no sistema
CANDIDATES=(
    "$ROOT_DIR/scripts/bin/java-8/bin/java"
    "/usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java"
    "/usr/lib/jvm/java-8-openjdk-amd64/bin/java"
    "/usr/lib/jvm/temurin-8-jdk-amd64/bin/java"
    "/usr/lib/jvm/temurin-8-jre-amd64/bin/java"
    /usr/local/sdkman/candidates/java/8.*/bin/java
    "$HOME/.sdkman/candidates/java/8.*/bin/java"
)

for c in "${CANDIDATES[@]}"; do
    if [ -x "$c" ]; then
        V=$("$c" -version 2>&1 | head -n 1)
        if [[ "$V" =~ "1.8." ]] || [[ "$V" =~ "\"8" ]]; then
            echo -e "  ✓ Java 8 detectado em: ${GREEN}$c${NC} ($V)"
            JAVA8_READY=true
            break
        fi
    fi
done

if [ "$JAVA8_READY" = false ]; then
    # Tentar via SDKMAN se presente
    if [ -s "/usr/local/sdkman/bin/sdkman-init.sh" ]; then
        echo "  -> Tentando instalar Java 8 via SDKMAN..."
        # shellcheck disable=SC1091
        source "/usr/local/sdkman/bin/sdkman-init.sh"
        sdk install java 8.0.412-tem -y 2>/dev/null || sdk install java 8.0.392-tem -y 2>/dev/null || true
    fi

    # Tentar via Adoptium APT repo se tivermos permissão de sudo/root
    if command -v apt-get &> /dev/null && [ -n "$SUDO" -o "$(id -u)" -eq 0 ]; then
        echo "  -> Tentando instalar temurin-8-jdk via repositório Adoptium..."
        wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | $SUDO gpg --dearmor -o /etc/apt/trusted.gpg.d/adoptium.gpg 2>/dev/null || true
        echo "deb https://packages.adoptium.net/artifactory/deb $(lsb_release -cs 2>/dev/null || echo 'jammy') main" | $SUDO tee /etc/apt/sources.list.d/adoptium.list 2>/dev/null || true
        $SUDO apt-get update -y || true
        $SUDO apt-get install -y temurin-8-jdk openjdk-8-jre-headless openjdk-8-jdk 2>/dev/null || true
    fi

    # Fallback portátil definitivo: baixar JRE 8 direto da API da Adoptium
    CANDIDATE_FOUND=false
    for c in "${CANDIDATES[@]}"; do
        if [ -x "$c" ]; then
            V=$("$c" -version 2>&1 | head -n 1)
            if [[ "$V" =~ "1.8." ]] || [[ "$V" =~ "\"8" ]]; then
                CANDIDATE_FOUND=true
                break
            fi
        fi
    done

    if [ "$CANDIDATE_FOUND" = false ]; then
        echo "  -> Baixando JRE 8 portátil oficial da Adoptium..."
        mkdir -p "$ROOT_DIR/scripts/bin/java-8"
        curl -Ls "https://api.adoptium.net/v3/binary/latest/8/ga/linux/x64/jre/hotspot/normal/eclipse" -o /tmp/java8.tar.gz
        tar -xzf /tmp/java8.tar.gz -C "$ROOT_DIR/scripts/bin/java-8" --strip-components=1
        rm -f /tmp/java8.tar.gz
        echo -e "${GREEN}✓ Java 8 portátil instalado em scripts/bin/java-8!${NC}"
    fi
fi

# 4. Instalar Playit.gg
echo -e "\n${YELLOW}[4/5] Verificando Playit.gg Agent portátil...${NC}"
mkdir -p "$ROOT_DIR/scripts/bin"
if [ ! -x "$ROOT_DIR/scripts/bin/playit" ]; then
    echo "Baixando binário portátil do playit-agent..."
    curl -SsLo "$ROOT_DIR/scripts/bin/playit" https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-amd64
    chmod +x "$ROOT_DIR/scripts/bin/playit"
    echo -e "${GREEN}✓ Playit.gg instalado em scripts/bin/playit!${NC}"
else
    echo -e "${GREEN}✓ Playit.gg já está instalado.${NC}"
fi

# 5. Configurar Crafty Controller 4 e Permissões
echo -e "\n${YELLOW}[5/5] Ajustando diretórios e permissões de execução...${NC}"
mkdir -p minecraft/crafty
mkdir -p backups

chmod +x "$ROOT_DIR/scripts/"*.sh "$ROOT_DIR/"*.sh 2>/dev/null || true
chmod +x "$ROOT_DIR/scripts/"*.py 2>/dev/null || true

echo -e "\n${GREEN}==================================================================${NC}"
echo -e "${GREEN}       ✓ INSTALAÇÃO E CONFIGURAÇÃO CONCLUÍDAS COM SUCESSO!         ${NC}"
echo -e "${GREEN}==================================================================${NC}"
echo -e "Para iniciar o servidor, execute:"
echo -e "  ${BLUE}./manager.sh 1${NC}\n"
