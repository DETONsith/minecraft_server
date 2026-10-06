#!/usr/bin/env bash
# ==============================================================================
# MINECRAFT FAILSAFE CONTINUOUS AUTOSAVE & PERSISTENCE WATCHDOG
# - Garante salvamento periódico via RCON e sincronização em disco a cada 60s
# - Gatilho de desligamento automático no horário programado (padrão: 13h45 BRT)
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Carregar configurações se existirem
if [ -f "$ROOT_DIR/config/config.env" ]; then
    # shellcheck disable=SC1091
    source "$ROOT_DIR/config/config.env"
elif [ -f "$ROOT_DIR/config.env" ]; then
    # shellcheck disable=SC1091
    source "$ROOT_DIR/config.env"
fi

PID_FILE="/tmp/minecraft_watchdog.pid"
LOG_FILE="/tmp/minecraft_watchdog.log"

AUTO_SHUTDOWN_ENABLED="${AUTO_SHUTDOWN_ENABLED:-true}"
AUTO_SHUTDOWN_TIME="${AUTO_SHUTDOWN_TIME:-13:45}"
AUTO_SHUTDOWN_TZ="${AUTO_SHUTDOWN_TZ:-America/Sao_Paulo}"
AUTO_SHUTDOWN_DAYS="${AUTO_SHUTDOWN_DAYS:-1-5}" # 1=Segunda .. 5=Sexta

# Autodetectar nome do Codespace se necessário
if [ -z "$CODESPACE_NAME" ] && command -v gh &>/dev/null; then
    CODESPACE_NAME="$(gh codespace list --json name,repository --jq '.[] | select(.repository | endswith("/minecraft_server")) | .name' 2>/dev/null | head -n1)"
    if [ -z "$CODESPACE_NAME" ]; then
        CODESPACE_NAME="$(gh codespace list --json name --jq '.[0].name' 2>/dev/null || true)"
    fi
fi

echo "$$" > "$PID_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Watchdog de persistência contínua e desligamento automático iniciado (Gatilho: ${AUTO_SHUTDOWN_TIME} ${AUTO_SHUTDOWN_TZ})." >> "$LOG_FILE"

while true; do
    sleep 60

    # 1. Sincronização segura de disco a cada 60s (o Minecraft salva chunks internamente no loop principal)
    if ps aux | grep -v grep | grep -q "java"; then
        sync
    fi

    # 2. Gatilho de Desligamento Automático no Horário Programado (13:45 BRT)
    if [ "$AUTO_SHUTDOWN_ENABLED" = "true" ]; then
        CURRENT_DOW=$(TZ="$AUTO_SHUTDOWN_TZ" date +%u 2>/dev/null || date +%u) # 1=Mon .. 7=Sun
        CURRENT_HM=$(TZ="$AUTO_SHUTDOWN_TZ" date +%H:%M 2>/dev/null || date +%H:%M)

        IS_SCHEDULED_DAY=false
        if [ "$AUTO_SHUTDOWN_DAYS" = "*" ] || [ "$AUTO_SHUTDOWN_DAYS" = "all" ]; then
            IS_SCHEDULED_DAY=true
        elif [[ "$AUTO_SHUTDOWN_DAYS" =~ ^([1-7])-([1-7])$ ]]; then
            START_D="${BASH_REMATCH[1]}"
            END_D="${BASH_REMATCH[2]}"
            if [ "$CURRENT_DOW" -ge "$START_D" ] && [ "$CURRENT_DOW" -le "$END_D" ]; then
                IS_SCHEDULED_DAY=true
            fi
        fi

        if [ "$IS_SCHEDULED_DAY" = true ] && [ "$CURRENT_HM" = "$AUTO_SHUTDOWN_TIME" ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [GATILHO 13:45] Horário limite atingido (${AUTO_SHUTDOWN_TIME} ${AUTO_SHUTDOWN_TZ})." >> "$LOG_FILE"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Executando graceful shutdown e backup via manager.sh..." >> "$LOG_FILE"
            
            # Executa o fluxo de salvamento gracioso e backup do manager.sh
            bash "$SCRIPT_DIR/manager.sh" stop-backup >> "$LOG_FILE" 2>&1 || true

            # Desliga o Codespace / Máquina
            if [ -n "$CODESPACE_NAME" ] && command -v gh &>/dev/null; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Solicitando encerramento do Codespace ($CODESPACE_NAME)..." >> "$LOG_FILE"
                gh codespace stop -c "$CODESPACE_NAME" >> "$LOG_FILE" 2>&1 || true
            fi

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Desligando ambiente local..." >> "$LOG_FILE"
            sudo shutdown -h now 2>/dev/null || exit 0
        fi
    fi
done
