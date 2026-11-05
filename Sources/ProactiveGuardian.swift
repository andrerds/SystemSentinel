import Foundation

// MARK: - Guardião Proativo (Sentinela Autônomo com IA)
actor ProactiveGuardian {
    private var isRunning = false
    private var highCpuTracker: [Int32: Int] = [:] // PID -> ciclos consecutivos em alta CPU
    private var recentIncidentKeys: [String: Date] = [:]
    private var lastDockerCheck = Date.distantPast

    private let processManager: ProcessManager
    private let systemMonitor: SystemMonitor
    private let llmService: LLMService

    init(processManager: ProcessManager, systemMonitor: SystemMonitor, llmService: LLMService) {
        self.processManager = processManager
        self.systemMonitor = systemMonitor
        self.llmService = llmService
    }

    func checkAnomalies(settings: AppSettings, currentMetrics: SystemMetrics?) async -> [SystemIncident] {
        guard settings.enableProactiveMonitoring else { return [] }
        var detected: [SystemIncident] = []
        let now = Date()

        // Limpa chaves de incidentes antigos (> 5 minutos)
        recentIncidentKeys = recentIncidentKeys.filter { now.timeIntervalSince($0.value) < 300 }

        // 1. Docker: Verifica contêineres em loop de reinício (a cada 10s)
        if now.timeIntervalSince(lastDockerCheck) >= 10 {
            lastDockerCheck = now
            if let dockerIncident = await checkDockerCrashLoops() {
                detected.append(dockerIncident)
            }
        }

        // Coleta processos ativos para checagem de sobrecarga e anomalias
        let topProcs = await processManager.getProcesses(sortBy: .cpu, limit: 15)
        let isBuilding = settings.ignoreBuildProcesses && topProcs.contains(where: { $0.isBuildTool && $0.cpuUsage > 25 })

        // 2. Load Average crítico (ignorado se for compilação legítima ativa)
        if let metrics = currentMetrics, metrics.loadAverage >= settings.loadAverageThreshold, !isBuilding {
            let key = "load-high"
            if recentIncidentKeys[key] == nil {
                recentIncidentKeys[key] = now
                let incident = SystemIncident(
                    id: UUID(),
                    type: .highLoad,
                    title: "Load Average Crítico (\(String(format: "%.1f", metrics.loadAverage)))",
                    description: "O agendador do macOS está saturado com processos enfileirados aguardando CPU ou disco. Limite: \(String(format: "%.1f", settings.loadAverageThreshold)).",
                    pid: nil,
                    containerName: nil,
                    llmDiagnosis: nil,
                    recommendedAction: .kill,
                    detectedAt: now,
                    isResolved: false
                )
                detected.append(incident)
            }
        }

        // 3. Processos individuais travados em alta CPU
        for p in topProcs where p.cpuUsage >= settings.singleProcessCpuThreshold {
            // Ignora processos de build / compilação / empacotamento quando habilitado
            if settings.ignoreBuildProcesses && p.isBuildTool {
                continue
            }

            let count = (highCpuTracker[p.id] ?? 0) + 1
            highCpuTracker[p.id] = count

            // Pede 2 ciclos consecutivos (~4 a 8s) para evitar falsos positivos de picos rápidos
            if count >= 2 {
                let key = "proc-\(p.id)"
                if recentIncidentKeys[key] == nil {
                    recentIncidentKeys[key] = now
                    let nameLower = p.name.lowercased()
                    
                    // Whitelist de processos vitais que NUNCA devem ser mortos automaticamente nem alertados como travados
                    let isProtected = nameLower.contains("antigravity") ||
                                      nameLower == "agy" ||
                                      nameLower.contains("terminal") ||
                                      nameLower.contains("iterm") ||
                                      nameLower.contains("code") ||
                                      nameLower.contains("orbstack") ||
                                      nameLower.contains("claude") ||
                                      nameLower.contains("jarvis") ||
                                      nameLower.contains("sentinel")
                    
                    if isProtected {
                        continue
                    }
                    
                    let isEphemeralSearch = nameLower.contains("grep") || nameLower.contains("find")
                    
                    // PREFERÊNCIA ABSOLUTA: REINICIAR em vez de encerrar!
                    // Só encerra se for busca descartável acidental (grep/find). Todo o resto = REINICIAR!
                    let recAction: AnomalyAction = isEphemeralSearch ? .kill : .restart
                    let incidentType: AnomalyType = isEphemeralSearch ? .runawayCommand : .cpuSpike

                    let incident = SystemIncident(
                        id: UUID(),
                        type: incidentType,
                        title: "\(p.name) travado em \(String(format: "%.0f", p.cpuUsage))% CPU",
                        description: "Processo PID \(p.id) (\(p.name)) está consumindo \(String(format: "%.1f", p.cpuUsage))% de CPU continuamente.",
                        pid: p.id,
                        containerName: nil,
                        llmDiagnosis: nil,
                        recommendedAction: recAction,
                        detectedAt: now,
                        isResolved: false
                    )
                    detected.append(incident)
                }
            }
        }

        // Limpa o contador para processos que normalizaram
        let currentPids = Set(topProcs.map { $0.id })
        for (pid, _) in highCpuTracker where !currentPids.contains(pid) {
            highCpuTracker.removeValue(forKey: pid)
        }

        // 4. Enriquecimento autônomo com IA (ou Heurística)
        var enriched: [SystemIncident] = []
        for var inc in detected {
            let proc = topProcs.first(where: { $0.id == inc.pid })
            let diag = await llmService.diagnoseIncident(incident: inc, process: proc)
            inc.llmDiagnosis = diag.reason
            inc.recommendedAction = diag.recommendedAction
            enriched.append(inc)

            // Avisos proativos
            if settings.proactiveVoiceAlerts && !settings.isVoiceMuted {
                let voiceMsg = "Atenção: \(inc.title). Recomendado \(inc.recommendedAction.rawValue)."
                await VoiceService.shared.speak(voiceMsg, category: inc.type.rawValue)
                await EventLogger.shared.log(
                    type: "voice_alert",
                    summary: voiceMsg,
                    details: ["incidentId": inc.id.uuidString, "type": inc.type.rawValue]
                )
            }

            await EventLogger.shared.log(
                type: "incident_detected",
                summary: inc.title,
                details: [
                    "incidentId": inc.id.uuidString,
                    "type": inc.type.rawValue,
                    "recommendedAction": inc.recommendedAction.rawValue,
                    "pid": inc.pid.map { "\($0)" } ?? "",
                    "container": inc.containerName ?? ""
                ]
            )

            if settings.proactiveNotifications {
                await NotificationService.shared.postAnomalyNotification(incident: inc)
            }
        }

        return enriched
    }

    private func checkDockerCrashLoops() async -> SystemIncident? {
        let paths = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", "/usr/bin/docker"]
        guard let dockerPath = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }

        let task = Process()
        task.launchPath = dockerPath
        task.arguments = ["ps", "-a", "--filter", "status=restarting", "--format", "{{.ID}}\t{{.Names}}\t{{.Status}}"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8), !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            let lines = output.split(separator: "\n")
            if let first = lines.first {
                let parts = first.split(separator: "\t")
                if parts.count >= 2 {
                    let name = String(parts[1])
                    let status = parts.count > 2 ? String(parts[2]) : "Restarting"
                    let key = "docker-\(name)"
                    if recentIncidentKeys[key] != nil { return nil }
                    recentIncidentKeys[key] = Date()

                    return SystemIncident(
                        id: UUID(),
                        type: .dockerCrashLoop,
                        title: "Contêiner Docker '\(name)' em Crash Loop",
                        description: "Status: \(status). O contêiner está reiniciando repetidamente e sobrecarregando a máquina.",
                        pid: nil,
                        containerName: name,
                        llmDiagnosis: "O contêiner '\(name)' está em loop contínuo de falhas. Verifique dependências ou reinicie o serviço.",
                        recommendedAction: .restart,
                        detectedAt: Date(),
                        isResolved: false
                    )
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    func resolveKey(for incident: SystemIncident) {
        if let pid = incident.pid {
            recentIncidentKeys.removeValue(forKey: "proc-\(pid)")
            highCpuTracker.removeValue(forKey: pid)
        }
        if let container = incident.containerName {
            recentIncidentKeys.removeValue(forKey: "docker-\(container)")
        }
        if incident.type == .highLoad {
            recentIncidentKeys.removeValue(forKey: "load-high")
        }

        Task {
            await EventLogger.shared.log(
                type: "incident_resolved",
                summary: "Resolvido: \(incident.title)",
                details: [
                    "incidentId": incident.id.uuidString,
                    "action": incident.recommendedAction.rawValue
                ]
            )
        }
    }
}
