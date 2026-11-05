import SwiftUI
import AppKit

// MARK: - Compact Notch View
struct CompactNotchView: View {
    @ObservedObject var appState: AppState
    let isNotch: Bool
    let screen: NSScreen

    var body: some View {
        if isNotch {
            hardwareNotchLayout
        } else {
            floatingPillLayout
        }
    }

    // MARK: - Hardware Notch Layout (Flanking camera left and right)
    private var hardwareNotchLayout: some View {
        HStack(alignment: .center, spacing: 0) {
            // Left Ear: CPU
            HStack(spacing: 5) {
                Image(systemName: isCritical ? "exclamationmark.triangle.fill" : "cpu")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(cpuColor)
                
                Text(String(format: "%.0f%%", cpuUsage))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
            }
            .frame(width: 54, alignment: .leading)
            .padding(.leading, 6)
            
            // Center is reserved for the physical camera notch cutout (pitch black)
            Spacer(minLength: 0)
                .frame(width: NotchGeometry.physicalCutoutWidth(for: screen))
            
            // Right Ear: RAM / Swap
            HStack(spacing: 5) {
                Text(String(format: "%.0f%%", ramUsage))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                
                Image(systemName: "memorychip")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(ramColor)
                
                if (appState.metrics?.swapUsed ?? 0) > 0 {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(width: 54, alignment: .trailing)
            .padding(.trailing, 6)
        }
        .frame(height: max(34, screen.safeAreaInsets.top))
    }

    // MARK: - Floating Pill Layout (External / Non-Notch Display)
    private var floatingPillLayout: some View {
        HStack(spacing: 9) {
            // CPU Indicator
            HStack(spacing: 5) {
                Image(systemName: isCritical ? "exclamationmark.triangle.fill" : "cpu")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(cpuColor)
                Text(String(format: "%.0f%%", cpuUsage))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
            }

            // Divider Dot
            Circle()
                .fill(Color.white.opacity(0.28))
                .frame(width: 3.5, height: 3.5)

            // RAM Indicator
            HStack(spacing: 5) {
                Image(systemName: "memorychip")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(ramColor)
                Text(String(format: "%.0f%%", ramUsage))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
            }

            // Status Glow Dot if warning or critical
            if isWarning || isCritical {
                Circle()
                    .fill(isCritical ? Color.red : Color.orange)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
    }

    // MARK: - Helpers
    private var cpuUsage: Double { appState.metrics?.cpuUsage ?? 0 }
    private var ramUsage: Double { appState.metrics?.memoryUsagePercent ?? 0 }
    private var isCritical: Bool { appState.metrics?.isCritical == true }
    private var isWarning: Bool { appState.metrics?.isWarning == true }

    private var cpuColor: Color {
        if cpuUsage >= appState.settings.cpuCriticalThreshold { return Color(red: 1.0, green: 0.27, blue: 0.23) }
        if cpuUsage >= appState.settings.cpuWarningThreshold { return Color(red: 1.0, green: 0.62, blue: 0.04) }
        return Color(red: 0.19, green: 0.82, blue: 0.35)
    }

    private var ramColor: Color {
        if ramUsage >= appState.settings.memoryCriticalThreshold { return Color(red: 1.0, green: 0.27, blue: 0.23) }
        if ramUsage >= appState.settings.memoryWarningThreshold { return Color(red: 1.0, green: 0.62, blue: 0.04) }
        return Color(red: 0.04, green: 0.52, blue: 1.0)
    }
}
