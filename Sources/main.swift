import SwiftUI
import AppKit
import Combine

// MARK: - App Entry
struct SystemSentinelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    // Painel da barra de menus (entrada principal)
    private var statusItem: NSStatusItem?
    private var menuBarController: MenuBarPanelController?

    // Ilha no notch (opcional, desligada por padrão)
    private var panels: [NSScreen: DynamicIslandPanel] = [:]
    private var notchEnabled = false
    private var mouseTrackingTask: Task<Void, Never>?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var expansionCancellable: AnyCancellable?

    private var cancellables = Set<AnyCancellable>()

    // Indicador de alerta no ícone da barra (tint + pulsar)
    private var attentionTask: Task<Void, Never>?
    private var acknowledgedLevel: AlertLevel = .normal
    private var currentLevel: AlertLevel = .normal

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupStatusBar()
        setupMenuBarPanel()
        setupScreenObserver()
        observeAlerts()
        observeNotchSetting()

        setNotchIslandEnabled(appState.settings.showNotchIsland)

        // Abre o painel automaticamente ao iniciar para visibilidade imediata
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.appState.isPanelOpen = true
        }
    }

    // MARK: - Barra de menus
    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = item.button {
            let image = NSImage(systemSymbolName: "shield.lefthalf.filled", accessibilityDescription: "System Sentinel")
            image?.isTemplate = true
            button.image = image
            button.title = " Sentinel"
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "System Sentinel — clique para abrir"
        }

        self.statusItem = item
    }

    private func setupMenuBarPanel() {
        guard let statusItem else { return }
        menuBarController = MenuBarPanelController(appState: appState, statusItem: statusItem)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || (event?.modifierFlags.contains(.control) ?? false)

        if isRightClick {
            showStatusMenu()
        } else {
            menuBarController?.toggle()
        }
    }

    private func showStatusMenu() {
        guard let statusItem else { return }
        statusItem.menu = buildStatusMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Abrir painel", action: #selector(openPanel), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let notchItem = NSMenuItem(title: "Exibir ilha no notch", action: #selector(toggleNotchIsland), keyEquivalent: "")
        notchItem.target = self
        notchItem.state = appState.settings.showNotchIsland ? .on : .off
        menu.addItem(notchItem)

        let pinItem = NSMenuItem(title: "Fixar ilha", action: #selector(togglePin), keyEquivalent: "")
        pinItem.target = self
        pinItem.state = appState.isPinned ? .on : .off
        pinItem.isEnabled = appState.settings.showNotchIsland
        menu.addItem(pinItem)

        menu.addItem(.separator())

        let muteTitle = appState.isVoiceMuted ? "Reativar avisos por voz" : "Silenciar avisos por voz (Mudo)"
        let muteItem = NSMenuItem(title: muteTitle, action: #selector(toggleVoiceMute), keyEquivalent: "m")
        muteItem.target = self
        muteItem.state = appState.isVoiceMuted ? .on : .off
        menu.addItem(muteItem)

        if appState.isSpeaking {
            let stopAudioItem = NSMenuItem(title: "Interromper fala agora", action: #selector(stopAudioNow), keyEquivalent: "")
            stopAudioItem.target = self
            menu.addItem(stopAudioItem)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Configurações…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Encerrar", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Alerta no ícone (brilho/piscada em vez de abrir a interface)
    private func observeAlerts() {
        Publishers.CombineLatest(appState.$metrics, appState.$settings)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.refreshAlertIndicator() }
            .store(in: &cancellables)

        appState.$isPanelOpen
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] open in
                guard let self else { return }
                // Abrir o painel conta como "ciente do alerta"
                if open { self.acknowledgedLevel = self.appState.alertLevel }
                self.refreshAlertIndicator()
            }
            .store(in: &cancellables)
    }

    private func refreshAlertIndicator() {
        let level = appState.alertLevel
        if level == .normal { acknowledgedLevel = .normal }
        currentLevel = level

        if level != .normal && level > acknowledgedLevel {
            startAttention()
        } else {
            stopAttention()
        }
    }

    /// Escurece a cor do alerta por um fator (1 = cor cheia). Necessário porque o
    /// ícone da barra ignora o canal alpha do tint — a piscada precisa ser na cor.
    private func shaded(_ color: NSColor, factor: CGFloat) -> NSColor {
        guard let c = color.usingColorSpace(.deviceRGB) else { return color }
        return NSColor(deviceRed: c.redComponent * factor,
                       green: c.greenComponent * factor,
                       blue: c.blueComponent * factor,
                       alpha: 1)
    }

    /// Pisca o ícone entre a cor do alerta e um tom bem apagado. Nenhuma janela é
    /// aberta: o aviso acontece só na barra de menus.
    private func applyTint(_ step: Int) {
        guard let button = statusItem?.button else { return }

        let base: NSColor?
        switch currentLevel {
        case .normal: base = nil
        case .warning: base = NSColor(DS.warn)
        case .critical: base = NSColor(DS.bad)
        }

        guard let base else {
            button.contentTintColor = nil
            return
        }

        let factors: [CGFloat] = [1.0, 0.5, 0.12, 0.5]
        button.contentTintColor = shaded(base, factor: factors[step % factors.count])
        // Garante que o item seja redesenhado a cada passo da piscada.
        button.needsDisplay = true
    }

    private func startAttention() {
        guard attentionTask == nil else { return }
        let stepDuration: TimeInterval = currentLevel == .critical ? 0.22 : 0.32

        attentionTask = Task { @MainActor in
            var step = 0
            while !Task.isCancelled {
                applyTint(step)
                step += 1
                try? await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
            }
        }
    }

    private func stopAttention() {
        attentionTask?.cancel()
        attentionTask = nil
        applyTint(0)
    }

    // MARK: - Ilha no notch (opcional)
    private func observeNotchSetting() {
        appState.$settings
            .map(\.showNotchIsland)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.setNotchIslandEnabled(enabled)
            }
            .store(in: &cancellables)
    }

    private func setNotchIslandEnabled(_ enabled: Bool) {
        guard enabled != notchEnabled else { return }
        notchEnabled = enabled

        if enabled {
            setupWindows()
            observeExpansion()
            startMouseTracking()
            setupClickMonitors()
        } else {
            mouseTrackingTask?.cancel()
            mouseTrackingTask = nil

            if let monitor = globalClickMonitor { NSEvent.removeMonitor(monitor) }
            if let monitor = localClickMonitor { NSEvent.removeMonitor(monitor) }
            globalClickMonitor = nil
            localClickMonitor = nil

            expansionCancellable?.cancel()
            expansionCancellable = nil

            for (_, panel) in panels { panel.close() }
            panels.removeAll()

            appState.setExpanded(false)
        }
    }

    private func setupWindows() {
        for screen in NSScreen.screens where panels[screen] == nil {
            let initialFrame = computeFrame(for: screen, expanded: appState.isExpanded)
            let panel = DynamicIslandPanel(contentRect: initialFrame)
            panel.setFrame(initialFrame, display: false)

            let rootView = DynamicIslandContainerView(appState: appState, screen: screen)
            let host = FirstMouseHostingView(rootView: AnyView(rootView))
            host.sizingOptions = []

            panel.contentView = host
            panel.orderFrontRegardless()
            panels[screen] = panel
        }
    }

    private func isMouseInNotchArea(_ loc: NSPoint, on screen: NSScreen) -> Bool {
        let expanded = appState.isExpanded
        let isNotch = NotchGeometry.isNotchDisplay(screen)
        let size = expanded ? NotchGeometry.expandedSize(for: screen) : NotchGeometry.closedSize(for: screen)
        let topBleed = isNotch ? NotchGeometry.notchTopScreenBleedAmount : 0
        let height = size.height + topBleed
        let width = size.width

        let marginX: CGFloat = expanded ? 14 : 18
        let marginYBottom: CGFloat = expanded ? 16 : 24
        let marginYTop: CGFloat = 8

        let minX = screen.frame.midX - (width / 2) - marginX
        let maxX = screen.frame.midX + (width / 2) + marginX
        let minY = screen.frame.maxY - height - marginYBottom
        let maxY = screen.frame.maxY + topBleed + marginYTop

        return loc.x >= minX && loc.x <= maxX && loc.y >= minY && loc.y <= maxY
    }

    private func targetScreen(for loc: NSPoint) -> NSScreen {
        NSScreen.screens.first { loc.x >= $0.frame.minX && loc.x <= $0.frame.maxX } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func startMouseTracking() {
        mouseTrackingTask?.cancel()
        mouseTrackingTask = Task { @MainActor in
            var hoverStartTime: Date?
            var exitStartTime: Date?

            while !Task.isCancelled {
                let loc = NSEvent.mouseLocation
                let screen = self.targetScreen(for: loc)
                let isInside = self.isMouseInNotchArea(loc, on: screen)

                if isInside {
                    exitStartTime = nil
                    if hoverStartTime == nil { hoverStartTime = Date() }
                    let dwell = Date().timeIntervalSince(hoverStartTime!)
                    let requiredDwell = self.appState.settings.hoverDwellDuration
                    if dwell >= requiredDwell && !self.appState.isExpanded && self.appState.settings.openOnHover {
                        self.appState.setExpanded(true)
                    }
                } else {
                    hoverStartTime = nil
                    if self.appState.isExpanded && !self.appState.openedByClick && !self.appState.isPinned && !self.appState.showSettings {
                        if exitStartTime == nil { exitStartTime = Date() }
                        let exitDwell = Date().timeIntervalSince(exitStartTime!)
                        if exitDwell >= self.appState.settings.exitGraceDuration {
                            self.appState.setExpanded(false)
                            exitStartTime = nil
                        }
                    } else {
                        exitStartTime = nil
                    }
                }

                let interval: UInt64 = self.appState.isExpanded ? 50_000_000 : 35_000_000
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    private func setupClickMonitors() {
        let handleClick: (NSPoint) -> Void = { [weak self] loc in
            guard let self else { return }
            let screen = self.targetScreen(for: loc)
            let inNotch = self.isMouseInNotchArea(loc, on: screen)

            if inNotch {
                if !self.appState.isExpanded {
                    self.appState.setExpanded(true, byClick: true)
                } else {
                    self.appState.openedByClick = true
                }
            } else if self.appState.isExpanded && !self.appState.isPinned && !self.appState.showSettings {
                self.appState.setExpanded(false)
            }
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { _ in
            Task { @MainActor in handleClick(NSEvent.mouseLocation) }
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            Task { @MainActor in handleClick(NSEvent.mouseLocation) }
            return event
        }
    }

    private func observeExpansion() {
        expansionCancellable?.cancel()
        expansionCancellable = appState.$isExpanded
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] expanded in
                guard let self else { return }
                for (screen, panel) in self.panels {
                    let targetRect = self.computeFrame(for: screen, expanded: expanded)
                    guard panel.frame != targetRect else { continue }
                    panel.setFrame(targetRect, display: true)
                    panel.orderFrontRegardless()
                }
            }
    }

    private func computeFrame(for screen: NSScreen, expanded: Bool) -> NSRect {
        let isNotch = NotchGeometry.isNotchDisplay(screen)
        let topBleed = isNotch ? NotchGeometry.notchTopScreenBleedAmount : 0
        let topOffset = isNotch ? 0 : NotchGeometry.dynamicIslandTopOffset

        let baseSize = expanded ? NotchGeometry.expandedSize(for: screen) : NotchGeometry.closedSize(for: screen)
        let screenFrame = screen.frame
        let windowWidth = min(baseSize.width, screenFrame.width).rounded()
        let windowHeight = (baseSize.height + topBleed).rounded()

        let x = (screenFrame.midX - (windowWidth / 2)).rounded()
        let y = (screenFrame.maxY + topBleed - topOffset - windowHeight).rounded()

        return NSRect(x: x, y: y, width: windowWidth, height: windowHeight)
    }

    private func setupScreenObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.notchEnabled else { return }
                let currentScreens = Set(NSScreen.screens)
                for (screen, panel) in self.panels where !currentScreens.contains(screen) {
                    panel.close()
                    self.panels.removeValue(forKey: screen)
                }
                self.setupWindows()
                for (screen, panel) in self.panels {
                    panel.setFrame(self.computeFrame(for: screen, expanded: self.appState.isExpanded), display: true)
                }
            }
        }
    }

    // MARK: - Menu actions
    @objc private func openPanel() {
        appState.isPanelOpen = true
    }

    @objc private func toggleNotchIsland() {
        appState.settings.showNotchIsland.toggle()
    }

    @objc private func togglePin() {
        appState.isPinned.toggle()
        if appState.isPinned {
            appState.setExpanded(true)
        }
    }

    @objc private func toggleVoiceMute() {
        appState.toggleVoiceMute()
    }

    @objc private func stopAudioNow() {
        appState.stopAudio()
    }

    @objc private func openSettings() {
        appState.showSettings = true
        appState.isPanelOpen = true
        menuBarController?.present()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// Top-level entry execution
SystemSentinelApp.main()
