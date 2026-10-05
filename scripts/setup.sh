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
        software-properties-common \
        lsb-release 2>/dev/null || true
    echo -e "${GREEN}✓ Dependências base verificadas.${NC}"
fi

# 3. Garantir Java 8 (Obrigatório para Forge 1.12.2 / Stoneblock)
echo -e "\n${YELLOW}[3/5] Verificando e garantindo Java 8...${NC}"
bash "$ROOT_DIR/scripts/install_java8.sh"

# 4. Instalar Playit.gg
echo -e "\n${YELLOW}[4/5] Verificando Playit.gg Agent portátil...${NC}"
mkdir -p "$ROOT_DIR/scripts/bin"
if [ ! -x "$ROOT_DIR/scripts/bin/playit" ]; then
    echo "Baixando binário portátil do playit-agent..."
    ARCH_RAW=$(uname -m)
    PLAYIT_URL="https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-amd64"
    if [[ "$ARCH_RAW" =~ "aarch64" ]] || [[ "$ARCH_RAW" =~ "arm64" ]]; then
        PLAYIT_URL="https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-aarch64"
    fi
    curl -SsLo "$ROOT_DIR/scripts/bin/playit" "$PLAYIT_URL"
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
