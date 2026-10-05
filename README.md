# ⛏️ Minecraft Server Template & Manager

Modelo pronto para instalação, gerenciamento e automação de servidores de Minecraft com **Crafty Controller 4**, túnel **Playit.gg** e rotina de backup em nuvem via **rclone**.

Compatível com **GitHub Codespaces**, **VPS (Ubuntu/Debian)** e **WSL / Linux Local**.

---

## 📦 Estrutura do Repositório

```text
minecraft_server/
├── setup.sh                  # Atalho raiz para scripts/setup.sh
├── manager.sh                # Atalho raiz para scripts/manager.sh
├── .gitignore                # Regras de exclusão para mundos pesados, logs e binários
├── config/
│   ├── config.env.example    # Modelo de variáveis de configuração do ambiente
│   └── templates/            # Templates padrão (server.properties, eula.txt)
├── scripts/
│   ├── setup.sh              # Script de instalação e bootstrap automatizado
│   ├── manager.sh            # Menu central para iniciar, parar e gerenciar
│   └── optimize_server.sh    # Script de otimização anti-lag e TPS para instâncias
├── auto_schedule.sh          # Controlador e keepalive/heartbeat para Codespaces
├── .github/
│   └── workflows/
│       └── scheduler.yml     # Fluxo de agendamento automático via GitHub Actions
├── deployments/
│   └── systemd/              # Modelos de serviços systemd para VPS/Linux
│       ├── crafty.service
│       └── playit.service
└── docs/
    ├── ARCHITECTURE.md       # Visão geral da arquitetura e portas
    └── BACKUP_GUIDE.md       # Guia passo a passo de backup com Google Drive
```

---

## 🚀 Instalação e Preparação do StoneBlock (Forge 1.12.2)

### 1. Importar Mods, Configs e Save do Launcher local:
Se você já tem a instância do modpack no SKLauncher ou na sua máquina:
```bash
./scripts/import_stoneblock.sh
```
*(Ele copia automaticamente `mods/`, `config/`, `scripts/` e o seu save `New World` para `minecraft/server/world`, além de instalar o Forge 1.12.2 Server).*

### 2. Configurar Dependências do Ambiente (Setup):
```bash
./setup.sh
```
O `setup.sh` instalará:
1. **Java 8 OpenJDK** (obrigatório para StoneBlock / Forge 1.12.2).
2. **Playit.gg CLI** para expor IP público no GitHub Codespaces.
3. Dependências do Python e RCON para auto-save contínuo e graceful shutdown.

---

## 🎮 Gerenciamento do Servidor (`manager.sh`)

Para abrir o menu interativo:

```bash
./manager.sh
```

### Funcionalidades do Menu:
- **1) Iniciar Servidor & Serviços:** Inicializa o túnel Playit e o painel Web do Crafty na porta `8443`.
- **2) Parar todos os serviços:** Finaliza de forma limpa processos do Java, Crafty e Playit, liberando as portas.
- **3) Fazer Backup e Sincronizar na Nuvem:** Compacta os dados do mundo e sincroniza com o Google Drive / nuvem via `rclone`.
- **4) Parar Serviços + Backup Geral:** Ideal antes de manutenções.
- **5) Parar Serviços + Backup + Desligar/Suspender Máquina:** Encerra serviços, envia backup para a nuvem e suspende o Codespace / máquina para economizar recursos.
- **6) Ver Logs em tempo real:** Acompanhe os logs do Crafty, do Minecraft e do Playit.
- **7) Aplicar Otimizações Anti-Lag:** Aplica parâmetros de alta performance no `server.properties` (view-distance, simulation-distance, async sync, etc.).

---

## 📖 Mais Informações

- Consulte [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) para detalhes técnicos da infraestrutura.
- Consulte [docs/PERFORMANCE_GUIDE.md](docs/PERFORMANCE_GUIDE.md) para o guia de otimização, flags de JVM e pré-geração de chunks.
- Consulte [docs/BACKUP_GUIDE.md](docs/BACKUP_GUIDE.md) para configurar o Google Drive com rclone.