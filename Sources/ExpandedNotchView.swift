import SwiftUI
import AppKit

// MARK: - Expanded Notch View (Atoll Horizontal Widescreen Shelf)
struct ExpandedNotchView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header Bar
            headerBar

            if appState.showSettings {
                SettingsView(appState: appState)
                    .transition(.opacity)
            } else if appState.isAnalyzing || appState.analysisResult != nil || appState.errorMessage != nil {
                aiAnalysisDrawer
                    .transition(.opacity)
            } else {
                // Two-column layout matching Atoll's horizontal shelf
                HStack(alignment: .top, spacing: 12) {
                    // Left Column: Telemetry Cards (CPU & RAM)
                    VStack(spacing: 8) {
                        cpuCard
                        ramCard
                    }
                    .frame(width: 255)

                    // Right Column: Process Guardian Inspector
                    VStack(spacing: 6) {
                        processControlBar
                        processListView
                    }
                    .frame(maxWidth: .infinity)
                }

                // Footer Bar
                footerBar
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundColor(.white)
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.checkerboard")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)

            Text("System Sentinel")
                .font(.system(size: 12, weight: .bold))

            // System Health Pill
            healthStatusBadge

            Spacer()

            // Ollama Indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(appState.llmConnected ? Color.green : Color.red.opacity(0.8))
                    .frame(width: 5, height: 5)
                Text(appState.llmConnected ? "LLM" : "Offline")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.08))
            .cornerRadius(8)

            // Pin Button
            Button {
                appState.isPinned.toggle()
            } label: {
                Image(systemName: appState.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(appState.isPinned ? .orange : .white.opacity(0.6))
                    .padding(4)
                    .background(appState.isPinned ? Color.orange.opacity(0.18) : Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(appState.isPinned ? "Desafixar Ilha" : "Fixar Ilha Aberta")

            // Audio Mute / Stop Button
            Button {
                if appState.isSpeaking {
                    appState.stopAudio()
                } else {
                    appState.toggleVoiceMute()
                }
            } label: {
                Image(systemName: appState.isSpeaking ? "speaker.wave.3.fill" : (appState.isVoiceMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(appState.isSpeaking ? .red : (appState.isVoiceMuted ? .white.opacity(0.4) : .blue))
                    .padding(4)
                    .background(appState.isSpeaking ? Color.red.opacity(0.2) : Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(appState.isSpeaking ? "Parar áudio imediatamente" : (appState.isVoiceMuted ? "Reativar voz" : "Mutar voz"))

            // Settings Toggle Button
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    appState.showSettings.toggle()
                }
            } label: {
                Image(systemName: appState.showSettings ? "xmark" : "gearshape")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(4)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Configurações")

            // Collapse Button
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    appState.isExpanded = false
                }
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(4)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Recolher")
        }
    }

    private var healthStatusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(appState.metrics?.statusColor ?? .green)
                .frame(width: 5, height: 5)
            Text(appState.metrics?.statusTitle ?? "Normal")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(appState.metrics?.statusColor ?? .green)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background((appState.metrics?.statusColor ?? .green).opacity(0.12))
        .cornerRadius(6)
    }

    // MARK: - CPU Card
    private var cpuCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("CPU", systemImage: "cpu")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.75))
                Spacer()
                Text(String(format: "%.1f%%", appState.metrics?.cpuUsage ?? 0))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(cpuMetricColor)
            }

            ProgressView(value: min(appState.metrics?.cpuUsage ?? 0, 100), total: 100)
                .tint(cpuMetricColor)
                .scaleEffect(x: 1, y: 0.8)

            HStack {
                Text("Núcleos Ativos")
                    .font(.system(size: 8.5))
                    .foregroundColor(.white.opacity(0.45))
                Spacer()
                Text(String(format: "%.0f%% Carga", appState.metrics?.cpuUsage ?? 0))
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.06))
        .cornerRadius(9)
    }

    // MARK: - RAM Card
    private var ramCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("RAM", systemImage: "memorychip")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.75))
                Spacer()
                Text(String(format: "%.1f%%", appState.metrics?.memoryUsagePercent ?? 0))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(ramMetricColor)
            }

            ProgressView(value: min(appState.metrics?.memoryUsagePercent ?? 0, 100), total: 100)
                .tint(ramMetricColor)
                .scaleEffect(x: 1, y: 0.8)

            HStack(spacing: 4) {
                Text(String(format: "%.1f / %.0f GB", appState.metrics?.memoryUsedGB ?? 0, appState.metrics?.memoryTotalGB ?? 0))
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                if (appState.metrics?.swapUsedGB ?? 0) > 0 {
                    Text(String(format: "Swap: %.1fG", appState.metrics?.swapUsedGB ?? 0))
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundColor(.orange)
                } else {
                    Text(String(format: "Presa: %.1fG", appState.metrics?.memoryWiredGB ?? 0))
                        .font(.system(size: 8.5))
                        .foregroundColor(.white.opacity(0.45))
                }
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.06))
        .cornerRadius(9)
    }

    // MARK: - Process Control Bar
    private var processControlBar: some View {
        HStack(spacing: 6) {
            // Search Input
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.5))

                TextField("Filtrar processo...", text: $appState.processSearchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(.white)

                if !appState.processSearchText.isEmpty {
                    Button {
                        appState.processSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.07))
            .cornerRadius(6)

            // Sort Picker
            Picker("", selection: $appState.processSortBy) {
                ForEach(ProcessSortOption.allCases) { opt in
                    Text(opt.rawValue).tag(opt)
                }
            }
            .pickerStyle(.segmented)
            .colorScheme(.dark)
            .frame(width: 130)
        }
    }

    // MARK: - Process List
    private var processListView: some View {
        VStack(spacing: 3) {
            if appState.processes.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.3))
                    Text("Nenhum processo")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(appState.processes.prefix(4)) { proc in
                    ProcessRowCard(
                        process: proc,
                        isConfirmingKill: appState.processToKillConfirm?.id == proc.id,
                        onAnalyze: {
                            Task { await appState.analyzeProcess(proc) }
                        },
                        onKillRequest: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                if appState.processToKillConfirm?.id == proc.id {
                                    appState.processToKillConfirm = nil
                                } else {
                                    appState.processToKillConfirm = proc
                                }
                            }
                        },
                        onConfirmKill: {
                            Task {
                                _ = await appState.killProcess(proc)
                                appState.processToKillConfirm = nil
                            }
                        },
                        onCancelKill: {
                            appState.processToKillConfirm = nil
                        }
                    )
                }
            }
        }
        .frame(height: 110, alignment: .top)
    }

    // MARK: - Inline AI Analysis Drawer
    private var aiAnalysisDrawer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Diagnóstico Inteligente (Ollama)", systemImage: "brain.head.profile")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.purple)

                Spacer()

                Button {
                    appState.analysisResult = nil
                    appState.errorMessage = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }

            if appState.isAnalyzing {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.65)
                    Text("Avaliando impacto no sistema...")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .center)
            } else if let result = appState.analysisResult {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Image(systemName: result.safeToKill ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(result.safeToKill ? .green : .orange)
                        Text(result.safeToKill ? "Seguro para Encerrar" : "Atenção: Não Recomendado")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(result.safeToKill ? .green : .orange)
                        
                        Spacer()
                        
                        Text(result.processName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                    }

                    Text(result.reason)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(3)

                    if let warning = result.warning {
                        Text(warning)
                            .font(.system(size: 8.5))
                            .foregroundColor(.orange)
                            .padding(3)
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(4)
                    }

                    HStack {
                        Spacer()
                        if result.safeToKill {
                            Button {
                                if let proc = appState.processes.first(where: { $0.id == result.processId }) {
                                    Task { _ = await appState.killProcess(proc) }
                                }
                            } label: {
                                Label("Encerrar Processo", systemImage: "xmark.circle.fill")
                                    .font(.system(size: 9.5, weight: .bold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                    }
                }
            } else if let err = appState.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundColor(.red)
                    Text(err)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }
                .padding(.vertical, 10)
            }
        }
        .padding(8)
        .background(Color.purple.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.purple.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(8)
    }

    // MARK: - Footer Bar
    private var footerBar: some View {
        HStack {
            let orphanCount = appState.orphanProcesses.count
            if orphanCount > 0 {
                Button {
                    Task { _ = await appState.killOrphans() }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                        Text("Limpar \(orphanCount) Órfãos")
                            .font(.system(size: 9, weight: .semibold))
                    }
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .help("Finalizar processos sem uso há mais de 24h")
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 9))
                        .foregroundColor(.green.opacity(0.7))
                    Text("Sem processos órfãos")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            Spacer()

            Text("Monitoramento Mach Kernel ativo")
                .font(.system(size: 8.5))
                .foregroundColor(.white.opacity(0.35))
        }
    }

    // MARK: - Helpers
    private var cpuMetricColor: Color {
        let v = appState.metrics?.cpuUsage ?? 0
        if v >= appState.settings.cpuCriticalThreshold { return Color(red: 1.0, green: 0.27, blue: 0.23) }
        if v >= appState.settings.cpuWarningThreshold { return Color(red: 1.0, green: 0.62, blue: 0.04) }
        return Color(red: 0.19, green: 0.82, blue: 0.35)
    }

    private var ramMetricColor: Color {
        let v = appState.metrics?.memoryUsagePercent ?? 0
        if v >= appState.settings.memoryCriticalThreshold { return Color(red: 1.0, green: 0.27, blue: 0.23) }
        if v >= appState.settings.memoryWarningThreshold { return Color(red: 1.0, green: 0.62, blue: 0.04) }
        return Color(red: 0.04, green: 0.52, blue: 1.0)
    }
}

// MARK: - Process Row Card
struct ProcessRowCard: View {
    let process: SystemProcess
    let isConfirmingKill: Bool
    let onAnalyze: () -> Void
    let onKillRequest: () -> Void
    let onConfirmKill: () -> Void
    let onCancelKill: () -> Void

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                // Ícone real do app (com marcador neutro de fallback)
                ProcessIcon(process: process, size: 16)

                // Process Name & PID
                VStack(alignment: .leading, spacing: 1) {
                    Text(process.name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text("PID \(process.id)")
                        .font(.system(size: 8.5))
                        .foregroundColor(.white.opacity(0.4))
                }

                Spacer()

                // CPU Badge
                Text(String(format: "%.1f%%", process.cpuUsage))
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundColor(process.cpuUsage >= 50 ? .orange : .white.opacity(0.8))
                    .frame(width: 38, alignment: .trailing)

                // RAM Badge
                Text(process.formattedMemory)
                    .font(.system(size: 9.5, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 44, alignment: .trailing)

                // AI Brain Action
                Button {
                    onAnalyze()
                } label: {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 10))
                        .foregroundColor(.purple.opacity(0.9))
                        .padding(3)
                }
                .buttonStyle(.plain)
                .help("Analisar processo com IA")

                // Kill Button
                Button {
                    onKillRequest()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.red.opacity(0.7))
                        .padding(3)
                }
                .buttonStyle(.plain)
                .help("Encerrar processo")
            }

            // Inline Soft Confirmation
            if isConfirmingKill {
                HStack(spacing: 6) {
                    Text("Encerrar?")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.red)

                    Button("Sim") {
                        onConfirmKill()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .font(.system(size: 8.5, weight: .bold))

                    Button("Não") {
                        onCancelKill()
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 8.5))
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.04))
        .cornerRadius(6)
    }
}
