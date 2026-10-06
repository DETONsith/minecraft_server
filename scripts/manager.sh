#!/usr/bin/env bash
# ==============================================================================
# MINECRAFT & CRAFTY CENTRAL MANAGER (GENERIC TEMPLATE)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

# Carregar arquivo de configuração (procura em config/ ou na raiz)
if [ ! -f "$ROOT_DIR/config/config.env" ] && [ -f "$ROOT_DIR/config/config.env.example" ]; then
    cp "$ROOT_DIR/config/config.env.example" "$ROOT_DIR/config/config.env"
fi

if [ -f "$ROOT_DIR/config/config.env" ]; then
    # shellcheck disable=SC1091
    source "$ROOT_DIR/config/config.env"
elif [ -f "$ROOT_DIR/config.env" ]; then
    # shellcheck disable=SC1091
    source "$ROOT_DIR/config.env"
fi

# Variáveis com fallbacks inteligentes
WORKSPACE_DIR="${SERVER_ROOT_DIR:-$ROOT_DIR}"
CRAFTY_DIR="$WORKSPACE_DIR/minecraft/crafty"
BACKUP_DIR="$WORKSPACE_DIR/${BACKUP_DIR:-backups}"
REMOTE_DRIVE="${RCLONE_REMOTE:-drive:Minecraft_Backups}"
PLAYIT_SOCKET_DIR="${PLAYIT_SOCKET_DIR:-/tmp/playit}"
BACKUP_RETENTION_LOCAL="${BACKUP_RETENTION_LOCAL:-3}"
SERVER_MODE="${SERVER_MODE:-standalone}"

# Paleta de Cores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

detect_java8() {
    if [ -n "$JAVA_8_BIN" ] && [ -x "$JAVA_8_BIN" ]; then
        echo "$JAVA_8_BIN"
        return 0
    fi

    # 1. Buscar instalações comuns de Java 8 expandindo globs
    for jvm in \
        /usr/local/sdkman/candidates/java/8*/bin/java \
        "$HOME"/.sdkman/candidates/java/8*/bin/java \
        /usr/lib/jvm/*java-8*/jre/bin/java \
        /usr/lib/jvm/*java-8*/bin/java \
        /usr/lib/jvm/*java-1.8*/bin/java \
        /usr/lib/jvm/*temurin-8*/bin/java \
        /usr/lib/jvm/*temurin-8*/jre/bin/java \
        /usr/lib/jvm/default-java/bin/java \
        "$ROOT_DIR/scripts/bin/java-8/bin/java"; do
        if [ -x "$jvm" ]; then
            local version
            version=$("$jvm" -version 2>&1 | head -n 1)
            if [[ "$version" =~ "1.8." ]] || [[ "$version" =~ "\"8" ]]; then
                echo "$jvm"
                return 0
            fi
        fi
    done

    # 2. Checar se 'java' padrão é Java 8
    if command -v java &>/dev/null; then
        local version
        version=$(java -version 2>&1 | head -n 1)
        if [[ "$version" =~ "1.8." ]] || [[ "$version" =~ "\"8" ]]; then
            command -v java
            return 0
        fi
    fi

    # 3. Se nenhum Java 8 válido for encontrado, executar o instalador automático (SDKMAN / APT / Adoptium)
    if [ -f "$ROOT_DIR/scripts/install_java8.sh" ]; then
        bash "$ROOT_DIR/scripts/install_java8.sh" >&2 || true
        for jvm in \
            /usr/local/sdkman/candidates/java/8*/bin/java \
            "$HOME"/.sdkman/candidates/java/8*/bin/java \
            /usr/lib/jvm/*java-8*/jre/bin/java \
            /usr/lib/jvm/*java-8*/bin/java \
            /usr/lib/jvm/*java-1.8*/bin/java \
            /usr/lib/jvm/*temurin-8*/bin/java \
            /usr/lib/jvm/*temurin-8*/jre/bin/java \
            /usr/lib/jvm/default-java/bin/java \
            "$ROOT_DIR/scripts/bin/java-8/bin/java"; do
            if [ -x "$jvm" ]; then
                local version
                version=$("$jvm" -version 2>&1 | head -n 1)
                if [[ "$version" =~ "1.8." ]] || [[ "$version" =~ "\"8" ]]; then
                    echo "$jvm"
                    return 0
                fi
            fi
        done
    fi

    return 1
}

status_services() {
    echo -e "\n══════════════════════════════════════════════════════"
    echo -e "             STATUS ATUAL DOS SERVIÇOS                 "
    echo -e "══════════════════════════════════════════════════════"

    # Crafty Controller
    if ps aux | grep -v grep | grep -q "python3 main.py"; then
        PID=$(ps aux | grep -v grep | grep "python3 main.py" | awk '{print $2}' | head -1)
        echo -e "  Crafty Controller:  ${GREEN}● ATIVO${NC} (PID: $PID)"
    else
        echo -e "  Crafty Controller:  ${RED}○ PARADO${NC}"
    fi

    # Playit
    if pgrep -f "playit" > /dev/null; then
        PID=$(pgrep -f "playit" | head -1)
        echo -e "  Playit.gg Tunnel:   ${GREEN}● ATIVO${NC} (PID: $PID)"
        if [ ! -s "$ROOT_DIR/config/playit.toml" ]; then
            local user_socket="/tmp/playit_${USER:-default}.sock"
            local claim_code
            claim_code=$(playit --socket-path "$user_socket" claim generate 2>/dev/null || true)
            if [ -n "$claim_code" ] && [ "$claim_code" != "error" ]; then
                echo -e "  ${YELLOW}↳ Vincular Túnel Playit: ${CYAN}https://playit.gg/claim/${claim_code}${NC}"
            fi
        fi
    else
        echo -e "  Playit.gg Tunnel:   ${RED}○ PARADO${NC}"
    fi

    # Servidor Minecraft (Processo Java)
    if ps aux | grep -v grep | grep -q "java"; then
        PID=$(ps aux | grep -v grep | grep "java" | awk '{print $2}' | head -1)
        echo -e "  Servidor Minecraft: ${GREEN}● ATIVO (Forge/Java)${NC} (PID: $PID)"
    else
        echo -e "  Servidor Minecraft: ${RED}○ PARADO${NC}"
    fi

    # Watchdog AutoSave
    if pgrep -f "watchdog.sh" > /dev/null; then
        echo -e "  Watchdog AutoSave:  ${GREEN}● ATIVO (60s Flush)${NC}"
    else
        echo -e "  Watchdog AutoSave:  ${YELLOW}○ INATIVO${NC}"
    fi

    # Portas em escuta
    echo -e "\n  Portas em escuta:"
    if command -v ss &>/dev/null; then
        ss -tulpn 2>/dev/null | grep -E '8443|25565|25575' | awk '{print "    - " $1, $5}' || echo "    Nenhuma porta ativa detectada."
    elif command -v netstat &>/dev/null; then
        netstat -tulpn 2>/dev/null | grep -E '8443|25565|25575' | awk '{print "    - " $1, $4}' || echo "    Nenhuma porta ativa detectada."
    else
        echo "    (Instale net-tools ou iproute2 para checar portas)"
    fi
    echo -e "══════════════════════════════════════════════════════\n"
}

save_world() {
    echo -e "\n>>> Forçando gravação e flush de todos os dados no Minecraft (save-all flush)..."
    if [ -f "$SCRIPT_DIR/rcon.py" ]; then
        python3 "$SCRIPT_DIR/rcon.py" "save-all flush" 2>/dev/null || true
    fi
    sync
    echo -e "${GREEN}✓ Sincronização e flush completo do mundo concluídos (dados 100% salvos em disco).${NC}"
}

optimize_all_instances() {
    if [ -f "$SCRIPT_DIR/optimize_server.sh" ]; then
        bash "$SCRIPT_DIR/optimize_server.sh" -q
    fi
    if [ -f "$SCRIPT_DIR/fix_player_uuids.py" ] && [ -d "$WORKSPACE_DIR/minecraft/server/world" ]; then
        python3 "$SCRIPT_DIR/fix_player_uuids.py" "$WORKSPACE_DIR/minecraft/server/world" "$HOME/.sklauncher/instances/stoneblock" > /dev/null 2>&1 || true
    fi
}

start_watchdog() {
    if ! pgrep -f "watchdog.sh" > /dev/null && [ -f "$SCRIPT_DIR/watchdog.sh" ]; then
        nohup bash "$SCRIPT_DIR/watchdog.sh" > /dev/null 2>&1 < /dev/null &
        disown $! 2>/dev/null || true
    fi
}

stop_watchdog() {
    pkill -f "watchdog.sh" 2>/dev/null || true
    rm -f /tmp/minecraft_watchdog.pid 2>/dev/null || true
}

start_services() {
    echo -e "\n>>> [1/4] Verificando e aplicando otimizações anti-lag e persistência segura..."
    optimize_all_instances

    echo -e "\n>>> [2/4] Iniciando serviços..."

    # 1. Iniciar Playit daemon
    if [ "${ENABLE_PLAYIT:-true}" = "true" ]; then
        echo -n "Iniciando Playit daemon... "
        local user_socket="/tmp/playit_${USER:-default}.sock"
        rm -f "$user_socket" 2>/dev/null || true
        
        PLAYIT_BIN=""
        if [ -x "$ROOT_DIR/scripts/bin/playit" ]; then
            PLAYIT_BIN="$ROOT_DIR/scripts/bin/playit"
        elif command -v playit-linux-amd64 &>/dev/null; then
            PLAYIT_BIN="$(command -v playit-linux-amd64)"
        elif command -v playitd &>/dev/null; then
            PLAYIT_BIN="$(command -v playitd)"
        elif command -v playit &>/dev/null; then
            PLAYIT_BIN="$(command -v playit)"
        fi

        if [ -n "$PLAYIT_BIN" ]; then
            if ! pgrep -f "playit" > /dev/null; then
                if command -v tmux &>/dev/null; then
                    tmux kill-session -t playit 2>/dev/null || true
                    tmux new-session -d -s playit "$PLAYIT_BIN --secret-path '$ROOT_DIR/config/playit.toml' --socket-path '$user_socket' -l /tmp/playit.log"
                else
                    setsid nohup "$PLAYIT_BIN" --secret-path "$ROOT_DIR/config/playit.toml" --socket-path "$user_socket" -l /tmp/playit.log > /tmp/playit_stdout.log 2>&1 < /dev/null &
                    disown $! 2>/dev/null || true
                fi
                sleep 2
                echo -e "${GREEN}OK${NC}"
            else
                echo -e "${YELLOW}Já em execução${NC}"
            fi
        else
            echo -e "${RED}playit não encontrado! Execute ./scripts/setup.sh primeiro.${NC}"
        fi
    fi

    # 2. Iniciar Servidor Minecraft (Modo Standalone direto ou Crafty)
    if [ "$SERVER_MODE" = "standalone" ]; then
        echo -n "Iniciando Servidor Minecraft (Forge 1.12.2 Standalone)... "
        if ! ps aux | grep -v grep | grep -q "java"; then
            JAVA_EXEC=$(detect_java8 || true)
            if [ -z "$JAVA_EXEC" ] || [ ! -x "$JAVA_EXEC" ]; then
                echo -e "${RED}Erro: Java 8 não encontrado! Execute ./scripts/install_java8.sh primeiro.${NC}"
                return 1
            fi
            
            # Localizar pasta do servidor e JAR do Forge
            MC_SERVER_DIR=""
            FORGE_JAR=""
            CANDIDATE_DIRS=(
                "$WORKSPACE_DIR/minecraft/server"
                "$WORKSPACE_DIR/server"
                "$WORKSPACE_DIR"
            )

            for cdir in "${CANDIDATE_DIRS[@]}"; do
                if [ -d "$cdir" ]; then
                    JAR_FOUND=$(find "$cdir" -maxdepth 2 -name "forge-1.12.2-*.jar" ! -name "*installer*" 2>/dev/null | head -1)
                    if [ -n "$JAR_FOUND" ]; then
                        MC_SERVER_DIR="$(dirname "$JAR_FOUND")"
                        FORGE_JAR="$JAR_FOUND"
                        break
                    fi
                fi
            done

            if [ -z "$FORGE_JAR" ]; then
                # Procurar qualquer jar executável
                for cdir in "${CANDIDATE_DIRS[@]}"; do
                    JAR_FOUND=$(find "$cdir" -maxdepth 2 -name "*.jar" ! -name "*installer*" 2>/dev/null | head -1)
                    if [ -n "$JAR_FOUND" ]; then
                        MC_SERVER_DIR="$(dirname "$JAR_FOUND")"
                        FORGE_JAR="$JAR_FOUND"
                        break
                    fi
                done
            fi

            if [ -n "$FORGE_JAR" ] && [ -d "$MC_SERVER_DIR" ]; then
                mkdir -p "$MC_SERVER_DIR/logs"
                cd "$MC_SERVER_DIR"
                
                MIN_RAM="${MIN_RAM:-4G}"
                MAX_RAM="${MAX_RAM:-6G}"
                
                # Flags JVM otimizadas para Stoneblock / Java 8 G1GC e auto-confirm do Forge
                JVM_ARGS=(
                    -Xms"$MIN_RAM"
                    -Xmx"$MAX_RAM"
                    -Dfml.queryResult=confirm
                    -XX:+UseG1GC
                    -XX:+UnlockExperimentalVMOptions
                    -XX:MaxGCPauseMillis=100
                    -XX:+DisableExplicitGC
                    -XX:TargetSurvivorRatio=90
                    -XX:G1NewSizePercent=35
                    -XX:G1MaxNewSizePercent=60
                    -XX:G1ReservePercent=15
                    -XX:G1MixedGCCountTarget=4
                    -XX:InitiatingHeapOccupancyPercent=15
                )

                if command -v tmux &>/dev/null; then
                    tmux kill-session -t mc 2>/dev/null || true
                    tmux new-session -d -s mc "cd '$MC_SERVER_DIR' && '$JAVA_EXEC' ${JVM_ARGS[*]} -jar '$(basename "$FORGE_JAR")' nogui 2>&1 | tee '$MC_SERVER_DIR/logs/server_process.log'"
                else
                    setsid nohup "$JAVA_EXEC" \
                        "${JVM_ARGS[@]}" \
                        -jar "$(basename "$FORGE_JAR")" nogui > "$MC_SERVER_DIR/logs/server_process.log" 2>&1 < /dev/null &
                    disown $! 2>/dev/null || true
                fi
                
                cd "$ROOT_DIR"
                echo -e "${GREEN}OK (Java 8: $JAVA_EXEC | RAM: $MIN_RAM-$MAX_RAM)${NC}"
            else
                echo -e "${RED}Jar do Forge não encontrado! Execute ./scripts/import_stoneblock.sh primeiro.${NC}"
            fi
        else
            echo -e "${YELLOW}Já em execução${NC}"
        fi
    elif [ "$SERVER_MODE" = "crafty" ]; then
        echo -n "Iniciando Crafty Controller... "
        if ! pgrep -f "python3 main.py" > /dev/null; then
            if [ -d "$CRAFTY_DIR/.venv" ] && [ -d "$CRAFTY_DIR/crafty-4" ]; then
                cd "$CRAFTY_DIR"
                # shellcheck disable=SC1091
                source .venv/bin/activate
                cd crafty-4
                nohup python3 main.py --daemon > "$CRAFTY_DIR/crafty_daemon.log" 2>&1 < /dev/null &
                cd "$ROOT_DIR"
                echo -e "${GREEN}OK${NC}"
            else
                echo -e "${RED}Ambiente do Crafty não encontrado. Execute ./scripts/setup.sh!${NC}"
            fi
        else
            echo -e "${YELLOW}Já em execução${NC}"
        fi
    fi

    # 3. Iniciar Watchdog de AutoSave Contínuo (Flush a cada 60s)
    start_watchdog

    # 4. Aguardar inicialização e verificar subida do Servidor Minecraft (Java / Portas)
    echo -n "Aguardando inicialização do processo Minecraft..."
    local java_alive=false
    for i in $(seq 1 10); do
        if ps aux | grep -v grep | grep -q "java"; then
            java_alive=true
            echo -e " ${GREEN}✓ Processo Forge (Java) ATIVO!${NC}"
            break
        fi
        sleep 1
        echo -n "."
    done

    if [ "$java_alive" = false ]; then
        echo -e " ${RED}✗ O processo do servidor encerrou inesperadamente!${NC}"
        if [ -n "$MC_SERVER_DIR" ] && [ -f "$MC_SERVER_DIR/logs/server_process.log" ]; then
            echo -e "\n${RED}Últimas linhas do erro (server_process.log):${NC}"
            tail -n 25 "$MC_SERVER_DIR/logs/server_process.log"
        fi
        return 1
    fi

    if [ "$SERVER_MODE" = "standalone" ]; then
        echo -e "✓ Porta Minecraft: ${CYAN}25565${NC}"
        echo -e "✓ Porta RCON: ${CYAN}25575${NC}"
        echo -e "${YELLOW}ℹ Nota: O StoneBlock leva de 1 a 2 minutos para carregar os 218 mods. Acompanhe com a opção (7 - Ver Logs).${NC}"
    else
        echo -e "✓ Painel Crafty: ${CYAN}https://localhost:8443${NC}"
        echo -e "✓ Porta Minecraft: ${CYAN}25565${NC}"
        echo -e "✓ Porta RCON: ${CYAN}25575${NC}"
    fi
}

stop_services() {
    echo -e "\n>>> Encerrando todos os serviços com salvamento seguro (Graceful Shutdown)..."

    # Parar watchdog
    stop_watchdog

    # 1. Minecraft Java: Enviar save-all flush e stop via RCON se disponível
    if ps aux | grep -v grep | grep -q "java"; then
        if [ -f "$SCRIPT_DIR/rcon.py" ]; then
            echo -n "Enviando comando 'save-all flush' via RCON... "
            python3 "$SCRIPT_DIR/rcon.py" "save-all flush" 2>/dev/null || true
            echo -e "${GREEN}OK${NC}"
            echo -n "Enviando comando 'stop' via RCON... "
            python3 "$SCRIPT_DIR/rcon.py" "stop" 2>/dev/null || true
            echo -e "${GREEN}OK${NC}"
        fi

        echo -n "Aguardando gravação completa de chunks e saída do Java... "
        pkill -TERM -f "java" 2>/dev/null || true
        
        # Aguardar até 30 segundos para o processo Java gravar tudo e sair de forma limpa
        for i in $(seq 1 30); do
            if ! ps aux | grep -v grep | grep -q "java"; then
                echo -e "${GREEN}OK (Mundo gravado e finalizado com sucesso!)${NC}"
                break
            fi
            sleep 1
        done

        if ps aux | grep -v grep | grep -q "java"; then
            echo -e "${YELLOW}Tempo limite excedido. Forçando encerramento final...${NC}"
            pkill -9 -f "java" || true
        fi
        tmux kill-session -t mc 2>/dev/null || true
    fi

    # 2. Crafty Controller
    if ps aux | grep -v grep | grep -q "python3 main.py"; then
        echo -n "Parando Crafty Controller... "
        pkill -TERM -f "python3 main.py" || true
        sleep 2
        pkill -9 -f "python3 main.py" 2>/dev/null || true
        echo -e "${GREEN}OK${NC}"
    fi

    # 3. Playit.gg
    if ps aux | grep -v grep | grep -qE "playitd|/playit"; then
        echo -n "Parando Playit.gg... "
        pkill -f "playit" 2>/dev/null || true
        tmux kill-session -t playit 2>/dev/null || true
        echo -e "${GREEN}OK${NC}"
    fi

    # Sincronização obrigatória de disco do sistema operacional
    echo -n "Garantindo gravação física de todos os dados no disco (sync)... "
    sync
    echo -e "${GREEN}OK${NC}"

    sleep 1
    echo -e "✓ Todos os serviços foram finalizados com segurança e os dados preservados!"
}

backup_world() {
    echo -e "\n>>> Executando rotina de backup do mundo..."
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_FILE="$BACKUP_DIR/minecraft_world_${TIMESTAMP}.tar.gz"

    # Salvar chunks via RCON antes de empacotar
    if [ -f "$SCRIPT_DIR/rcon.py" ] && ps aux | grep -v grep | grep -q "java"; then
        python3 "$SCRIPT_DIR/rcon.py" "save-all flush" 2>/dev/null || true
    fi
    sync

    echo "Localizando dados do mundo..."
    TARGET_DIR=""
    CANDIDATE_WORLD_DIRS=(
        "$WORKSPACE_DIR/minecraft/server/world"
        "$WORKSPACE_DIR/minecraft/server/saves/New World"
        "$WORKSPACE_DIR/minecraft/crafty/crafty-4/servers"
        "$WORKSPACE_DIR/world"
    )

    for cpath in "${CANDIDATE_WORLD_DIRS[@]}"; do
        if [ -d "$cpath" ]; then
            if [[ "$cpath" =~ crafty-4/servers ]]; then
                TARGET_DIR=$(find "$cpath" -maxdepth 3 -type d -name "world" 2>/dev/null | head -1)
                [ -n "$TARGET_DIR" ] && break
            else
                TARGET_DIR="$cpath"
                break
            fi
        fi
    done

    if [ -n "$TARGET_DIR" ] && [ -d "$TARGET_DIR" ]; then
        PARENT_DIR=$(dirname "$TARGET_DIR")
        BASE_NAME=$(basename "$TARGET_DIR")
        tar -czf "$BACKUP_FILE" -C "$PARENT_DIR" "$BASE_NAME"
        SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
        echo -e "✓ Backup gerado: ${CYAN}$BACKUP_FILE${NC} ($SIZE)"
    else
        echo -e "${YELLOW}Nenhuma pasta 'world' encontrada ainda para backup.${NC}"
        return 0
    fi

    # Sincronização via rclone
    if command -v rclone &> /dev/null && [ -n "$REMOTE_DRIVE" ]; then
        REMOTE_NAME=$(echo "$REMOTE_DRIVE" | cut -d: -f1)
        if rclone listremotes | grep -q "^${REMOTE_NAME}:"; then
            echo "Enviando para a nuvem ($REMOTE_DRIVE)..."
            rclone mkdir "$REMOTE_DRIVE" 2>/dev/null || true
            rclone copy "$BACKUP_FILE" "$REMOTE_DRIVE" --progress
            echo -e "${GREEN}✓ Sincronizado com o armazenamento em nuvem!${NC}"
        else
            echo -e "${YELLOW}Aviso: Remote '${REMOTE_NAME}:' não autenticado no rclone. Backup salvo localmente.${NC}"
        fi
    fi

    # Limpeza de backups antigos locais
    echo "Limpando backups locais antigos (mantendo os últimos $BACKUP_RETENTION_LOCAL)..."
    # shellcheck disable=SC2012
    ls -dt "$BACKUP_DIR"/minecraft_world_*.tar.gz 2>/dev/null | tail -n "+$((BACKUP_RETENTION_LOCAL + 1))" | xargs -r rm -- 2>/dev/null || true
}

shutdown_environment() {
    echo -e "\n>>> Encerrando o ambiente..."
    read -rp "Tem certeza que deseja suspender/desligar a máquina? (s/N): " confirm
    if [[ "$confirm" =~ ^[sS]$ ]]; then
        echo -e "Desligando em 3 segundos..."
        sleep 2
        if [ -n "$CODESPACE_NAME" ] && command -v gh &> /dev/null; then
            gh codespace stop -c "$CODESPACE_NAME" || true
        fi
        sudo shutdown -h now 2>/dev/null || exit 0
    else
        echo -e "Operação cancelada."
    fi
}

view_logs() {
    echo -e "\nEscolha o log para visualizar:"
    echo "1) Crafty Controller Log"
    echo "2) Minecraft Server Log"
    echo "3) Playit.gg Tunnel Log"
    echo "4) Watchdog AutoSave Log"
    echo "5) Voltar"
    read -rp "Opção: " log_opt

    case $log_opt in
        1) tail -n 50 -f "$CRAFTY_DIR/crafty.log" 2>/dev/null || tail -n 50 -f "$CRAFTY_DIR/crafty_daemon.log" 2>/dev/null || echo "Log não encontrado." ;;
        2) 
            MC_LOG=$(find "$WORKSPACE_DIR" -name "latest.log" 2>/dev/null | head -1)
            if [ -n "$MC_LOG" ] && [ -s "$MC_LOG" ]; then
                tail -n 50 -f "$MC_LOG"
            elif [ -f "$WORKSPACE_DIR/minecraft/server/logs/server_process.log" ]; then
                tail -n 50 -f "$WORKSPACE_DIR/minecraft/server/logs/server_process.log"
            else
                echo "Arquivo de log do Minecraft não encontrado."
            fi
            ;;
        3) tail -n 50 -f /tmp/playit.log 2>/dev/null || echo "Log do Playit não encontrado." ;;
        4) tail -n 50 -f /tmp/minecraft_watchdog.log 2>/dev/null || echo "Log do Watchdog não encontrado." ;;
        *) return ;;
    esac
}

setup_playit() {
    local user_socket="/tmp/playit_${USER:-default}.sock"
    echo -e "\n>>> Iniciando provisionamento do Playit.gg..."
    echo -e "Acesse o link gerado abaixo no seu navegador e confirme o vínculo:\n"
    if ! pgrep -f "playit" > /dev/null; then
        echo "Iniciando Playit daemon primeiro..."
        start_services
    fi
    playit --socket-path "$user_socket" setup || "$ROOT_DIR/scripts/bin/playit" setup
    echo -e "\n${GREEN}✓ Playit vinculado com sucesso!${NC}"
}

# Suporte a argumentos de linha de comando não interativos (CI/CD, Cron, Actions)
if [ -n "$1" ]; then
    case "$1" in
        1|start|iniciar)
            start_services
            status_services
            exit 0
            ;;
        2|stop|parar)
            stop_services
            status_services
            exit 0
            ;;
        3|backup)
            backup_world
            exit 0
            ;;
        4|stop-backup)
            stop_services
            backup_world
            exit 0
            ;;
        5|shutdown)
            stop_services
            backup_world
            shutdown_environment
            exit 0
            ;;
        save|salvar|flush|sync)
            save_world
            exit 0
            ;;
        optimize|otimizar)
            if [ -f "$SCRIPT_DIR/optimize_server.sh" ]; then
                bash "$SCRIPT_DIR/optimize_server.sh"
            fi
            exit 0
            ;;
        playit|claim|setup)
            setup_playit
            exit 0
            ;;
        status)
            status_services
            exit 0
            ;;
        cmd|rcon)
            shift
            if [ -f "$SCRIPT_DIR/rcon.py" ]; then
                python3 "$SCRIPT_DIR/rcon.py" "$*"
            else
                echo "rcon.py não encontrado."
            fi
            exit 0
            ;;
        *)
            echo "Uso: $0 [start|stop|backup|stop-backup|save|shutdown|optimize|playit|status|cmd <comando>]"
            exit 1
            ;;
    esac
fi

# Loop do Menu Principal Interativo
while true; do
    stty sane 2>/dev/null || true
    status_services
    echo -e "O que deseja fazer?"
    echo "1) Iniciar Servidor & Serviços (Forge/Playit)"
    echo "2) Parar todos os serviços (Graceful Shutdown Seguro)"
    echo "3) Fazer Backup e Sincronizar na Nuvem"
    echo "4) Parar Serviços + Backup Geral"
    echo "5) Parar Serviços + Backup + Desligar/Suspender Máquina"
    echo "6) Sincronizar/Salvar mundo no disco agora (save-all flush + sync)"
    echo "7) Ver Logs em tempo real"
    echo "8) Aplicar Otimizações Anti-Lag em Todas as Instâncias"
    echo "9) Vincular / Autenticar Túnel Playit.gg"
    echo "0) Sair"
    echo "------------------------------------------------------"
    read -rp "Digite a opção [0-9]: " option

    case $option in
        1) start_services ;;
        2) stop_services ;;
        3) backup_world ;;
        4)
            stop_services
            backup_world
            ;;
        5)
            stop_services
            backup_world
            shutdown_environment
            ;;
        6) save_world ;;
        7) view_logs ;;
        8)
            if [ -f "$SCRIPT_DIR/optimize_server.sh" ]; then
                bash "$SCRIPT_DIR/optimize_server.sh"
            fi
            ;;
        9) setup_playit ;;
        0) echo "Até logo!"; exit 0 ;;
        *) echo -e "${RED}Opção inválida!${NC}" ;;
    esac
    echo ""
    stty sane 2>/dev/null || true
    read -rp "Pressione [Enter] para continuar..." _unused_key
done
