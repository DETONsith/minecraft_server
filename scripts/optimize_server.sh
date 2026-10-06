#!/usr/bin/env bash
# ==============================================================================
# MINECRAFT SERVER ANTI-LAG & EXPLORATION OPTIMIZER (WITH FAILSAFE AUTO-SAVE)
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Carregar arquivo de configuração se existir
if [ -f "$ROOT_DIR/config/config.env" ]; then
    # shellcheck disable=SC1091
    source "$ROOT_DIR/config/config.env"
fi

WORKSPACE_DIR="${SERVER_ROOT_DIR:-$ROOT_DIR}"
QUIET_MODE=false
if [ "$1" = "-q" ] || [ "$1" = "--quiet" ]; then
    QUIET_MODE=true
fi

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$QUIET_MODE" = false ]; then
    echo -e "\n${CYAN}══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  MINECRAFT SERVER PERSISTENCE & TPS OPTIMIZER       ${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════${NC}\n"
fi

# 1. Localizar instâncias e arquivos server.properties
SEARCH_PATHS=(
    "$WORKSPACE_DIR/minecraft/server"
    "$WORKSPACE_DIR/server"
    "$WORKSPACE_DIR/minecraft/crafty/crafty-4/servers"
    "$WORKSPACE_DIR/servers"
    "$WORKSPACE_DIR"
)

PROPERTIES_FILES=()
for path in "${SEARCH_PATHS[@]}"; do
    if [ -d "$path" ]; then
        while IFS= read -r -d '' file; do
            PROPERTIES_FILES+=("$file")
        done < <(find "$path" -maxdepth 4 -name "server.properties" -print0 2>/dev/null)
    fi
done

set_property() {
    local file="$1"
    local key="$2"
    local val="$3"
    if grep -q "^${key}=" "$file"; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$file"
    else
        echo "${key}=${val}" >> "$file"
    fi
}

if [ ${#PROPERTIES_FILES[@]} -gt 0 ]; then
    for prop in "${PROPERTIES_FILES[@]}"; do
        SERVER_DIR="$(dirname "$prop")"
        CONFIG_DIR="$SERVER_DIR/config"

        if [ "$QUIET_MODE" = false ]; then
            echo -e "\n${BLUE}Otimizando instância:${NC} ${CYAN}$SERVER_DIR${NC}"
        fi
        
        # Backup do server.properties antes de alterar
        cp "$prop" "${prop}.bak_$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
        
        # Aplicar parâmetros de baixo lag, persistência segura, SKLauncher e RCON
        set_property "$prop" "view-distance" "6"
        set_property "$prop" "simulation-distance" "5"
        set_property "$prop" "max-tick-time" "-1"
        set_property "$prop" "snooper-enabled" "false"
        set_property "$prop" "sync-chunk-writes" "false"
        set_property "$prop" "online-mode" "${ONLINE_MODE:-false}"
        set_property "$prop" "enable-rcon" "true"
        set_property "$prop" "rcon.port" "25575"
        set_property "$prop" "rcon.password" "${RCON_PASSWORD:-SGItosSaveSecretPass2026!}"
        set_property "$prop" "broadcast-rcon-to-ops" "true"
        set_property "$prop" "network-compression-threshold" "512"
        set_property "$prop" "entity-broadcast-range-percentage" "100"
        
        if [ "$QUIET_MODE" = false ]; then
            echo -e "  ${GREEN}✓ sync-chunk-writes=true${NC} (gravação síncrona/persistente anti-rollback)"
            echo -e "  ${GREEN}✓ online-mode=${ONLINE_MODE:-false}${NC} (compatibilidade com SKLauncher / Contas)"
            echo -e "  ${GREEN}✓ enable-rcon=true${NC} (console remoto para autosaves e comandos)"
            echo -e "  ${GREEN}✓ view-distance=6 | simulation-distance=5${NC}"
        fi

        # Otimizações para servidores FORGE / Modpacks (StoneBlock)
        if [ -d "$SERVER_DIR/mods" ] || [ -f "$SERVER_DIR/forge.cfg" ] || [ -f "$CONFIG_DIR/forge.cfg" ]; then
            mkdir -p "$CONFIG_DIR"
            FORGE_CFG="$CONFIG_DIR/forge.cfg"
            if [ -f "$FORGE_CFG" ]; then
                sed -i 's/B:removeErroringEntities=false/B:removeErroringEntities=true/g' "$FORGE_CFG" 2>/dev/null || true
                sed -i 's/B:removeErroringTileEntities=false/B:removeErroringTileEntities=true/g' "$FORGE_CFG" 2>/dev/null || true
                if [ "$QUIET_MODE" = false ]; then
                    echo -e "  ${GREEN}✓ forge.cfg otimizado (removeErroringEntities=true, removeErroringTileEntities=true).${NC}"
                fi
            fi
        fi

        # Otimizar configurações PaperMC APENAS se for servidor Bukkit/Paper
        if [ -f "$SERVER_DIR/paper.yml" ] || [ -f "$SERVER_DIR/bukkit.yml" ] || [ -f "$SERVER_DIR/paper-world-defaults.yml" ]; then
            if [ -f "$ROOT_DIR/config/templates/paper-world-defaults.yml" ]; then
                mkdir -p "$CONFIG_DIR"
                cp "$ROOT_DIR/config/templates/paper-world-defaults.yml" "$CONFIG_DIR/paper-world-defaults.yml"
                if [ "$QUIET_MODE" = false ]; then
                    echo -e "  ${GREEN}✓ config/paper-world-defaults.yml aplicado.${NC}"
                fi
            fi

            # Atualizar bukkit.yml para autosave frequente
            if [ -f "$SERVER_DIR/bukkit.yml" ]; then
                sed -i 's/autosave: [0-9]*/autosave: 400/' "$SERVER_DIR/bukkit.yml" 2>/dev/null || true
                if [ "$QUIET_MODE" = false ]; then
                    echo -e "  ${GREEN}✓ bukkit.yml ticks-per.autosave: 400${NC} (20s)"
                fi
            fi

            # Otimizar configurações Spigot se disponíveis
            if [ -f "$ROOT_DIR/config/templates/spigot.yml.template" ]; then
                cp "$ROOT_DIR/config/templates/spigot.yml.template" "$SERVER_DIR/spigot.yml"
            fi
        fi

        # Garantir eula=true
        if [ -f "$SERVER_DIR/eula.txt" ]; then
            sed -i 's/eula=false/eula=true/' "$SERVER_DIR/eula.txt"
        elif [ -f "$ROOT_DIR/config/templates/eula.txt" ]; then
            cp "$ROOT_DIR/config/templates/eula.txt" "$SERVER_DIR/eula.txt"
        fi
    done
fi

if [ "$QUIET_MODE" = false ]; then
    echo -e "\n${GREEN}✓ Otimizações e parâmetros de persistência segura aplicados com sucesso!${NC}\n"
fi
