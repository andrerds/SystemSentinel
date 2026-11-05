import SwiftUI

struct SettingsView: View {
    private static let topAnchorID = "settings-top"

    @ObservedObject var appState: AppState

    @State private var endpointText = ""
    @State private var selectedModel = ""
    @State private var apiKeyText = ""
    @State private var isTesting = false
    @State private var testResult: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.s4) {
                        Color.clear
                            .frame(height: 0)
                            .id(Self.topAnchorID)
                        proactiveSection
                        aiSection
                        thresholdsSection
                        behaviourSection
                    }
                    .padding(DS.s4)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    proxy.scrollTo(Self.topAnchorID, anchor: .top)
                }
            }

            Hairline()

            footer
        }
        .onAppear {
            endpointText = appState.settings.llmEndpoint
            selectedModel = appState.settings.llmModel
            apiKeyText = appState.settings.llmApiKey
        }
    }

    // MARK: Guardião Proativo
    private var proactiveSection: some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            SectionLabel(text: "Guardião Proativo (Autônomo)")

            Card {
                VStack(alignment: .leading, spacing: DS.s3) {
                    Toggle(isOn: $appState.settings.enableProactiveMonitoring) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Monitoramento Proativo Ativo")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(DS.textPrimary)
                            Text("Detecta crash loops do Docker, buscas travadas e alta CPU")
                                .font(.system(size: 10.5))
                                .foregroundColor(DS.textTertiary)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(DS.accent)

                    Hairline()

                    Toggle(isOn: $appState.settings.proactiveVoiceAlerts) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Avisos por voz (falar / Cartesia PT-BR)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(DS.textPrimary)
                            Text("Anuncia por voz na hora em que o Mac começar a esquentar")
                                .font(.system(size: 10.5))
                                .foregroundColor(DS.textTertiary)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(DS.accent)
                    .disabled(!appState.settings.enableProactiveMonitoring)

                    Hairline()

                    Toggle(isOn: Binding(
                        get: { appState.isVoiceMuted },
                        set: { appState.setVoiceMuted($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Silenciar avisos de voz (Mudo)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(DS.textPrimary)
                            Text("Corta imediatamente qualquer fala atual e impede novos áudios")
                                .font(.system(size: 10.5))
                                .foregroundColor(DS.textTertiary)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(DS.bad)

                    Hairline()

                    Toggle(isOn: $appState.settings.ignoreBuildProcesses) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Ignorar processos de compilação / build")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(DS.textPrimary)
                            Text("Não interrompe nem alerta sobre swiftc, cargo, clang, vite, xcodebuild ou alto load durante compilações")
                                .font(.system(size: 10.5))
                                .foregroundColor(DS.textTertiary)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(DS.good)

                    Hairline()

                    HStack {
                        Button {
                            if appState.isSpeaking {
                                appState.stopAudio()
                            } else {
                                appState.speakAnnouncement("Teste de áudio do System Sentinel com falar.")
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: appState.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                                Text(appState.isSpeaking ? "Interromper Fala" : "Testar Voz (falar)")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(appState.isSpeaking ? DS.bad : DS.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(appState.isSpeaking ? DS.bad.opacity(0.14) : DS.accent.opacity(0.14)))
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }

                    Hairline()

                    Toggle(isOn: $appState.settings.proactiveNotifications) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Notificações interativas do macOS")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(DS.textPrimary)
                            Text("Envia banners com botões [Reiniciar] ou [Encerrar]")
                                .font(.system(size: 10.5))
                                .foregroundColor(DS.textTertiary)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(DS.accent)
                    .disabled(!appState.settings.enableProactiveMonitoring)

                    Hairline()

                    Toggle(isOn: $appState.settings.autoHealSafeAnomalies) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Auto-recuperar comandos seguros")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(DS.textPrimary)
                            Text("Mata automaticamente greps ou buscas recursivas travadas")
                                .font(.system(size: 10.5))
                                .foregroundColor(DS.textTertiary)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(DS.bad)
                    .disabled(!appState.settings.enableProactiveMonitoring)

                    Hairline()

                    sliderRow(
                        "Gatilho Load Average",
                        value: $appState.settings.loadAverageThreshold,
                        range: 2...25, step: 0.5, tint: DS.warn, suffix: "", format: "%.1f"
                    )

                    sliderRow(
                        "Gatilho CPU Processo",
                        value: $appState.settings.singleProcessCpuThreshold,
                        range: 50...150, step: 5, tint: DS.bad, suffix: "%", format: "%.0f"
                    )
                }
            }
        }
    }

    // MARK: IA (Ollama / OpenAI / OmniRoute)
    private var aiSection: some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            SectionLabel(text: "Diagnóstico com IA (Ollama / OmniRoute / OpenAI)")

            Card {
                VStack(alignment: .leading, spacing: DS.s3) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(appState.llmConnected ? DS.good : DS.textTertiary)
                            .frame(width: 6, height: 6)
                        Text(appState.llmConnected ? "Conectado" : "Offline")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(appState.llmConnected ? DS.good : DS.textSecondary)

                        Spacer()

                        if let res = testResult {
                            Text(res)
                                .font(.system(size: 10.5))
                                .foregroundColor(appState.llmConnected ? DS.good : DS.bad)
                        }

                        Button(isTesting ? "Testando…" : "Testar") { testConnection() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DS.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(DS.accent.opacity(0.14)))
                            .disabled(isTesting)
                    }

                    fieldLabel("Endpoint (Ollama: http://localhost:11434 ou OpenAI/OmniRoute)")
                    TextField("http://localhost:11434", text: $endpointText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(DS.textPrimary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: DS.rSm, style: .continuous)
                                .fill(DS.fieldFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.rSm, style: .continuous)
                                .stroke(DS.cardStroke, lineWidth: 0.75)
                        )

                    fieldLabel("API Key (Opcional para OmniRoute / OpenAI)")
                    SecureField("Chave de API", text: $apiKeyText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(DS.textPrimary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: DS.rSm, style: .continuous)
                                .fill(DS.fieldFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.rSm, style: .continuous)
                                .stroke(DS.cardStroke, lineWidth: 0.75)
                        )

                    fieldLabel("Modelo")
                    if appState.availableModels.isEmpty {
                        TextField("llama3.2 ou gpt-4o-mini", text: $selectedModel)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundColor(DS.textPrimary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: DS.rSm, style: .continuous)
                                    .fill(DS.fieldFill)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.rSm, style: .continuous)
                                    .stroke(DS.cardStroke, lineWidth: 0.75)
                            )
                    } else {
                        Picker("", selection: $selectedModel) {
                            ForEach(appState.availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .colorScheme(.dark)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    // MARK: Limites de alerta
    private var thresholdsSection: some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            SectionLabel(text: "Limites Gerais do Sistema")

            Card {
                VStack(alignment: .leading, spacing: DS.s3) {
                    sliderRow(
                        "CPU Global · atenção",
                        value: $appState.settings.cpuWarningThreshold,
                        range: 40...90, step: 1, tint: DS.warn
                    )
                    sliderRow(
                        "CPU Global · crítico",
                        value: $appState.settings.cpuCriticalThreshold,
                        range: 60...98, step: 1, tint: DS.bad
                    )
                    Hairline()
                    sliderRow(
                        "Memória · atenção",
                        value: $appState.settings.memoryWarningThreshold,
                        range: 40...90, step: 1, tint: DS.warn
                    )
                    sliderRow(
                        "Memória · crítico",
                        value: $appState.settings.memoryCriticalThreshold,
                        range: 70...98, step: 1, tint: DS.bad
                    )
                }
            }
        }
    }

    // MARK: Comportamento
    private var behaviourSection: some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            SectionLabel(text: "Comportamento da Interface")

            Card {
                VStack(alignment: .leading, spacing: DS.s3) {
                    Toggle(isOn: $appState.settings.showNotchIsland) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Exibir ilha no notch")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(DS.textPrimary)
                            Text("Mostra o visual em formato de ilha no topo da tela")
                                .font(.system(size: 10.5))
                                .foregroundColor(DS.textTertiary)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(DS.accent)

                    Hairline()

                    Toggle(isOn: $appState.settings.openOnHover) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Expandir ao passar o mouse")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(DS.textPrimary)
                            Text("A ilha abre quando o cursor repousa sobre ela")
                                .font(.system(size: 10.5))
                                .foregroundColor(DS.textTertiary)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(DS.accent)
                    .disabled(!appState.settings.showNotchIsland)

                    Group {
                        sliderRow(
                            "Atraso de abertura",
                            value: $appState.settings.hoverDwellDuration,
                            range: 0.1...0.6, step: 0.05, tint: DS.accent, suffix: "s",
                            format: "%.2f"
                        )
                        sliderRow(
                            "Tolerância de saída",
                            value: $appState.settings.exitGraceDuration,
                            range: 0.1...0.8, step: 0.05, tint: DS.accent, suffix: "s",
                            format: "%.2f"
                        )
                    }
                    .disabled(!appState.settings.showNotchIsland)
                    .opacity(appState.settings.showNotchIsland ? 1 : 0.4)
                }
            }
        }
    }

    // MARK: Rodapé
    private var footer: some View {
        HStack(spacing: DS.s2) {
            Button("Restaurar padrões") {
                appState.settings = AppSettings()
                appState.saveSettings()
                endpointText = appState.settings.llmEndpoint
                selectedModel = appState.settings.llmModel
                apiKeyText = appState.settings.llmApiKey
                testResult = nil
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(DS.textSecondary)

            Spacer()

            Button {
                appState.updateLLMEndpoint(
                    endpointText.isEmpty ? "http://localhost:11434" : endpointText,
                    model: selectedModel.isEmpty ? "llama3.2" : selectedModel,
                    apiKey: apiKeyText
                )
                appState.saveSettings()
                withAnimation(.easeOut(duration: 0.18)) {
                    appState.showSettings = false
                }
            } label: {
                Text("Salvar")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: DS.rSm, style: .continuous)
                            .fill(DS.accent)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.s4)
        .padding(.vertical, DS.s3)
    }

    // MARK: Componentes
    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundColor(DS.textSecondary)
    }

    private func sliderRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        tint: Color,
        suffix: String = "%",
        format: String = "%.0f"
    ) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 11.5))
                    .foregroundColor(DS.textSecondary)
                Spacer()
                Text(String(format: "\(format)\(suffix)", value.wrappedValue))
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundColor(tint)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: step)
                .tint(tint)
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        let endpoint = endpointText.isEmpty ? "http://localhost:11434" : endpointText
        appState.updateLLMEndpoint(
            endpoint,
            model: selectedModel.isEmpty ? "llama3.2" : selectedModel,
            apiKey: apiKeyText
        )
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            isTesting = false
            testResult = appState.llmConnected ? "Conectado" : "Offline"
        }
    }
}
