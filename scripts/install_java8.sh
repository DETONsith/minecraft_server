#!/usr/bin/env bash
# ==============================================================================
# JAVA 8 INSTALLER FOR CODESPACES, UBUNTU, DEBIAN & LINUX
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}==================================================================${NC}"
echo -e "${BLUE}          CONFIGURADOR AUTOMÁTICO DE JAVA 8 (FORGE 1.12.2)         ${NC}"
echo -e "${BLUE}==================================================================${NC}"

# 1. Determinar permissões sudo
SUDO=""
if [ "$(id -u)" -ne 0 ] && command -v sudo &>/dev/null; then
    SUDO="sudo"
fi

# 2. Corrigir symlinks de dynamic linkers do Linux se necessário
if [ -n "$SUDO" ] || [ "$(id -u)" -eq 0 ]; then
    $SUDO mkdir -p /lib64 /lib 2>/dev/null || true
    if [ -f "/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2" ]; then
        $SUDO ln -sf /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 /lib64/ld-linux-x86-64.so.2 2>/dev/null || true
    fi
    if [ -f "/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1" ]; then
        $SUDO ln -sf /lib/aarch64-linux-gnu/ld-linux-aarch64.so.1 /lib/ld-linux-aarch64.so.1 2>/dev/null || true
    fi
fi

# 3. Função para checar e validar executável Java 8
check_java8() {
    for cand in \
        /usr/local/sdkman/candidates/java/8*/bin/java \
        "$HOME"/.sdkman/candidates/java/8*/bin/java \
        /usr/lib/jvm/*java-8*/jre/bin/java \
        /usr/lib/jvm/*java-8*/bin/java \
        /usr/lib/jvm/*java-1.8*/bin/java \
        /usr/lib/jvm/*temurin-8*/bin/java \
        /usr/lib/jvm/*temurin-8*/jre/bin/java \
        /usr/lib/jvm/default-java/bin/java \
        "$ROOT_DIR/scripts/bin/java-8/bin/java"; do
        if [ -x "$cand" ]; then
            local v
            v=$("$cand" -version 2>&1 | head -n 1 || true)
            if [[ "$v" =~ "1.8." ]] || [[ "$v" =~ "\"8" ]]; then
                echo "$cand"
                return 0
            fi
        fi
    done
    return 1
}

EXISTING_JAVA=$(check_java8 || true)
if [ -n "$EXISTING_JAVA" ]; then
    echo -e "${GREEN}✓ Java 8 funcional já encontrado: $EXISTING_JAVA${NC}"
    exit 0
fi

# 4. Tentar instalação nativa via APT (Adoptium & OpenJDK PPA)
if command -v apt-get &> /dev/null; then
    echo -e "${YELLOW}-> Instalando pacotes Java 8 nativos via APT...${NC}"
    set +e
    $SUDO apt-get update -y || true
    $SUDO apt-get install -y gnupg wget curl software-properties-common libc6 zlib1g || true
    
    # Repositório Oficial Adoptium
    wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | $SUDO gpg --dearmor -o /etc/apt/trusted.gpg.d/adoptium.gpg 2>/dev/null || true
    UBUNTU_CODENAME=$(lsb_release -cs 2>/dev/null || echo "jammy")
    echo "deb https://packages.adoptium.net/artifactory/deb $UBUNTU_CODENAME main" | $SUDO tee /etc/apt/sources.list.d/adoptium.list 2>/dev/null || true
    
    # PPA OpenJDK Canonical
    $SUDO add-apt-repository -y ppa:openjdk-r/ppa 2>/dev/null || true
    $SUDO apt-get update -y || true
    $SUDO apt-get install -y temurin-8-jdk openjdk-8-jre-headless openjdk-8-jdk 2>/dev/null || true
    set -e
fi

EXISTING_JAVA=$(check_java8 || true)
if [ -n "$EXISTING_JAVA" ]; then
    echo -e "${GREEN}✓ Java 8 instalado com sucesso via APT: $EXISTING_JAVA${NC}"
    exit 0
fi

# 5. Tentar via SDKMAN
for sdk_init in "/usr/local/sdkman/bin/sdkman-init.sh" "$HOME/.sdkman/bin/sdkman-init.sh"; do
    if [ -s "$sdk_init" ]; then
        echo -e "${YELLOW}-> Tentando instalar Java 8 via SDKMAN...${NC}"
        # shellcheck disable=SC1090
        set +e
        source "$sdk_init"
        sdk install java 8.0.412-tem -y || sdk install java 8.0.392-tem -y || sdk install java 8.0.382-zulu -y
        set -e
        break
    fi
done

EXISTING_JAVA=$(check_java8 || true)
if [ -n "$EXISTING_JAVA" ]; then
    echo -e "${GREEN}✓ Java 8 instalado com sucesso via SDKMAN: $EXISTING_JAVA${NC}"
    exit 0
fi

# 6. Fallback final: Download direto do Adoptium JRE 8 portátil com suporte multi-arquitetura
ARCH_RAW=$(uname -m)
ADOPTIUM_ARCH="x64"
case "$ARCH_RAW" in
    aarch64|arm64|armv8*) ADOPTIUM_ARCH="aarch64" ;;
    x86_64|amd64) ADOPTIUM_ARCH="x64" ;;
esac

echo -e "${YELLOW}-> Baixando JRE 8 portátil oficial da Adoptium ($ADOPTIUM_ARCH)...${NC}"
rm -rf "$ROOT_DIR/scripts/bin/java-8"
mkdir -p "$ROOT_DIR/scripts/bin/java-8"
curl -Ls "https://api.adoptium.net/v3/binary/latest/8/ga/linux/${ADOPTIUM_ARCH}/jre/hotspot/normal/eclipse" -o /tmp/java8_install.tar.gz
tar -xzf /tmp/java8_install.tar.gz -C "$ROOT_DIR/scripts/bin/java-8" --strip-components=1
chmod -R 755 "$ROOT_DIR/scripts/bin/java-8"
rm -f /tmp/java8_install.tar.gz

EXISTING_JAVA=$(check_java8 || true)
if [ -n "$EXISTING_JAVA" ]; then
    echo -e "${GREEN}✓ Java 8 portátil configurado e verificado: $EXISTING_JAVA${NC}"
    exit 0
else
    echo -e "${RED}Erro: Não foi possível configurar um Java 8 funcional no sistema.${NC}"
    exit 1
fi
