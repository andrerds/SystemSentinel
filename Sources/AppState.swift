import SwiftUI
import AppKit
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var metrics: SystemMetrics?
    @Published var processes: [SystemProcess] = []
    @Published var orphanProcesses: [SystemProcess] = []
    @Published var activeIncidents: [SystemIncident] = []
    @Published var settings = AppSettings()
    @Published var llmConnected = false
    @Published var availableModels: [String] = []

    // UI State
    @Published var isExpanded = false
    @Published var isPanelOpen = false
    @Published var openedByClick = false
    @Published var isPinned = false
    @Published var showSettings = false
    @Published var processSearchText = ""
    @Published var processSortBy: ProcessSortOption = .cpu
    @Published var processToKillConfirm: SystemProcess?
    @Published var orphanActionConfirm = false

    // LLM Analysis
    @Published var isAnalyzing = false
    @Published var analysisResult: LLMAnalysis?
    @Published var analyzingProcessId: Int32?
    @Published var errorMessage: String?

    // Audio & Voice State
    @Published var isSpeaking = false

    var isVoiceMuted: Bool {
        get { settings.isVoiceMuted }
        set { setVoiceMuted(newValue) }
    }

    let systemMonitor = SystemMonitor()
    let processManager = ProcessManager()
    var llmService: LLMService
    let proactiveGuardian: ProactiveGuardian
    private var ipcServer: IPCServer?

    private var refreshTask: Task<Void, Never>?
    private var settingsCancellable: AnyCancellable?

    /// Nível de alerta calculado considerando métricas e incidentes ativos do guardião.
    var alertLevel: AlertLevel {
        let maxCpu = processes.first?.cpuUsage ?? 0
        return metrics?.alertLevel(
            for: settings,
            hasActiveIncident: !activeIncidents.isEmpty,
            maxProcessCpu: maxCpu
        ) ?? .normal
    }

    init() {
        let initialSettings = AppSettings()
        let initialLLM = LLMService(
            endpoint: initialSettings.llmEndpoint,
            model: initialSettings.llmModel,
            apiKey: initialSettings.llmApiKey
        )
        self.llmService = initialLLM
        self.proactiveGuardian = ProactiveGuardian(
            processManager: processManager,
            systemMonitor: systemMonitor,
            llmService: initialLLM
        )

        loadSettings()
        self.llmService = LLMService(
            endpoint: settings.llmEndpoint,
            model: settings.llmModel,
            apiKey: settings.llmApiKey
        )

        Task {
            await VoiceService.shared.setMuted(settings.isVoiceMuted)
            await VoiceService.shared.setStateChangeHandler { [weak self] speaking in
                Task { @MainActor [weak self] in
                    self?.isSpeaking = speaking
                }
            }
        }

        self.ipcServer = IPCServer(appState: self)
        self.ipcServer?.start()

        persistSettingsOnChange()
        setupNotificationListener()
        startMonitoring()
        checkLLM()
    }

    func setVoiceMuted(_ muted: Bool) {
        settings.isVoiceMuted = muted
        Task {
            await VoiceService.shared.setMuted(muted)
            await EventLogger.shared.log(
                type: "voice_muted",
                summary: muted ? "Avisos de voz silenciados (mudo)" : "Avisos de voz ativados",
                details: ["isVoiceMuted": "\(muted)"]
            )
        }
        if muted {
            self.isSpeaking = false
        }
        saveSettings()
    }

    func toggleVoiceMute() {
        setVoiceMuted(!isVoiceMuted)
    }

    func stopAudio() {
        Task {
            await VoiceService.shared.stopAudio()
            await EventLogger.shared.log(type: "voice_stopped", summary: "Áudio interrompido manualmente")
        }
        self.isSpeaking = false
    }

    func speakAnnouncement(_ message: String) {
        Task {
            await VoiceService.shared.speak(message, category: "manual", force: true)
        }
    }

    private func setupNotificationListener() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SystemSentinelNotificationAction"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let self = self,
                      let info = note.userInfo,
                      let uuid = info["incidentId"] as? UUID,
                      let action = info["action"] as? String else { return }

                if let inc = self.activeIncidents.first(where: { $0.id == uuid }) {
                    if action == "ACTION_KILL" {
                        var mod = inc
                        mod.recommendedAction = .kill
                        await self.executeIncidentAction(mod)
                    } else if action == "ACTION_RESTART" {
                        var mod = inc
                        mod.recommendedAction = .restart
                        await self.executeIncidentAction(mod)
                    } else {
                        self.dismissIncident(inc)
                    }
                }
            }
        }
    }

    /// Mantém as preferências salvas em disco sempre que algo muda na UI.
    private func persistSettingsOnChange() {
        settingsCancellable = $settings
            .dropFirst()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.saveSettings() }
    }

    func startMonitoring() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func refresh() async {
        let m = await systemMonitor.getMetrics()
        self.metrics = m

        // Coleta processos caso painel esteja aberto OU haja alerta ou anomalia
        if isExpanded || isPanelOpen || alertLevel != .normal || settings.enableProactiveMonitoring {
            await loadProcessData()
        }

        // Executa ronda proativa do guardião
        if settings.enableProactiveMonitoring {
            let newIncidents = await proactiveGuardian.checkAnomalies(settings: settings, currentMetrics: m)
            for inc in newIncidents {
                if !activeIncidents.contains(where: { $0.id == inc.id || ($0.pid != nil && $0.pid == inc.pid) }) {
                    self.activeIncidents.insert(inc, at: 0)

                    // Se auto-heal de processos seguros estiver ativo
                    if settings.autoHealSafeAnomalies && inc.type == .runawayCommand {
                        Task { await self.executeIncidentAction(inc) }
                    }
                }
            }

            // Remove incidentes resolvidos (processos que não existem mais ou têm > 3 minutos)
            let now = Date()
            self.activeIncidents.removeAll { inc in
                if now.timeIntervalSince(inc.detectedAt) > 180 { return true }
                if let pid = inc.pid {
                    return kill(pid, 0) != 0 // processo já morreu
                }
                return false
            }
            if self.activeIncidents.count > 5 {
                self.activeIncidents = Array(self.activeIncidents.prefix(5))
            }
        }

        // Exporta telemetria em tempo real para o MyJarvis
        exportTelemetryToJarvis()

        // Atualiza estado vivo para agentes e MCP
        Task {
            await EventLogger.shared.updateSystemState(
                metrics: m,
                activeIncidents: activeIncidents,
                isVoiceMuted: isVoiceMuted,
                isSpeaking: isSpeaking,
                topProcesses: processes
            )
        }
    }

    /// Grava telemetria viva para o Cockpit do MyJarvis consumir
    func exportTelemetryToJarvis() {
        guard let m = metrics else { return }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let jarvisDir = base?.appendingPathComponent("com.jarvis.myjarvis") else { return }
        try? FileManager.default.createDirectory(at: jarvisDir, withIntermediateDirectories: true)

        let file = jarvisDir.appendingPathComponent("sentinel-telemetry.json")
        let top = processes.first

        let payload: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970,
            "cpuUsage": m.cpuUsage,
            "memoryUsedGB": m.memoryUsedGB,
            "memoryTotalGB": m.memoryTotalGB,
            "memoryPercent": m.memoryUsagePercent,
            "loadAverage": m.loadAverage,
            "topProcess": top?.name ?? "Nenhum",
            "topProcessCpu": top?.cpuUsage ?? 0.0,
            "status": alertLevel.title,
            "activeIncidents": activeIncidents.map { inc in
                [
                    "id": inc.id.uuidString,
                    "type": inc.type.rawValue,
                    "title": inc.title,
                    "description": inc.description,
                    "action": inc.recommendedAction.rawValue,
                    "diagnosis": inc.llmDiagnosis ?? ""
                ]
            }
        ]

        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) {
            try? data.write(to: file, options: [.atomic])
        }
    }

    /// Carrega processos e órfãos respeitando a busca e a ordenação atuais.
    func loadProcessData() async {
        let p = await processManager.getProcesses(sortBy: processSortBy, filter: processSearchText)
        let orphans = await processManager.getOrphanProcesses()
        self.processes = p
        self.orphanProcesses = orphans
    }

    func executeIncidentAction(_ incident: SystemIncident) async {
        switch incident.recommendedAction {
        case .kill:
            if let pid = incident.pid {
                try? await processManager.killProcess(pid: pid)
            }
        case .restart:
            if let pid = incident.pid {
                try? await processManager.restartProcess(pid: pid)
            } else if let container = incident.containerName {
                _ = await processManager.restartDockerContainer(name: container)
            }
        case .stopDocker:
            if let container = incident.containerName {
                _ = await processManager.stopDockerContainer(name: container)
            }
        case .ignore:
            break
        }

        Task {
            await EventLogger.shared.log(
                type: "process_action",
                summary: "Ação executada: \(incident.recommendedAction.rawValue) em \(incident.title)",
                details: [
                    "incidentId": incident.id.uuidString,
                    "action": incident.recommendedAction.rawValue,
                    "pid": incident.pid.map { "\($0)" } ?? "",
                    "container": incident.containerName ?? ""
                ]
            )
        }

        dismissIncident(incident)
        await refresh()
    }

    func dismissIncident(_ incident: SystemIncident) {
        activeIncidents.removeAll { $0.id == incident.id }
        Task {
            await proactiveGuardian.resolveKey(for: incident)
        }
    }

    func setExpanded(_ expanded: Bool, byClick: Bool = false) {
        guard isExpanded != expanded else {
            if expanded && byClick {
                openedByClick = true
            }
            return
        }
        if expanded {
            openedByClick = byClick
        } else {
            openedByClick = false
        }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            self.isExpanded = expanded
        }
        if expanded {
            Task { await loadProcessData() }
        }
    }

    func toggleExpanded() {
        setExpanded(!isExpanded, byClick: true)
    }

    // MARK: - LLM & Actions
    func checkLLM() {
        Task {
            let ok = await llmService.checkConnection()
            let models = await llmService.fetchAvailableModels()
            self.llmConnected = ok
            self.availableModels = models
            if !models.isEmpty && !models.contains(settings.llmModel) {
                if let first = models.first {
                    settings.llmModel = first
                    await llmService.setModel(first)
                }
            }
        }
    }

    func updateLLMEndpoint(_ endpoint: String, model: String, apiKey: String = "") {
        settings.llmEndpoint = endpoint
        settings.llmModel = model
        settings.llmApiKey = apiKey
        Task {
            await llmService.setEndpoint(endpoint)
            await llmService.setModel(model)
            await llmService.setApiKey(apiKey)
            checkLLM()
        }
        saveSettings()
    }

    func analyzeProcess(_ process: SystemProcess) async {
        isAnalyzing = true
        analyzingProcessId = process.id
        analysisResult = nil
        errorMessage = nil
        do {
            let result = try await llmService.analyzeProcess(process)
            self.analysisResult = result
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isAnalyzing = false
    }

    func killProcess(_ process: SystemProcess) async -> Bool {
        do {
            try await processManager.killProcess(pid: process.id)
            if analysisResult?.processId == process.id {
                analysisResult = nil
            }
            await refresh()
            return true
        } catch {
            errorMessage = "Falha ao encerrar PID \(process.id)"
            return false
        }
    }

    func killOrphans() async -> Int {
        let orphans = await processManager.getOrphanProcesses()
        let failed = await processManager.killProcesses(pids: orphans.map { $0.id })
        await refresh()
        return orphans.count - failed.count
    }

    // MARK: - Persistence
    func loadSettings() {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let url = base.appendingPathComponent("SystemSentinel/settings.json")
        guard let data = try? Data(contentsOf: url),
              let loaded = try? JSONDecoder().decode(AppSettings.self, from: data) else { return }
        settings = loaded
    }

    func saveSettings() {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let dir = base.appendingPathComponent("SystemSentinel")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(settings) {
            try? data.write(to: dir.appendingPathComponent("settings.json"))
        }
    }
}
