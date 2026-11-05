import Foundation
import Darwin

// MARK: - IPC Server over Unix Domain Socket
@MainActor
final class IPCServer {
    private let socketPath: String
    private var serverSource: DispatchSourceRead?
    private var serverFd: Int32 = -1
    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".systemsentinel", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.socketPath = dir.appendingPathComponent("sentinel.sock").path
    }

    func start() {
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        _ = socketPath.withCString { cstr in
            strncpy(&addr.sun_path.0, cstr, maxLen - 1)
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, addrLen)
            }
        }

        guard bindResult == 0 else {
            Darwin.close(fd)
            return
        }

        guard Darwin.listen(fd, 8) == 0 else {
            Darwin.close(fd)
            return
        }

        self.serverFd = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue.global(qos: .utility))
        source.setEventHandler { [weak self] in
            var clientAddr = sockaddr_un()
            var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            let clientFd = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.accept(fd, $0, &clientLen)
                }
            }
            guard clientFd >= 0 else { return }

            Task { @MainActor [weak self] in
                self?.handleClient(fd: clientFd)
            }
        }

        source.setCancelHandler {
            Darwin.close(fd)
        }

        source.resume()
        self.serverSource = source
    }

    func stop() {
        serverSource?.cancel()
        serverSource = nil
        unlink(socketPath)
    }

    private func handleClient(fd: Int32) {
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        guard let data = handle.availableData as Data?, !data.isEmpty else {
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = json["action"] as? String else {
            let err: [String: Any] = ["status": "error", "message": "JSON inválido ou campo 'action' ausente"]
            sendResponse(err, handle: handle)
            return
        }

        Task { @MainActor in
            let response = await self.processAction(action, payload: json)
            self.sendResponse(response, handle: handle)
        }
    }

    private func processAction(_ action: String, payload: [String: Any]) async -> [String: Any] {
        guard let appState = self.appState else {
            return ["status": "error", "message": "AppState indisponível"]
        }

        switch action {
        case "ping":
            return ["status": "ok", "app": "SystemSentinel", "version": "1.0.0"]

        case "get_state":
            var res: [String: Any] = [
                "status": "ok",
                "isVoiceMuted": appState.isVoiceMuted,
                "isSpeaking": appState.isSpeaking,
                "showSettings": appState.showSettings,
                "isPanelOpen": appState.isPanelOpen,
                "activeIncidentCount": appState.activeIncidents.count,
                "activeIncidents": appState.activeIncidents.map { inc in
                    [
                        "id": inc.id.uuidString,
                        "type": inc.type.rawValue,
                        "title": inc.title,
                        "description": inc.description,
                        "recommendedAction": inc.recommendedAction.rawValue,
                        "pid": inc.pid as Any,
                        "container": inc.containerName as Any
                    ]
                }
            ]
            if let m = appState.metrics {
                res["metrics"] = [
                    "cpuUsage": m.cpuUsage,
                    "memoryUsagePercent": m.memoryUsagePercent,
                    "memoryUsedGB": m.memoryUsedGB,
                    "memoryTotalGB": m.memoryTotalGB,
                    "loadAverage": m.loadAverage,
                    "swapUsedGB": m.swapUsedGB,
                    "statusTitle": m.statusTitle
                ]
            }
            return res

        case "get_events":
            let limit = payload["limit"] as? Int ?? 50
            let events = await EventLogger.shared.getRecentEvents(limit: limit)
            let eventData: [[String: Any]] = events.map { ev in
                var dict: [String: Any] = [
                    "id": ev.id.uuidString,
                    "timestamp": ISO8601DateFormatter().string(from: ev.timestamp),
                    "type": ev.type,
                    "summary": ev.summary
                ]
                if let d = ev.details {
                    dict["details"] = d
                }
                return dict
            }
            return ["status": "ok", "events": eventData]

        case "get_processes":
            let limit = payload["limit"] as? Int ?? 20
            let filter = payload["filter"] as? String
            let sortByStr = payload["sortBy"] as? String ?? "cpu"
            let sortOption: ProcessSortOption = sortByStr == "memory" ? .memory : (sortByStr == "name" ? .name : .cpu)
            let procs = await appState.processManager.getProcesses(sortBy: sortOption, filter: filter, limit: limit)
            let list = procs.map { p in
                [
                    "pid": p.id,
                    "name": p.name,
                    "cpuUsage": p.cpuUsage,
                    "memoryMB": p.memoryUsageMB,
                    "isBuildTool": p.isBuildTool,
                    "isOrphan": p.isOrphan,
                    "commandLine": p.commandLine as Any
                ]
            }
            return ["status": "ok", "processes": list]

        case "set_voice_mute":
            let muted = payload["muted"] as? Bool ?? true
            appState.setVoiceMuted(muted)
            return ["status": "ok", "isVoiceMuted": appState.isVoiceMuted]

        case "open_settings":
            appState.showSettings = true
            appState.isPanelOpen = true
            return ["status": "ok", "showSettings": true]

        case "close_settings":
            appState.showSettings = false
            return ["status": "ok", "showSettings": false]

        case "stop_audio":
            appState.stopAudio()
            return ["status": "ok", "stopped": true]

        case "speak":
            guard let text = payload["message"] as? String else {
                return ["status": "error", "message": "Mensagem ausente"]
            }
            appState.speakAnnouncement(text)
            return ["status": "ok", "spoken": text]

        case "resolve_incident":
            guard let idStr = payload["id"] as? String, let uuid = UUID(uuidString: idStr) else {
                return ["status": "error", "message": "ID do incidente inválido"]
            }
            guard let inc = appState.activeIncidents.first(where: { $0.id == uuid }) else {
                return ["status": "error", "message": "Incidente não encontrado"]
            }
            let execute = payload["executeAction"] as? Bool ?? false
            if execute {
                await appState.executeIncidentAction(inc)
            } else {
                appState.dismissIncident(inc)
            }
            return ["status": "ok", "resolved": idStr]

        case "manage_process":
            guard let pid = payload["pid"] as? Int32 else {
                return ["status": "error", "message": "PID ausente ou inválido"]
            }
            let sig = payload["signal"] as? String ?? "kill"
            if sig == "restart" {
                try? await appState.processManager.restartProcess(pid: pid)
            } else {
                try? await appState.processManager.killProcess(pid: pid)
            }
            await appState.refresh()
            return ["status": "ok", "pid": pid, "action": sig]

        default:
            return ["status": "error", "message": "Ação desconhecida: \(action)"]
        }
    }

    private func sendResponse(_ dict: [String: Any], handle: FileHandle) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        try? handle.write(contentsOf: data)
        try? handle.close()
    }
}
