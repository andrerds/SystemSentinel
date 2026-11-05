import XCTest
import Foundation
@testable import main

final class SystemMetricsTests: XCTestCase {
    private func metrics(cpu: Double, memoryUsedGB: Double, total: Double = 16) -> SystemMetrics {
        SystemMetrics(
            cpuUsage: cpu,
            memoryUsed: UInt64(memoryUsedGB * 1_073_741_824),
            memoryTotal: UInt64(total * 1_073_741_824),
            memoryWired: 0,
            memoryCompressor: 0,
            swapUsed: 0,
            gpuUsage: nil,
            loadAverage: 1.5
        )
    }

    func testHealthyMetricsReportNormal() {
        let m = metrics(cpu: 12, memoryUsedGB: 4)
        XCTAssertFalse(m.isCritical)
        XCTAssertFalse(m.isWarning)
        XCTAssertEqual(m.statusTitle, "Normal")
    }

    func testHighCpuIsWarningButNotCritical() {
        let m = metrics(cpu: 75, memoryUsedGB: 4)
        XCTAssertTrue(m.isWarning)
        XCTAssertFalse(m.isCritical)
        XCTAssertEqual(m.statusTitle, "Atenção")
    }

    func testCpuAtCriticalThresholdIsCritical() {
        let m = metrics(cpu: 90, memoryUsedGB: 4)
        XCTAssertTrue(m.isCritical)
        XCTAssertEqual(m.statusTitle, "Crítico")
    }

    func testMemoryUsagePercentIsRelativeToTotal() {
        let m = metrics(cpu: 0, memoryUsedGB: 8, total: 16)
        XCTAssertEqual(m.memoryUsagePercent, 50, accuracy: 0.001)
        XCTAssertEqual(m.memoryTotalGB, 16)
    }

    func testZeroTotalMemoryDoesNotDivideByZero() {
        let m = SystemMetrics(
            cpuUsage: 0, memoryUsed: 0, memoryTotal: 0,
            memoryWired: 0, memoryCompressor: 0, swapUsed: 0,
            gpuUsage: nil, loadAverage: 0
        )
        XCTAssertEqual(m.memoryUsagePercent, 0)
    }
}

final class SystemProcessTests: XCTestCase {
    func testProcessIsOrphanOnlyAfter24Hours() {
        let recent = SystemProcess(id: 42, name: "app", cpuUsage: 1, memoryUsage: 0, startTime: Date())
        let old = SystemProcess(
            id: 43, name: "old", cpuUsage: 1, memoryUsage: 0,
            startTime: Date().addingTimeInterval(-90_000)
        )
        XCTAssertFalse(recent.isOrphan)
        XCTAssertTrue(old.isOrphan)
    }

    func testProcessWithoutStartTimeIsNotOrphan() {
        let unknown = SystemProcess(id: 44, name: "svc", cpuUsage: 1, memoryUsage: 0, startTime: nil)
        XCTAssertFalse(unknown.isOrphan)
    }

    func testProcessMemoryFormattingSwitchesToGigabytes() {
        let megabytes = SystemProcess(id: 1, name: "a", cpuUsage: 0, memoryUsage: 512 * 1_048_576, startTime: nil)
        let gigabytes = SystemProcess(id: 2, name: "b", cpuUsage: 0, memoryUsage: 2 * 1_073_741_824, startTime: nil)
        XCTAssertEqual(megabytes.formattedMemory, "512 MB")
        XCTAssertEqual(gigabytes.formattedMemory, "2.0 GB")
    }
}

final class AppSettingsTests: XCTestCase {
    func testLegacySettingsDefaultToNotchIslandDisabled() throws {
        // Um arquivo antigo, sem a chave nova, deve manter o painel da barra de
        // menus como entrada principal.
        let legacy = """
        {"llmEndpoint":"http://localhost:11434","llmModel":"llama3.2","cpuWarningThreshold":65}
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: legacy)
        XCTAssertFalse(settings.showNotchIsland)
        XCTAssertEqual(settings.cpuWarningThreshold, 65)
        XCTAssertEqual(settings.memoryCriticalThreshold, 90)
    }

    func testSettingsRoundTripKeepsNotchPreference() throws {
        var settings = AppSettings()
        settings.showNotchIsland = true
        settings.cpuCriticalThreshold = 88

        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertTrue(decoded.showNotchIsland)
        XCTAssertEqual(decoded.cpuCriticalThreshold, 88)
    }

    func testSortOptionsExposeStableLabels() {
        XCTAssertEqual(ProcessSortOption.allCases.map(\.rawValue), ["CPU", "RAM", "Nome"])
    }
}
