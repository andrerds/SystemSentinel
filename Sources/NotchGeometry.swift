import SwiftUI
import AppKit

// MARK: - Notch Detection & Sizing (from Atoll)
enum NotchGeometry {
    /// Extra bleed height beyond screen.maxY to seal against the physical MacBook bezel
    static let notchTopScreenBleedAmount: CGFloat = 4.0
    
    /// Float offset below the menu bar on external displays / non-notch Macs
    static let dynamicIslandTopOffset: CGFloat = 6.0
    
    /// Always targets the physical screen with the hardware camera notch
    static func targetScreen() -> NSScreen {
        if let physicalNotch = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return physicalNotch
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }
    
    /// Checks if the given screen has a physical camera notch
    static func isNotchDisplay(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0
    }
    
    /// Calculates the physical width of the MacBook camera housing cutout
    static func physicalCutoutWidth(for screen: NSScreen) -> CGFloat {
        let leftPad = screen.auxiliaryTopLeftArea?.width ?? 0
        let rightPad = screen.auxiliaryTopRightArea?.width ?? 0
        if leftPad > 0 && rightPad > 0 {
            return screen.frame.width - leftPad - rightPad + 4
        }
        return 213
    }
    
    /// Calculates the closed notch size matching the screen hardware
    static func closedSize(for screen: NSScreen) -> CGSize {
        if isNotchDisplay(screen) {
            let cameraCutout = physicalCutoutWidth(for: screen)
            // Left ear (60pt) + physical camera cutout + Right ear (60pt)
            let totalWidth = cameraCutout + 120
            let height = max(34, screen.safeAreaInsets.top)
            return CGSize(width: totalWidth, height: height)
        } else {
            // Pill size on external display (Atoll capsule standard)
            return CGSize(width: 220, height: 34)
        }
    }
    
    /// The size when the island is expanded (widescreen shelf matching Atoll)
    static func expandedSize(for screen: NSScreen) -> CGSize {
        let maxWidth = min(620, screen.frame.width - 40).rounded()
        return CGSize(width: maxWidth, height: 230)
    }
}

// MARK: - NotchShape (Atoll Bezier curve matching Apple camera bezel)
struct NotchShape: Shape {
    var topCornerRadius: CGFloat = 6
    var bottomCornerRadius: CGFloat = 14

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Top-left starting point
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Top-left curve outwards into the bezel
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
        )

        // Left downward line
        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius))

        // Bottom-left rounded corner
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
        )

        // Bottom line
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))

        // Bottom-right rounded corner
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY)
        )

        // Right upward line
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius))

        // Top-right curve outwards into the bezel
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY)
        )

        // Close back across the top edge
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        return path
    }
}

// MARK: - Dynamic Island Pill Shape (Continuous squircle for external screens)
struct DynamicIslandPillShape: Shape {
    var cornerRadius: CGFloat

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let resolvedRadius = min(cornerRadius, min(rect.width, rect.height) / 2)
        return Path(roundedRect: rect, cornerRadius: resolvedRadius, style: .continuous)
    }
}
