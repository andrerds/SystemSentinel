import SwiftUI
import AppKit

// MARK: - System Metrics
struct SystemMetrics: Codable, Equatable {
    var cpuUsage: Double
    var memoryUsed: UInt64
    var memoryTotal: UInt64
    var memoryWired: UInt64
    var memoryCompressor: UInt64
    var swapUsed: UInt64
    var gpuUsage: Double?
    /// Média de carga do sistema no último minuto (getloadavg).
    var loadAverage: Double

    var memoryUsagePercent: Double {
        guard memoryTotal > 0 else { return 0 }
        return Double(memoryUsed) / Double(memoryTotal) * 100
    }
    
    var memoryUsedGB: Double { Double(memoryUsed) / 1_073_741_824 }
    var memoryTotalGB: Double { Double(memoryTotal) / 1_073_741_824 }
    var memoryWiredGB: Double { Double(memoryWired) / 1_073_741_824 }
    var memoryCompressorGB: Double { Double(memoryCompressor) / 1_073_741_824 }
    var swapUsedGB: Double { Double(swapUsed) / 1_073_741_824 }
    
    var isCritical: Bool { cpuUsage >= 90 || memoryUsagePercent >= 90 }
    var isWarning: Bool { (cpuUsage >= 70 || memoryUsagePercent >= 75) && !isCritical }
    
    var statusTitle: String {
        if isCritical { return "Crítico" }
        if isWarning { return "Atenção" }
        return "Normal"
    }
    
    var statusColor: Color {
        if isCritical { return Color(red: 1.0, green: 0.27, blue: 0.23) } // Apple Red
        if isWarning { return Color(red: 1.0, green: 0.62, blue: 0.04) }  // Apple Orange
        return Color(red: 0.19, green: 0.82, blue: 0.35)                  // Apple Green
    }

    /// Nível de alerta segundo os limites que o usuário configurou.
    /// É isto que alimenta o indicador da barra de menus.
    func alertLevel(for settings: AppSettings, hasActiveIncident: Bool = false, maxProcessCpu: Double = 0) -> AlertLevel {
        if hasActiveIncident || cpuUsage >= settings.cpuCriticalThreshold || memoryUsagePercent >= settings.memoryCriticalThreshold || loadAverage >= (settings.loadAverageThreshold * 1.4) {
            return .critical
        }
        if cpuUsage >= settings.cpuWarningThreshold || memoryUsagePercent >= settings.memoryWarningThreshold || loadAverage >= settings.loadAverageThreshold || maxProcessCpu >= settings.singleProcessCpuThreshold {
            return .warning
        }
        return .normal
    }
}

// MARK: - Anomalias e Incidentes Proativos
enum AnomalyType: String, Codable, CaseIterable {
    case highLoad = "Sobrecarga de Sistema"
    case cpuSpike = "Alta CPU Travada"
    case runawayCommand = "Comando em Loop"
    case dockerCrashLoop = "Docker em Crash Loop"
    case orphanProcess = "Processo Órfão"
    case buildInProgress = "Compilação em Andamento"

    var icon: String {
        switch self {
        case .highLoad: return "flame.fill"
        case .cpuSpike: return "cpu.fill"
        case .runawayCommand: return "terminal.fill"
        case .dockerCrashLoop: return "shippingbox.fill"
        case .orphanProcess: return "person.crop.circle.badge.exclamationmark"
        case .buildInProgress: return "hammer.fill"
        }
    }
}

enum AnomalyAction: String, Codable {
    case kill = "Encerrar"
    case restart = "Reiniciar"
    case stopDocker = "Parar Contêiner"
    case ignore = "Ignorar"
}

struct SystemIncident: Identifiable, Codable, Equatable {
    let id: UUID
    let type: AnomalyType
    let title: String
    let description: String
    let pid: Int32?
    let containerName: String?
    var llmDiagnosis: String?
    var recommendedAction: AnomalyAction
    let detectedAt: Date
    var isResolved: Bool
}

// MARK: - Nível de alerta do sistema
enum AlertLevel: Int, Comparable {
    case normal = 0
    case warning = 1
    case critical = 2

    static func < (lhs: AlertLevel, rhs: AlertLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Atenção"
        case .critical: return "Crítico"
        }
    }
}

// MARK: - Process Info
struct SystemProcess: Identifiable, Codable, Equatable {
    let id: Int32
    let name: String
    let cpuUsage: Double
    let memoryUsage: UInt64
    let startTime: Date?
    var ppid: Int32? = nil
    var path: String? = nil
    var commandLine: String? = nil
    var uid: UInt32? = nil
    var totalCpuTimeSeconds: Double = 0.0
    
    var memoryUsageMB: Double { Double(memoryUsage) / 1_048_576 }
    var memoryUsageGB: Double { Double(memoryUsage) / 1_073_741_824 }
    
    var elapsedSeconds: TimeInterval {
        startTime.map { Date().timeIntervalSince($0) } ?? 0
    }

    var isBuildTool: Bool {
        let nameLower = name.lowercased()
        let exactBuildNames: Set<String> = [
            "swift", "swift-build", "as", "ar", "cc", "c++", "ld", "ld64", "go",
            "make", "ninja", "tar", "gzip", "bun", "javac", "mvn", "dart", "flutter",
            "ng", "nx", "turbo", "lerna", "pnpm", "yarn", "npm", "npx"
        ]
        if exactBuildNames.contains(nameLower) {
            return true
        }

        let combined = "\(nameLower) \(path?.lowercased() ?? "") \(commandLine?.lowercased() ?? "")"
        let distinctKeywords = [
            "swiftc", "swift-frontend", "swift-driver", "sourcekit-lsp", "xcodebuild",
            "ibtool", "actool", "assetutil", "simctl", "codesign", "clang", "apple-clang",
            "gcc", "g++", "rustc", "cargo", "cargo-clippy", "rust-analyzer",
            "esbuild", "webpack", "rollup", "turbopack", "vite", "tsc", "swc",
            "postcss", "babel", "kotlinc", "gradle", "gradlew", "buildkitd", "cmake",
            "run build", ":build", "app:build", "build:production", "build:prod"
        ]
        return distinctKeywords.contains { combined.contains($0) }
    }

    var isUserOrphan: Bool {
        guard let ppid = ppid, ppid == 1 else { return false }
        if let uid = uid, uid != getuid() { return false }
        
        let lowerPath = (path ?? "").lowercased()
        let lowerName = name.lowercased()
        
        if lowerPath.hasPrefix("/system/") || lowerPath.hasPrefix("/usr/libexec") || lowerPath.hasPrefix("/usr/sbin") {
            return false
        }
        let systemApps = ["windowserver", "dock", "finder", "systemuiserver", "controlcenter", "loginwindow", "spotlight"]
        if systemApps.contains(where: { lowerName.contains($0) }) {
            return false
        }
        return true
    }

    var isOrphan: Bool {
        if isUserOrphan {
            return true
        }
        guard let start = startTime else { return false }
        return Date().timeIntervalSince(start) > 86400
    }
    
    var formattedMemory: String {
        if memoryUsageGB >= 1.0 {
            return String(format: "%.1f GB", memoryUsageGB)
        } else {
            return String(format: "%.0f MB", memoryUsageMB)
        }
    }
}

// MARK: - LLM Analysis
struct LLMAnalysis: Codable, Equatable {
    let processId: Int32
    let processName: String
    let safeToKill: Bool
    let reason: String
    let warning: String?
}

// MARK: - App Settings
struct AppSettings: Codable, Equatable {
    var llmEndpoint: String = "http://localhost:11434"
    var llmModel: String = "llama3.2"
    var llmApiKey: String = ""
    var cpuWarningThreshold: Double = 70
    var cpuCriticalThreshold: Double = 90
    var memoryWarningThreshold: Double = 75
    var memoryCriticalThreshold: Double = 90
    var loadAverageThreshold: Double = 8.0
    var singleProcessCpuThreshold: Double = 80.0
    var enableProactiveMonitoring: Bool = true
    var proactiveVoiceAlerts: Bool = true
    var isVoiceMuted: Bool = false
    var ignoreBuildProcesses: Bool = true
    var proactiveNotifications: Bool = true
    var autoHealSafeAnomalies: Bool = false
    var hoverDwellDuration: Double = 0.12
    var exitGraceDuration: Double = 0.40
    var autoKillOrphans: Bool = false
    var openOnHover: Bool = true
    /// Ilha no notch. Desligada por padrão: a entrada principal passa a ser o painel da barra de menus.
    var showNotchIsland: Bool = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        llmEndpoint = (try? c.decode(String.self, forKey: .llmEndpoint)) ?? "http://localhost:11434"
        llmModel = (try? c.decode(String.self, forKey: .llmModel)) ?? "llama3.2"
        llmApiKey = (try? c.decode(String.self, forKey: .llmApiKey)) ?? ""
        cpuWarningThreshold = (try? c.decode(Double.self, forKey: .cpuWarningThreshold)) ?? 70
        cpuCriticalThreshold = (try? c.decode(Double.self, forKey: .cpuCriticalThreshold)) ?? 90
        memoryWarningThreshold = (try? c.decode(Double.self, forKey: .memoryWarningThreshold)) ?? 75
        memoryCriticalThreshold = (try? c.decode(Double.self, forKey: .memoryCriticalThreshold)) ?? 90
        loadAverageThreshold = (try? c.decode(Double.self, forKey: .loadAverageThreshold)) ?? 8.0
        singleProcessCpuThreshold = (try? c.decode(Double.self, forKey: .singleProcessCpuThreshold)) ?? 80.0
        enableProactiveMonitoring = (try? c.decode(Bool.self, forKey: .enableProactiveMonitoring)) ?? true
        proactiveVoiceAlerts = (try? c.decode(Bool.self, forKey: .proactiveVoiceAlerts)) ?? true
        isVoiceMuted = (try? c.decode(Bool.self, forKey: .isVoiceMuted)) ?? false
        ignoreBuildProcesses = (try? c.decode(Bool.self, forKey: .ignoreBuildProcesses)) ?? true
        proactiveNotifications = (try? c.decode(Bool.self, forKey: .proactiveNotifications)) ?? true
        autoHealSafeAnomalies = (try? c.decode(Bool.self, forKey: .autoHealSafeAnomalies)) ?? false
        hoverDwellDuration = (try? c.decode(Double.self, forKey: .hoverDwellDuration)) ?? 0.12
        exitGraceDuration = (try? c.decode(Double.self, forKey: .exitGraceDuration)) ?? 0.40
        autoKillOrphans = (try? c.decode(Bool.self, forKey: .autoKillOrphans)) ?? false
        openOnHover = (try? c.decode(Bool.self, forKey: .openOnHover)) ?? true
        showNotchIsland = (try? c.decode(Bool.self, forKey: .showNotchIsland)) ?? false
    }
}

// MARK: - Enums
enum ProcessSortOption: String, CaseIterable, Identifiable {
    case cpu = "CPU"
    case memory = "RAM"
    case name = "Nome"
    var id: String { rawValue }
}
