import SwiftUI
import AppKit

// MARK: - Dynamic Island Window Panel (based on Atoll)
final class DynamicIslandPanel: NSPanel {
    static let pinnedCollectionBehavior: NSWindow.CollectionBehavior = [
        .fullScreenAuxiliary,
        .canJoinAllSpaces,
        .ignoresCycle,
        .stationary,
    ]

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        hasShadow = false
        level = .mainMenu + 3
        animationBehavior = .none
        collectionBehavior = Self.pinnedCollectionBehavior
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    @objc func _postWindowNeedsUpdateConstraints() {
        // Protect against AppKit constraint pass exception loop during rapid animated window resizes
    }
}

// MARK: - First Mouse Hosting View (Atoll pattern)
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    @objc func windowDidLayout() {
        // Suppress NSHostingView's internal recursive updateAnimatedWindowSize loop on window resize
    }
}

// MARK: - Main Root Island View
struct DynamicIslandContainerView: View {
    @ObservedObject var appState: AppState
    let screen: NSScreen

    private var isNotch: Bool {
        screen.safeAreaInsets.top > 0
    }

    private var resolvedClipShape: AnyShape {
        if isNotch {
            let topRadius: CGFloat = appState.isExpanded ? 8 : 6
            let bottomRadius: CGFloat = appState.isExpanded ? 24 : 14
            return AnyShape(NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius))
        } else {
            let radius: CGFloat = appState.isExpanded ? 24 : 17
            return AnyShape(DynamicIslandPillShape(cornerRadius: radius))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if appState.isExpanded {
                ExpandedNotchView(appState: appState)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                CompactNotchView(appState: appState, isNotch: isNotch, screen: screen)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, isNotch ? NotchGeometry.notchTopScreenBleedAmount : 0)
        .background(Color.black)
        .clipShape(resolvedClipShape)
        .overlay(alignment: .top) {
            if isNotch {
                Rectangle()
                    .fill(Color.black)
                    .frame(height: NotchGeometry.notchTopScreenBleedAmount)
            }
        }
        .overlay {
            // Subtle glass border only on external pill displays (never on physical notch)
            if !isNotch {
                resolvedClipShape
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
        }
        .compositingGroup()
        .shadow(
            color: appState.isExpanded ? Color.black.opacity(0.6) : .clear,
            radius: appState.isExpanded ? 12 : 5
        )
        .contentShape(resolvedClipShape)
        .onTapGesture {
            if !appState.isExpanded {
                appState.setExpanded(true, byClick: true)
            } else {
                appState.openedByClick = true
            }
        }
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: appState.isExpanded)
    }
}

