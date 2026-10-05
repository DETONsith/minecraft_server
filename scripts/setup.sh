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

# 2. Atualizar pacotes do sistema e Instalar Java 8 (Obrigatório para Forge 1.12.2 / Stoneblock)
echo -e "\n${YELLOW}[2/5] Verificando dependências do sistema e Java 8...${NC}"
if command -v apt-get &> /dev/null; then
    sudo apt-get update -y
    sudo apt-get install -y \
        openjdk-8-jre-headless \
        openjdk-8-jdk \
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
        lsb-release 2>/dev/null || {
            echo -e "${YELLOW}Tentando instalar via Adoptium repo caso falhe...${NC}"
            wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/adoptium.gpg 2>/dev/null || true
            echo "deb https://packages.adoptium.net/artifactory/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/adoptium.list 2>/dev/null || true
            sudo apt-get update -y
            sudo apt-get install -y temurin-8-jdk || true
        }
    echo -e "${GREEN}✓ Dependências base e Java 8 instalados.${NC}"
else
    echo -e "${YELLOW}Aviso: Gerenciador apt-get não encontrado. Certifique-se de ter Java 8, Python 3 e rclone instalados manualmente.${NC}"
fi

# 3. Instalar Playit.gg
echo -e "\n${YELLOW}[3/5] Verificando Playit.gg Agent portátil...${NC}"
mkdir -p "$ROOT_DIR/scripts/bin"
if [ ! -x "$ROOT_DIR/scripts/bin/playit" ]; then
    echo "Baixando binário portátil do playit-agent..."
    curl -SsLo "$ROOT_DIR/scripts/bin/playit" https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-amd64
    chmod +x "$ROOT_DIR/scripts/bin/playit"
    echo -e "${GREEN}✓ Playit.gg instalado em scripts/bin/playit!${NC}"
else
    echo -e "${GREEN}✓ Playit.gg já está instalado.${NC}"
fi

# 4. Configurar Crafty Controller 4
echo -e "\n${YELLOW}[4/5] Configurando Crafty Controller 4...${NC}"
mkdir -p minecraft/crafty
mkdir -p backups

if [ ! -d "minecraft/crafty/crafty-4" ]; then
    echo "Clonando repositório oficial do Crafty 4..."
    cd minecraft/crafty
    git clone https://gitlab.com/crafty-controller/crafty-4.git crafty-4
    cd crafty-4
    git checkout tags/v4.4.7 2>/dev/null || git checkout master 2>/dev/null || true
    cd "$ROOT_DIR"
fi

# Configurar venv Python para o Crafty
if [ ! -d "minecraft/crafty/.venv" ]; then
    echo "Criando ambiente virtual Python para o Crafty..."
    python3 -m venv minecraft/crafty/.venv
    # shellcheck disable=SC1091
    source minecraft/crafty/.venv/bin/activate
    pip install --upgrade pip
    if [ -f "minecraft/crafty/crafty-4/requirements.txt" ]; then
        pip install -r minecraft/crafty/crafty-4/requirements.txt
    fi
    deactivate
    echo -e "${GREEN}✓ Ambiente virtual do Crafty configurado.${NC}"
else
    echo -e "${GREEN}✓ Ambiente virtual do Crafty já configurado.${NC}"
fi

# 5. Permissões de Execução
echo -e "\n${YELLOW}[5/5] Ajustando permissões de execução dos scripts...${NC}"
chmod +x "$ROOT_DIR/scripts/"*.sh "$ROOT_DIR/"*.sh 2>/dev/null || true

echo -e "\n${GREEN}==================================================================${NC}"
echo -e "${GREEN}       ✓ INSTALAÇÃO E CONFIGURAÇÃO CONCLUÍDAS COM SUCESSO!         ${NC}"
echo -e "${GREEN}==================================================================${NC}"
echo -e "Para iniciar e gerenciar o servidor, execute:"
echo -e "  ${BLUE}./manager.sh${NC}\n"
