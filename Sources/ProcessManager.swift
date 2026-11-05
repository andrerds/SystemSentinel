import Foundation
import AppKit

// MARK: - Process Manager
actor ProcessManager {
    enum ProcessError: Error {
        case killFailed
    }

    func getProcesses(sortBy: ProcessSortOption = .cpu, filter: String? = nil, limit: Int = 30) -> [SystemProcess] {
        var procs = collectProcesses(sortBy: sortBy, limit: 60)
        
        if let query = filter?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            procs = procs.filter {
                $0.name.localizedCaseInsensitiveContains(query) || "\($0.id)".contains(query)
            }
        }
        
        switch sortBy {
        case .cpu:
            procs.sort { $0.cpuUsage > $1.cpuUsage }
        case .memory:
            procs.sort { $0.memoryUsage > $1.memoryUsage }
        case .name:
            procs.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        }
        
        return Array(procs.prefix(limit))
    }

    func getOrphanProcesses() -> [SystemProcess] {
        collectProcesses(sortBy: .cpu, limit: 100).filter { $0.isOrphan && $0.cpuUsage > 0 }
    }

    func killProcess(pid: Int32) throws {
        if kill(pid, SIGKILL) != 0 {
            throw ProcessError.killFailed
        }
    }

    func killProcesses(pids: [Int32]) -> [Int32] {
        pids.filter { (try? killProcess(pid: $0)) == nil }
    }

    func restartProcess(pid: Int32) throws {
        // Envia SIGTERM e depois se for processo conhecido, tenta restart
        _ = kill(pid, SIGTERM)
    }

    func stopDockerContainer(name: String) -> Bool {
        let task = Process()
        let paths = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", "/usr/bin/docker"]
        guard let dockerPath = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return false }
        task.launchPath = dockerPath
        task.arguments = ["stop", name]
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    func restartDockerContainer(name: String) -> Bool {
        let task = Process()
        let paths = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", "/usr/bin/docker"]
        guard let dockerPath = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return false }
        task.launchPath = dockerPath
        task.arguments = ["restart", name]
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    private func collectProcesses(sortBy: ProcessSortOption, limit: Int) -> [SystemProcess] {
        let task = Process()
        task.launchPath = "/bin/ps"
        let sortFlag = (sortBy == .memory) ? "-m" : "-r"
        task.arguments = ["-Aceo", "pid,ppid,pcpu,comm", sortFlag]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var results: [SystemProcess] = []
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > 1 else { return [] }

        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            // Format: PID PPID %CPU COMM...
            let parts = trimmed.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count >= 4,
                  let pid = Int32(parts[0]),
                  let ppid = Int32(parts[1]) else { continue }
            
            let cpuStr = parts[2].replacingOccurrences(of: ",", with: ".")
            let cpuUsage = Double(cpuStr) ?? 0.0
            let command = String(parts[3]).trimmingCharacters(in: .whitespaces)
            
            if pid <= 1 { continue }

            let displayName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? command
            let memory = getProcessMemory(pid: pid)
            let start = getProcessStartTime(pid: pid)
            let details = getProcessDetails(pid: pid)

            results.append(SystemProcess(
                id: pid,
                name: displayName,
                cpuUsage: cpuUsage,
                memoryUsage: memory,
                startTime: start,
                ppid: ppid,
                path: details.path,
                commandLine: details.commandLine,
                uid: details.uid,
                totalCpuTimeSeconds: details.totalCpuSec
            ))

            if results.count >= limit { break }
        }
        return results
    }

    private func getProcessMemory(pid: Int32) -> UInt64 {
        var taskInfo = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, size) == size else { return 0 }
        return UInt64(taskInfo.pti_resident_size)
    }

    private func getProcessStartTime(pid: Int32) -> Date? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec))
    }

    private func getProcessDetails(pid: Int32) -> (uid: UInt32?, path: String?, commandLine: String?, totalCpuSec: Double) {
        var bsd = proc_bsdinfo()
        let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        var uid: UInt32? = nil
        if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, bsdSize) == bsdSize {
            uid = bsd.pbi_uid
        }
        
        var task = proc_taskinfo()
        let taskSize = Int32(MemoryLayout<proc_taskinfo>.size)
        var cpuSec: Double = 0
        if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, taskSize) == taskSize {
            cpuSec = Double(task.pti_total_user + task.pti_total_system) / 1_000_000_000.0
        }
        
        var pathBuf = [CChar](repeating: 0, count: 4096)
        let pathLen = proc_pidpath(pid, &pathBuf, 4096)
        let path = pathLen > 0 ? String(cString: pathBuf) : nil
        
        let cmd = getProcessCommandLine(pid: pid)
        
        return (uid, path, cmd, cpuSec)
    }

    private func getProcessCommandLine(pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: Int = 0
        if sysctl(&mib, 3, nil, &size, nil, 0) != 0 || size <= 0 {
            return nil
        }
        var buffer = [CChar](repeating: 0, count: size)
        if sysctl(&mib, 3, &buffer, &size, nil, 0) != 0 {
            return nil
        }
        guard size > MemoryLayout<Int32>.size else { return nil }
        var argc: Int32 = 0
        memcpy(&argc, buffer, MemoryLayout<Int32>.size)
        
        var offset = MemoryLayout<Int32>.size
        while offset < size && buffer[offset] != 0 {
            offset += 1
        }
        while offset < size && buffer[offset] == 0 {
            offset += 1
        }
        var args: [String] = []
        buffer.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            while offset < size && args.count < Int(argc) {
                let start = offset
                while offset < size && buffer[offset] != 0 {
                    offset += 1
                }
                if offset > start {
                    let str = String(cString: base + start)
                    args.append(str)
                }
                offset += 1
            }
        }
        return args.isEmpty ? nil : args.joined(separator: " ")
    }
}

// MARK: - Process Icon Provider (cache rápida e não bloqueante)
@MainActor
final class ProcessIconProvider {
    static let shared = ProcessIconProvider()

    private var cache: [Int32: NSImage] = [:]
    private var unresolved: Set<Int32> = []

    /// Devolve o ícone do app dono do processo, ou `nil` quando não há um ícone
    /// representativo (a view desenha um marcador neutro nesse caso).
    func icon(for process: SystemProcess) -> NSImage? {
        if let cached = cache[process.id] { return cached }
        if unresolved.contains(process.id) { return nil }

        if let resolved = resolveIcon(for: process) {
            if cache.count > 150 { cache.removeAll(keepingCapacity: true) }
            cache[process.id] = resolved
            return resolved
        }

        if unresolved.count > 200 { unresolved.removeAll(keepingCapacity: true) }
        unresolved.insert(process.id)
        return nil
    }

    private func resolveIcon(for process: SystemProcess) -> NSImage? {
        // Helpers e serviços não têm app próprio: sobe no caminho do binário até o
        // bundle .app mais externo (ex.: "Google Chrome Helper" → ícone do Chrome).
        if let path = executablePath(for: process.id) {
            guard let bundlePath = outermostAppBundle(for: path) else {
                // Binário solto (CLI/serviço): sem ícone representativo → marcador neutro
                return nil
            }
            return NSWorkspace.shared.icon(forFile: bundlePath)
        }

        return NSRunningApplication(processIdentifier: process.id)?.icon
    }

    /// Sobe no caminho e devolve o `.app` mais externo (ignora helpers aninhados
    /// como "Google Chrome Helper (Renderer).app", que têm ícone genérico).
    private func outermostAppBundle(for path: String) -> String? {
        var url = URL(fileURLWithPath: path)
        var found: String?
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            if url.pathExtension == "app" { found = url.path }
        }
        return found
    }

    private func executablePath(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }
}

