# System Sentinel 🛡️

[![macOS 13+](https://img.shields.io/badge/platform-macOS%2013%2B-blue.svg)](https://apple.com/macos)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![MCP Compatible](https://img.shields.io/badge/MCP-JSON--RPC%202.0-green.svg)](https://modelcontextprotocol.io)
[![License: MIT](https://img.shields.io/badge/License-MIT-purple.svg)](LICENSE)

System Sentinel é um monitor de integridade de sistema autônomo e de alta precisão para macOS, desenvolvido nativamente em SwiftUI (com suporte a painel de barra de menus e Dynamic Island / notch) e integrado com agentes de IA via MCP (Model Context Protocol).

---

## 🚀 Principais Funcionalidades

### 1. Monitoramento e Telemetria em Tempo Real
- **Métricas do macOS:** CPU geral, detalhamento de RAM (usada, ativa, wired, compressor), uso de Swap, GPU e Load Average de 1, 5 e 15 minutos via `getloadavg`.
- **Top Processos:** Inspeção contínua dos processos mais pesados por CPU ou memória RAM.
- **Detecção de Órfãos:** Varredura de processos zumbis ou desassociados que continuam consumindo ciclos do sistema.

### 2. Guardião Proativo com IA (Diagnóstico e Auto-Recuperação)
- **Crash Loops do Docker:** Identificação automática de contêineres presos em reinicializações infinitas.
- **Detecção de Travamento:** Análise de processos em loop contínuo (ex: `grep` recursivo, scripts acidentais).
- **Proteção Inteligente de Compilações (`Builds`):**
  - Reconhece compiladores e ferramentas de empacotamento (`swift`, `swiftc`, `swift-frontend`, `cargo`, `rustc`, `clang`, `clang++`, `gcc`, `xcodebuild`, `vite`, `esbuild`, `webpack`, `tsc`, `ng`, `nx`, `turbo`, `gradle`, `mvn`, `bun`).
  - Suprime falsos positivos durante compilações ativas: não acusa processos de build como "travados" e não dispara alarme de load average crítico enquanto uma build legítima estiver utilizando os núcleos da CPU.
  - Alternável pela opção `ignoreBuildProcesses` nas configurações.

### 3. Sistema de Notificação por Voz Inteligente (`falar`)
- **Integração com Cartesia Sonic PT-BR:**
  - Sintetizador ultra-rápido (< 80ms) com motor Cartesia Sonic via script canônico `falar` (`/Users/andrerds/bin/falar`), com fallbacks locais (Kokoro) e nativos (`say -v Luciana`).
  - Envio com cabeçalho de contexto obrigatório (`--project SystemSentinel --context "Guardião Proativo"`).
  - Suporte à flag `--interrupt`: corta qualquer áudio anterior para não encavalar falas.
- **Controle Total de Mudo (Mute):**
  - **Interrupção Imediata:** Clicar no botão de áudio enquanto o Sentinel está falando mata o processo de voz no mesmo instante (`killall say`, encerramento de `ffplay`/`afplay`).
  - **Mudo Global:** Alterna o estado de silêncio (`isVoiceMuted`), impedindo qualquer aviso sonoro futuro.
  - **Acesso Rápido:**
    - Botão dinâmico no cabeçalho do painel da barra de menus (`MenuBarPanelView`).
    - Botão dinâmico na Dynamic Island expandida (`ExpandedNotchView`).
    - Menu de clique direito no ícone da barra de menus (`main.swift`).
    - Interruptores nas configurações completas (`SettingsView`).
    - Controle programático via MCP (`set_voice_mute`).

---

## 🤖 Servidor MCP para Outros Agentes e ACP

O System Sentinel expõe um **Servidor MCP nativo (Model Context Protocol)** em conformidade com a especificação JSON-RPC 2.0 (stdio), permitindo que agentes como **Claude Code**, **Antigravity / Gemini**, **Cursor**, **Windsurf** ou ambientes **ACP** interajam diretamente com a máquina e com o Sentinel.

### Arquitetura de Comunicação
```
┌─────────────────────────────────┐
│ Agente IA (Claude / Antigravity)│
└────────────────┬────────────────┘
                 │ stdio (JSON-RPC 2.0)
                 ▼
┌─────────────────────────────────┐
│      systemsentinel-mcp         │ (/Users/andrerds/bin/systemsentinel-mcp)
└────────────────┬────────────────┘
                 │ Unix Domain Socket
                 ▼
┌─────────────────────────────────┐
│   System Sentinel (Swift App)   │ (~/.systemsentinel/sentinel.sock)
│   • EventLogger                 │ (~/.systemsentinel/events.jsonl)
│   • State Persistence           │ (~/.systemsentinel/state.json)
└─────────────────────────────────┘
```

> **Resiliência:** Se o aplicativo gráfico do System Sentinel estiver fechado, o servidor MCP continua funcionando de forma autônoma (fallback coletando métricas nativas do macOS via `sysctl`/`vm_stat` e lendo os logs em disco).

### Ferramentas MCP (`Tools`) Disponíveis

| Ferramenta | Descrição | Parâmetros |
|---|---|---|
| `get_system_metrics` | Retorna métricas em tempo real (CPU, RAM, Swap, Load Average, alerta). | Nenhum |
| `get_active_incidents` | Lista anomalias ativas detectadas pelo Guardião Proativo. | Nenhum |
| `get_system_events` | Retorna os últimos eventos e histórico de incidentes registrados. | `limit` (int, default: 30) |
| `list_processes` | Lista os principais processos em execução com filtros e ordenação. | `sortBy` (cpu/memory/name), `limit` (int), `filter` (string) |
| `resolve_incident` | Resolve ou descarta um incidente ativo, opcionalmente auto-recuperando. | `incidentId` (string, UUID), `executeAction` (bool) |
| `manage_process` | Encerra (`kill`) ou reinicia (`restart`) um processo pelo PID. | `pid` (int), `signal` ("kill" / "restart") |
| `set_voice_mute` | Silencia ou reativa os alertas de voz, ou interrompe áudio imediatamente. | `muted` (bool), `stopAudioNow` (bool) |
| `open_settings` | Abre ou fecha a tela de configurações no painel da barra de menus. | `open` (bool) |
| `speak_message` | Faz o System Sentinel emitir um anúncio por voz via `falar`. | `message` (string, texto em PT-BR) |

### Recursos MCP (`Resources`)

- `systemsentinel://state`: Snapshot JSON completo com métricas, incidentes ativos, status de áudio e top processos.
- `systemsentinel://events`: Stream em JSON Lines contendo os eventos de auditoria e incidentes do Guardião.

---

## ⚙️ Configuração nos Agentes

### Claude Code (`~/.claude/mcp.json`)
```json
{
  "mcpServers": {
    "systemsentinel": {
      "command": "/Users/andrerds/bin/systemsentinel-mcp"
    }
  }
}
```

### Antigravity / Gemini CLI (`~/.gemini/settings.json`)
```json
{
  "mcpServers": {
    "systemsentinel": {
      "command": "/Users/andrerds/bin/systemsentinel-mcp",
      "args": []
    }
  }
}
```

---

## 🔒 Segurança e Privacidade

- **Zero Exposição de Chaves:** Nenhuma chave de API, segredo ou token é embutido no código-fonte.
- **Isolamento Local:** O socket IPC é restrito ao usuário local (`~/.systemsentinel/sentinel.sock` com permissões de usuário macOS).
- **Sem Telemetria Externa Não Autorizada:** Todo o processamento de métricas e auditoria é estritamente local na máquina.

---

## 🛠️ Compilação e Instalação

### Pré-requisitos
- macOS 13.0+ (Ventura ou superior)
- Swift 5.9+ / Xcode Command Line Tools
- Python 3.10+ (para o runner MCP)

### Compilar e Instalar o Aplicativo
Execute o script de build oficial para compilar em modo Release e empacotar para `/Applications`:

```bash
./build_app.sh
```

### Instalar o CLI MCP
O executável já é instalado em `/Users/andrerds/bin/systemsentinel-mcp`. Para recompilar ou atualizar:

```bash
cp bin/systemsentinel-mcp /Users/andrerds/bin/systemsentinel-mcp
chmod +x /Users/andrerds/bin/systemsentinel-mcp
```

### Iniciar o System Sentinel
```bash
open /Applications/SystemSentinel.app
```
O aplicativo será carregado na barra de menus com o ícone de escudo (`shield.lefthalf.filled`).

---

## 📄 Licença

Distribuído sob a licença MIT. Veja `LICENSE` para mais informações.
