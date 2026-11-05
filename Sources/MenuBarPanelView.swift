import SwiftUI
import AppKit

// MARK: - Vista raiz do painel da barra de menus
struct MenuBarPanelView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if !appState.showSettings {
                Hairline()
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.rLg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.rLg, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
        )
        .preferredColorScheme(.dark)
    }

    private var panelBackground: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blending: .behindWindow)
            Color.black.opacity(0.42)
        }
    }

    // MARK: Header
    private var header: some View {
        HStack(spacing: DS.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [DS.accent, DS.accent.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text("System Sentinel")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.textPrimary)
                Text("Monitor de sistema")
                    .font(.system(size: 10.5))
                    .foregroundColor(DS.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: DS.s2)

            StatusPill(title: alertTitle, color: alertColor)

            audioControlButton

            if appState.showSettings || isShowingAnalysis {
                IconButton(systemName: "chevron.left", help: "Voltar") {
                    appState.showSettings = false
                    appState.analysisResult = nil
                    appState.errorMessage = nil
                }
            } else {
                IconButton(systemName: "gearshape", help: "Configurações") {
                    appState.analysisResult = nil
                    appState.errorMessage = nil
                    appState.showSettings = true
                }
            }

            IconButton(systemName: "xmark", help: "Fechar") {
                appState.isPanelOpen = false
            }
        }
        .padding(.horizontal, DS.s4)
        .padding(.vertical, DS.s3)
    }

    private var audioControlButton: some View {
        Button {
            if appState.isSpeaking {
                appState.stopAudio()
            } else {
                appState.toggleVoiceMute()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(appState.isSpeaking ? DS.bad.opacity(0.18) : (appState.isVoiceMuted ? DS.cardStroke : DS.accent.opacity(0.14)))
                    .frame(width: 26, height: 26)

                Image(systemName: appState.isSpeaking ? "speaker.wave.3.fill" : (appState.isVoiceMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(appState.isSpeaking ? DS.bad : (appState.isVoiceMuted ? DS.textTertiary : DS.accent))
            }
        }
        .buttonStyle(.plain)
        .help(appState.isSpeaking ? "Falando agora — clique para parar o áudio" : (appState.isVoiceMuted ? "Áudio mutado — clique para ativar voz" : "Áudio ativado — clique para mutar"))
    }

    // MARK: Conteúdo
    @ViewBuilder
    private var content: some View {
        // Troca instantânea: transições em ramos condicionais deixavam as duas
        // telas na hierarquia ao mesmo tempo dentro de um NSPanel.
        if appState.showSettings {
            SettingsView(appState: appState)
        } else if isShowingAnalysis {
            AnalysisPanel(appState: appState)
        } else {
            overview
        }
    }

    private var isShowingAnalysis: Bool {
        appState.isAnalyzing || appState.analysisResult != nil || appState.errorMessage != nil
    }

    // MARK: Visão geral
    private var overview: some View {
        VStack(spacing: DS.s3) {
            HStack(spacing: DS.s3) {
                cpuCard
                ramCard
            }
            if !appState.activeIncidents.isEmpty {
                incidentsSection
            }
            processSection
        }
        .padding(.horizontal, DS.s4)
        .padding(.vertical, DS.s3)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: Incidentes Proativos Detectados
    private var incidentsSection: some View {
        VStack(spacing: DS.s2) {
            ForEach(appState.activeIncidents) { inc in
                Card {
                    VStack(alignment: .leading, spacing: DS.s2) {
                        HStack(spacing: 6) {
                            Image(systemName: inc.type.icon)
                                .foregroundColor(DS.bad)
                                .font(.system(size: 13, weight: .bold))
                            Text(inc.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(DS.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(inc.type.rawValue)
                                .font(.system(size: 9.5, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(DS.bad.opacity(0.18)))
                                .foregroundColor(DS.bad)
                        }

                        if let diag = inc.llmDiagnosis {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(DS.accent)
                                    .padding(.top, 2)
                                Text(diag)
                                    .font(.system(size: 11))
                                    .foregroundColor(DS.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)))
                        }

                        HStack(spacing: DS.s2) {
                            Button {
                                Task { await appState.executeIncidentAction(inc) }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: inc.recommendedAction == .kill ? "xmark.circle.fill" : "arrow.clockwise")
                                    Text("\(inc.recommendedAction.rawValue)")
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(inc.recommendedAction == .kill ? DS.bad : DS.accent))
                            }
                            .buttonStyle(.plain)

                            Button("Ignorar") {
                                withAnimation { appState.dismissIncident(inc) }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundColor(DS.textTertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                        }
                    }
                }
            }
        }
    }

    private var cpuCard: some View {
        MetricCard(
            symbol: isCritical ? "exclamationmark.triangle.fill" : "cpu",
            title: "CPU",
            percent: cpu,
            valueText: String(format: "%.0f%%", cpu),
            caption: cpuCaption,
            tint: cpuColor
        )
    }

    private var ramCard: some View {
        MetricCard(
            symbol: "memorychip",
            title: "Memória",
            percent: ram,
            valueText: String(format: "%.0f%%", ram),
            caption: ramCaption,
            tint: ramColor
        )
    }

    // MARK: Seção de processos
    private var processSection: some View {
        VStack(spacing: DS.s2) {
            HStack(spacing: DS.s2) {
                Text("Processos")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.textPrimary)

                Spacer()

                SegmentedPicker(
                    selection: $appState.processSortBy,
                    options: ProcessSortOption.allCases.map { (value: $0, label: $0.rawValue) }
                )
            }

            searchField

            processList
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(DS.textTertiary)

            TextField("Buscar processo ou PID", text: $appState.processSearchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(DS.textPrimary)

            if !appState.processSearchText.isEmpty {
                Button {
                    appState.processSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(DS.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: DS.rSm, style: .continuous)
                .fill(DS.fieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.rSm, style: .continuous)
                .stroke(DS.cardStroke, lineWidth: 0.75)
        )
    }

    @ViewBuilder
    private var processList: some View {
        if appState.processes.isEmpty {
            VStack(spacing: DS.s2) {
                Image(systemName: appState.processSearchText.isEmpty ? "hourglass" : "magnifyingglass")
                    .font(.system(size: 18))
                    .foregroundColor(DS.textTertiary)
                Text(appState.processSearchText.isEmpty ? "Coletando processos…" : "Nenhum processo encontrado")
                    .font(.system(size: 11.5))
                    .foregroundColor(DS.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(appState.processes) { proc in
                        ProcessRow(
                            process: proc,
                            isConfirming: appState.processToKillConfirm?.id == proc.id,
                            onAnalyze: { Task { await appState.analyzeProcess(proc) } },
                            onKillRequest: {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    appState.processToKillConfirm =
                                        appState.processToKillConfirm?.id == proc.id ? nil : proc
                                }
                            },
                            onConfirmKill: {
                                Task {
                                    _ = await appState.killProcess(proc)
                                    appState.processToKillConfirm = nil
                                }
                            },
                            onCancelKill: { appState.processToKillConfirm = nil }
                        )
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: Rodapé
    private var footer: some View {
        HStack(spacing: DS.s2) {
            let orphanCount = appState.orphanProcesses.count

            if orphanCount > 0 {
                Button {
                    Task { _ = await appState.killOrphans() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Limpar \(orphanCount) órfão\(orphanCount == 1 ? "" : "s")")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(DS.warn)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(DS.warn.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .help("Encerra processos sem uso há mais de 24h")
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DS.good.opacity(0.8))
                    Text("Sem processos órfãos")
                        .font(.system(size: 11))
                        .foregroundColor(DS.textTertiary)
                }
            }

            Spacer()

            HStack(spacing: 5) {
                Circle()
                    .fill(DS.good)
                    .frame(width: 6, height: 6)
                Text("Ao vivo")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(DS.textTertiary)
            }
        }
        .padding(.horizontal, DS.s4)
        .padding(.vertical, DS.s3)
    }

    // MARK: Helpers
    private var alertTitle: String {
        appState.metrics == nil ? "—" : appState.alertLevel.title
    }

    private var alertColor: Color {
        guard appState.metrics != nil else { return DS.textTertiary }
        switch appState.alertLevel {
        case .normal: return DS.good
        case .warning: return DS.warn
        case .critical: return DS.bad
        }
    }

    private var cpu: Double { appState.metrics?.cpuUsage ?? 0 }
    private var ram: Double { appState.metrics?.memoryUsagePercent ?? 0 }
    private var isCritical: Bool { appState.metrics?.isCritical == true }

    private var cpuCaption: String {
        let cores = ProcessInfo.processInfo.processorCount
        let load = appState.metrics?.loadAverage ?? 0
        return "\(cores) núcleos · carga \(String(format: "%.2f", load))"
    }

    private var ramCaption: String {
        guard let m = appState.metrics else { return "Coletando…" }
        return String(format: "%.1f / %.0f GB em uso", m.memoryUsedGB, m.memoryTotalGB)
    }

    private var cpuColor: Color {
        if cpu >= appState.settings.cpuCriticalThreshold { return DS.bad }
        if cpu >= appState.settings.cpuWarningThreshold { return DS.warn }
        return DS.good
    }

    private var ramColor: Color {
        if ram >= appState.settings.memoryCriticalThreshold { return DS.bad }
        if ram >= appState.settings.memoryWarningThreshold { return DS.warn }
        return DS.accent
    }
}

// MARK: - Ícone do processo (com marcador neutro quando não há ícone)
struct ProcessIcon: View {
    let process: SystemProcess
    var size: CGFloat = 22

    var body: some View {
        Group {
            if let image = ProcessIconProvider.shared.icon(for: process) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                        .fill(Color.white.opacity(0.09))
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundColor(DS.textTertiary)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Linha de processo
struct ProcessRow: View {
    let process: SystemProcess
    let isConfirming: Bool
    let onAnalyze: () -> Void
    let onKillRequest: () -> Void
    let onConfirmKill: () -> Void
    let onCancelKill: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(spacing: DS.s2) {
            HStack(spacing: DS.s2) {
                ProcessIcon(process: process)

                VStack(alignment: .leading, spacing: 1) {
                    Text(process.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.textPrimary)
                        .lineLimit(1)
                    Text("PID \(process.id)")
                        .font(.system(size: 10))
                        .foregroundColor(DS.textTertiary)
                        .monospacedDigit()
                }

                Spacer(minLength: DS.s2)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(String(format: "%.1f%%", process.cpuUsage))
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundColor(cpuColor)
                        .monospacedDigit()
                    Text(process.formattedMemory)
                        .font(.system(size: 10))
                        .foregroundColor(DS.textTertiary)
                        .monospacedDigit()
                }
                .frame(width: 62, alignment: .trailing)

                HStack(spacing: 4) {
                    Button(action: onAnalyze) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DS.violet)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Analisar com IA")

                    Button(action: onKillRequest) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(hovering || isConfirming ? DS.bad : DS.textTertiary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Encerrar processo")
                }
                .opacity(hovering || isConfirming ? 1 : 0.7)
            }

            if isConfirming {
                HStack(spacing: DS.s2) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(DS.bad)
                    Text("Encerrar “\(process.name)”?")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: DS.s2)
                    Button("Encerrar", action: onConfirmKill)
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(DS.bad))
                    Button("Cancelar", action: onCancelKill)
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: DS.rSm, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.075 : 0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.rSm, style: .continuous)
                .stroke(Color.white.opacity(hovering ? 0.10 : 0.05), lineWidth: 0.6)
        )
        .onHover { hovering = $0 }
    }

    private var cpuColor: Color {
        process.cpuUsage >= 50 ? DS.warn : DS.textSecondary
    }
}

// MARK: - Painel de diagnóstico da IA
struct AnalysisPanel: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s3) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.violet)
                Text("Diagnóstico com IA")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(DS.textPrimary)
                Spacer()
            }

            if appState.isAnalyzing {
                VStack(spacing: DS.s3) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Avaliando o impacto no sistema…")
                        .font(.system(size: 11.5))
                        .foregroundColor(DS.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            } else if let result = appState.analysisResult {
                resultCard(result)
            } else if let error = appState.errorMessage {
                errorCard(error)
            }

            Spacer(minLength: 0)
        }
        .padding(DS.s4)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func resultCard(_ result: LLMAnalysis) -> some View {
        let tint = result.safeToKill ? DS.good : DS.warn

        return VStack(alignment: .leading, spacing: DS.s3) {
            HStack(spacing: 8) {
                Image(systemName: result.safeToKill ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.safeToKill ? "Seguro para encerrar" : "Não recomendado")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(tint)
                    Text("\(result.processName) · PID \(result.processId)")
                        .font(.system(size: 10.5))
                        .foregroundColor(DS.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            Text(result.reason)
                .font(.system(size: 12))
                .foregroundColor(DS.textPrimary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            if let warning = result.warning {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(DS.warn)
                    Text(warning)
                        .font(.system(size: 11))
                        .foregroundColor(DS.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(DS.s2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DS.rSm, style: .continuous)
                        .fill(DS.warn.opacity(0.12))
                )
            }

            if result.safeToKill {
                Button {
                    if let proc = appState.processes.first(where: { $0.id == result.processId }) {
                        Task { _ = await appState.killProcess(proc) }
                    }
                } label: {
                    Label("Encerrar processo", systemImage: "xmark.circle.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: DS.rSm, style: .continuous)
                                .fill(DS.bad)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DS.s3)
        .background(
            RoundedRectangle(cornerRadius: DS.rMd, style: .continuous)
                .fill(tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.rMd, style: .continuous)
                .stroke(tint.opacity(0.28), lineWidth: 1)
        )
    }

    private func errorCard(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13))
                .foregroundColor(DS.bad)
            VStack(alignment: .leading, spacing: 2) {
                Text("Falha na análise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.textPrimary)
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.s3)
        .background(
            RoundedRectangle(cornerRadius: DS.rMd, style: .continuous)
                .fill(DS.bad.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.rMd, style: .continuous)
                .stroke(DS.bad.opacity(0.30), lineWidth: 1)
        )
    }
}
