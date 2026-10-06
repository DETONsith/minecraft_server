#!/usr/bin/env bash
# ==============================================================================
# MINECRAFT FAILSAFE CONTINUOUS AUTOSAVE & IDLE WATCHDOG
# - Garante salvamento periódico e sincronização em disco a cada 60s
# - Desliga automaticamente se o servidor ficar X minutos sem jogadores online
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

IDLE_SHUTDOWN_ENABLED="${IDLE_SHUTDOWN_ENABLED:-true}"
IDLE_TIMEOUT_MINUTES="${IDLE_TIMEOUT_MINUTES:-10}"

# Autodetectar nome do Codespace se necessário
if [ -z "$CODESPACE_NAME" ] && command -v gh &>/dev/null; then
    CODESPACE_NAME="$(gh codespace list --json name,repository --jq '.[] | select(.repository | endswith("/minecraft_server")) | .name' 2>/dev/null | head -n1)"
    if [ -z "$CODESPACE_NAME" ]; then
        CODESPACE_NAME="$(gh codespace list --json name --jq '.[0].name' 2>/dev/null || true)"
    fi
fi

echo "$$" > "$PID_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Watchdog iniciado (Desligamento por inatividade: ${IDLE_TIMEOUT_MINUTES} min sem jogadores)." >> "$LOG_FILE"

IDLE_MINUTES=0

while true; do
    sleep 60

    # 1. Sincronização segura de disco a cada 60s
    if ps aux | grep -v grep | grep -q "java"; then
        sync
    else
        # Se Java nem está rodando, zerar contador
        IDLE_MINUTES=0
        continue
    fi

    # 2. Monitoramento de jogadores e desligamento por inatividade
    if [ "$IDLE_SHUTDOWN_ENABLED" = "true" ]; then
        RCON_RESP="$(python3 "$SCRIPT_DIR/rcon.py" list 2>/dev/null || true)"
        
        # Verificar se o RCON respondeu (servidor totalmente inicializado e online)
        if echo "$RCON_RESP" | grep -q "players online"; then
            PLAYER_COUNT=$(echo "$RCON_RESP" | grep -oE '[0-9]+/[0-9]+' | head -n1 | cut -d'/' -f1)
            
            if [ -n "$PLAYER_COUNT" ] && [ "$PLAYER_COUNT" -eq 0 ]; then
                IDLE_MINUTES=$((IDLE_MINUTES + 1))
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Servidor vazio: 0 jogadores online ($IDLE_MINUTES/$IDLE_TIMEOUT_MINUTES min)." >> "$LOG_FILE"

                if [ "$IDLE_MINUTES" -ge "$IDLE_TIMEOUT_MINUTES" ]; then
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [GATILHO INATIVIDADE] Servidor atingiu ${IDLE_TIMEOUT_MINUTES} minutos sem jogadores. Encerrando..." >> "$LOG_FILE"
                    
                    # Salva e encerra serviços com backup
                    bash "$SCRIPT_DIR/manager.sh" stop-backup >> "$LOG_FILE" 2>&1 || true

                    # Desliga o Codespace / Máquina
                    if [ -n "$CODESPACE_NAME" ] && command -v gh &>/dev/null; then
                        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Solicitando encerramento do Codespace ($CODESPACE_NAME)..." >> "$LOG_FILE"
                        gh codespace stop -c "$CODESPACE_NAME" >> "$LOG_FILE" 2>&1 || true
                    fi

                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Desligando ambiente local..." >> "$LOG_FILE"
                    sudo shutdown -h now 2>/dev/null || exit 0
                fi
            elif [ -n "$PLAYER_COUNT" ] && [ "$PLAYER_COUNT" -gt 0 ]; then
                if [ "$IDLE_MINUTES" -gt 0 ]; then
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Jogador ativo detectado ($PLAYER_COUNT online). Contador de inatividade zerado." >> "$LOG_FILE"
                fi
                IDLE_MINUTES=0
            fi
        else
            # RCON ainda não respondeu (servidor iniciando ou carregando mods)
            IDLE_MINUTES=0
        fi
    fi
done
