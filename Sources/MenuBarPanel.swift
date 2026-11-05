import SwiftUI
import AppKit
import Combine

// MARK: - Menu Bar Panel (janela flutuante ancorada no ícone da barra)
final class MenuBarPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        animationBehavior = .utilityWindow
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    @objc func _postWindowNeedsUpdateConstraints() {
        // Evita o loop de constraints do AppKit durante redimensionamentos animados
    }
}

// MARK: - Controller (visibilidade, posicionamento e eventos de fechamento)
@MainActor
final class MenuBarPanelController {
    private let appState: AppState
    private let statusItem: NSStatusItem
    private let panel: MenuBarPanel
    private var cancellables = Set<AnyCancellable>()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var keyMonitor: Any?

    init(appState: AppState, statusItem: NSStatusItem) {
        self.appState = appState
        self.statusItem = statusItem
        self.panel = MenuBarPanel(
            contentRect: NSRect(x: 0, y: 0, width: DS.panelWidth, height: DS.panelHeight)
        )

        let host = FirstMouseHostingView(rootView: AnyView(MenuBarPanelView(appState: appState)))
        host.sizingOptions = []
        panel.contentView = host

        // isPanelOpen é a única fonte de verdade da visibilidade
        appState.$isPanelOpen
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] open in
                guard let self else { return }
                if open { self.present() } else { self.dismiss() }
            }
            .store(in: &cancellables)
    }

    func toggle() {
        appState.isPanelOpen.toggle()
    }

    func close() {
        appState.isPanelOpen = false
    }

    // MARK: Apresentação
    func present() {
        Task { await appState.loadProcessData() }

        panel.setFrame(computeFrame(), display: true)
        panel.makeKeyAndOrderFront(nil)
        activateApp()
        statusItem.button?.highlight(true)
        installMonitors()
    }

    private func dismiss() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        removeMonitors()

        appState.showSettings = false
        appState.analysisResult = nil
        appState.errorMessage = nil
        appState.processToKillConfirm = nil
    }

    private func activateApp() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: Posicionamento sob o ícone da barra
    private func computeFrame() -> NSRect {
        let width = DS.panelWidth
        let gap: CGFloat = 6
        let mouseLoc = NSEvent.mouseLocation

        // Encontra a tela onde o clique ocorreu ou onde o botão reside
        let screen: NSScreen = {
            if let target = NSScreen.screens.first(where: { $0.frame.contains(mouseLoc) }) {
                return target
            }
            if let btnWin = statusItem.button?.window, let s = btnWin.screen {
                return s
            }
            return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        }()

        let visible = screen.visibleFrame
        let height = min(DS.panelHeight, max(300, visible.height - 24))

        let buttonMidX: CGFloat
        let buttonMinY: CGFloat

        if let button = statusItem.button, let win = button.window {
            let screenRect = win.convertToScreen(button.bounds)
            if screenRect.width > 0 && screenRect.maxY > visible.minY + 50 {
                buttonMidX = screenRect.midX
                buttonMinY = screenRect.minY
            } else if screen.frame.contains(mouseLoc) {
                buttonMidX = mouseLoc.x
                buttonMinY = visible.maxY
            } else {
                buttonMidX = visible.maxX - width / 2 - 20
                buttonMinY = visible.maxY
            }
        } else if screen.frame.contains(mouseLoc) {
            buttonMidX = mouseLoc.x
            buttonMinY = visible.maxY
        } else {
            buttonMidX = visible.maxX - width / 2 - 20
            buttonMinY = visible.maxY
        }

        var x = buttonMidX - width / 2
        x = min(max(x, visible.minX + 10), visible.maxX - width - 10)

        var y = buttonMinY - gap - height
        y = min(max(y, visible.minY + 10), visible.maxY - height - 6)

        return NSRect(x: x.rounded(), y: y.rounded(), width: width, height: height)
    }

    // MARK: Monitores de eventos
    private func installMonitors() {
        removeMonitors()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.handleOutsideClick() }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in self?.handleOutsideClick() }
            return event
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // Esc
                Task { @MainActor in self?.close() }
                return nil
            }
            return event
        }
    }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        globalMonitor = nil
        localMonitor = nil
        keyMonitor = nil
    }

    private func handleOutsideClick() {
        guard panel.isVisible else { return }
        let location = NSEvent.mouseLocation
        if panel.frame.contains(location) { return }
        // Clique no próprio ícone é tratado pelo botão (toggle)
        if let button = statusItem.button, let win = button.window {
            let buttonScreenRect = win.convertToScreen(button.bounds)
            if buttonScreenRect.insetBy(dx: -4, dy: -4).contains(location) { return }
        }
        close()
    }
}
