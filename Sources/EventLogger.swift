import Foundation

// MARK: - Sentinel Event Representation
struct SentinelEvent: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let type: String // incident_detected, incident_resolved, voice_alert, voice_muted, voice_stopped, process_action
    let summary: String
    let details: [String: String]?

    init(id: UUID = UUID(), timestamp: Date = Date(), type: String, summary: String, details: [String: String]? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.summary = summary
        self.details = details
    }
}

// MARK: - Event Logger & State Persistence for Agents & MCP
actor EventLogger {
    static let shared = EventLogger()

    private let baseDirectory: URL
    private let eventsFile: URL
    private let stateFile: URL
    private var inMemoryEvents: [SentinelEvent] = []
    private let maxInMemory = 200

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".systemsentinel", isDirectory: true)
        self.baseDirectory = dir
        self.eventsFile = dir.appendingPathComponent("events.jsonl")
        self.stateFile = dir.appendingPathComponent("state.json")

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.inMemoryEvents = Self.loadRecentEventsFromDisk(file: eventsFile, maxCount: maxInMemory)
    }

    private static func loadRecentEventsFromDisk(file: URL, maxCount: Int) -> [SentinelEvent] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let lines = content.split(separator: "\n").suffix(maxCount)
        var loaded: [SentinelEvent] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
            if let event = try? decoder.decode(SentinelEvent.self, from: data) {
                loaded.append(event)
            }
        }
        return loaded
    }

    func log(type: String, summary: String, details: [String: String]? = nil) {
        let event = SentinelEvent(type: type, summary: summary, details: details)
        inMemoryEvents.append(event)
        if inMemoryEvents.count > maxInMemory {
            inMemoryEvents.removeFirst(inMemoryEvents.count - maxInMemory)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        if let data = try? encoder.encode(event), var line = String(data: data, encoding: .utf8) {
            line.append("\n")
            if let handle = try? FileHandle(forWritingTo: eventsFile) {
                handle.seekToEndOfFile()
                if let lineData = line.data(using: .utf8) {
                    handle.write(lineData)
                }
                try? handle.close()
            } else {
                try? line.write(to: eventsFile, atomically: true, encoding: .utf8)
            }
        }
    }

    func getRecentEvents(limit: Int = 50) -> [SentinelEvent] {
        let count = min(limit, inMemoryEvents.count)
        return Array(inMemoryEvents.suffix(count).reversed())
    }

    func updateSystemState(
        metrics: SystemMetrics?,
        activeIncidents: [SystemIncident],
        isVoiceMuted: Bool,
        isSpeaking: Bool,
        topProcesses: [SystemProcess]
    ) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]

        var payload: [String: Any] = [
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
            "isVoiceMuted": isVoiceMuted,
            "isSpeaking": isSpeaking,
            "activeIncidentCount": activeIncidents.count
        ]

        if let m = metrics {
            payload["metrics"] = [
                "cpuUsage": m.cpuUsage,
                "memoryUsagePercent": m.memoryUsagePercent,
                "memoryUsedGB": m.memoryUsedGB,
                "memoryTotalGB": m.memoryTotalGB,
                "loadAverage": m.loadAverage,
                "swapUsedGB": m.swapUsedGB,
                "isCritical": m.isCritical,
                "isWarning": m.isWarning,
                "statusTitle": m.statusTitle
            ]
        }

        let incData = activeIncidents.map { inc in
            [
                "id": inc.id.uuidString,
                "type": inc.type.rawValue,
                "title": inc.title,
                "description": inc.description,
                "pid": inc.pid as Any,
                "containerName": inc.containerName as Any,
                "recommendedAction": inc.recommendedAction.rawValue,
                "llmDiagnosis": inc.llmDiagnosis as Any,
                "detectedAt": ISO8601DateFormatter().string(from: inc.detectedAt)
            ]
        }
        payload["activeIncidents"] = incData

        let topProcData = topProcesses.prefix(15).map { p in
            [
                "pid": p.id,
                "name": p.name,
                "cpuUsage": p.cpuUsage,
                "memoryMB": p.memoryUsageMB,
                "isBuildTool": p.isBuildTool,
                "isOrphan": p.isOrphan
            ]
        }
        payload["topProcesses"] = topProcData

        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) {
            try? data.write(to: stateFile, options: .atomic)
        }
    }
}
