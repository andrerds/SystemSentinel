import Foundation

// MARK: - Voice Service (Cartesia Sonic PT-BR / falar com fallback)
actor VoiceService {
    static let shared = VoiceService()

    private var lastSpokenTime: [String: Date] = [:]
    private let minIntervalSeconds: TimeInterval = 120 // 2 minutos entre avisos semelhantes da mesma categoria
    private var currentTask: Process?
    private(set) var isSpeaking: Bool = false
    private(set) var isMuted: Bool = false

    private var stateChangeCallback: (@Sendable (Bool) -> Void)?

    private init() {}

    func setStateChangeHandler(_ handler: @escaping @Sendable (Bool) -> Void) {
        self.stateChangeCallback = handler
    }

    func setMuted(_ muted: Bool) {
        self.isMuted = muted
        if muted {
            stopAudio()
        }
    }

    func stopAudio() {
        if let task = currentTask, task.isRunning {
            task.terminate()
        }
        currentTask = nil
        isSpeaking = false
        stateChangeCallback?(false)

        // Encerra imediatamente qualquer player de áudio órfão disparado pelo falar ou say
        Task.detached {
            Self.killAudioPlayers()
        }
    }

    func speak(_ message: String, category: String = "general", force: Bool = false) {
        guard !isMuted else { return }

        let now = Date()
        if !force, let last = lastSpokenTime[category], now.timeIntervalSince(last) < minIntervalSeconds {
            return
        }
        lastSpokenTime[category] = now

        // Interrompe fala anterior para dar lugar ao novo aviso
        if let task = currentTask, task.isRunning {
            task.terminate()
        }

        isSpeaking = true
        stateChangeCallback?(true)

        let task = Process()
        self.currentTask = task

        Task.detached {
            Self.executeSpeak(message, process: task) {
                Task {
                    await VoiceService.shared.finishSpeaking(task: task)
                }
            }
        }
    }

    private func finishSpeaking(task: Process) {
        if currentTask == task {
            currentTask = nil
            isSpeaking = false
            stateChangeCallback?(false)
        }
    }

    private static func findFalarExecutable() -> String? {
        let candidates = [
            NSString(string: "~/bin/falar").expandingTildeInPath,
            NSString(string: "~/.local/bin/falar").expandingTildeInPath,
            "/opt/homebrew/bin/falar",
            "/usr/local/bin/falar"
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Tenta resolver via which falar
        let whichTask = Process()
        whichTask.launchPath = "/usr/bin/which"
        whichTask.arguments = ["falar"]
        let pipe = Pipe()
        whichTask.standardOutput = pipe
        whichTask.standardError = Pipe()
        do {
            try whichTask.run()
            whichTask.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty, FileManager.default.isExecutableFile(atPath: output) {
                return output
            }
        } catch {}

        return nil
    }

    private static func executeSpeak(_ message: String, process: Process, completion: @escaping @Sendable () -> Void) {
        let falarPath = findFalarExecutable()

        if let falarPath = falarPath {
            process.launchPath = falarPath
            // Usa as flags corretas do falar: --interrupt para cortar qualquer áudio pendente,
            // e metadados de projeto/contexto conforme padrão do sistema
            process.arguments = [
                "--interrupt",
                "--project", "SystemSentinel",
                "--context", "Guardião Proativo",
                message
            ]
        } else {
            process.launchPath = "/usr/bin/say"
            process.arguments = ["-v", "Luciana", message]
        }

        process.standardOutput = Pipe()
        process.standardError = Pipe()

        process.terminationHandler = { _ in
            completion()
        }

        do {
            try process.run()
        } catch {
            // Fallback caso o processo principal falhe
            let fallback = Process()
            fallback.launchPath = "/usr/bin/say"
            fallback.arguments = ["-v", "Luciana", message]
            fallback.terminationHandler = { _ in completion() }
            do {
                try fallback.run()
            } catch {
                completion()
            }
        }
    }

    private static func killAudioPlayers() {
        // Encerra ffplay, afplay associados ao falar/kokoro/easyvoice e say
        let pkill = Process()
        pkill.launchPath = "/usr/bin/pkill"
        pkill.arguments = ["-f", "ffplay.*-nodisp|afplay.*falar|afplay.*kokoro|afplay.*easyvoice"]
        pkill.standardOutput = Pipe()
        pkill.standardError = Pipe()
        try? pkill.run()
        pkill.waitUntilExit()

        let killSay = Process()
        killSay.launchPath = "/usr/bin/killall"
        killSay.arguments = ["say"]
        killSay.standardOutput = Pipe()
        killSay.standardError = Pipe()
        try? killSay.run()
        killSay.waitUntilExit()
    }
}
