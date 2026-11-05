import Foundation

// MARK: - System Monitor
actor SystemMonitor {
    func getMetrics() -> SystemMetrics {
        let mem = getMemoryInfo()
        return SystemMetrics(
            cpuUsage: getCPUUsage(),
            memoryUsed: mem.0,
            memoryTotal: mem.1,
            memoryWired: mem.2,
            memoryCompressor: mem.3,
            swapUsed: mem.4,
            gpuUsage: nil,
            loadAverage: getLoadAverage()
        )
    }

    private func getLoadAverage() -> Double {
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, 3) > 0 else { return 0 }
        return loads[0]
    }

    private func getCPUUsage() -> Double {
        var numCPUsU: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        let err = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUsU, &cpuInfo, &numCpuInfo)
        guard err == KERN_SUCCESS, let cpuInfo = cpuInfo else { return 0 }

        var totalUsage: Double = 0
        for i in 0..<Int(numCPUsU) {
            let offset = Int32(CPU_STATE_MAX) * Int32(i)
            let user = Double(cpuInfo[Int(offset + Int32(CPU_STATE_USER))])
            let system = Double(cpuInfo[Int(offset + Int32(CPU_STATE_SYSTEM))])
            let idle = Double(cpuInfo[Int(offset + Int32(CPU_STATE_IDLE))])
            let nice = Double(cpuInfo[Int(offset + Int32(CPU_STATE_NICE))])
            let total = user + system + idle + nice
            if total > 0 {
                totalUsage += ((user + system + nice) / total) * 100
            }
        }
        let size = vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)
        return totalUsage / Double(numCPUsU)
    }

    private func getMemoryInfo() -> (UInt64, UInt64, UInt64, UInt64, UInt64) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0, 0, 0, 0) }
        let pageSize = UInt64(vm_kernel_page_size)
        let total = UInt64(ProcessInfo.processInfo.physicalMemory)
        let free = UInt64(stats.free_count) * pageSize
        let inactive = UInt64(stats.inactive_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressor = UInt64(stats.compressor_page_count) * pageSize
        let used = total - free - inactive
        let swapUsage = xsw_usage()
        return (used, total, wired, compressor, swapUsage.xsu_used)
    }
}
