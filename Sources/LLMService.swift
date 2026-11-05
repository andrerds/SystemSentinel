import Foundation

// MARK: - LLM Service (Ollama & OpenAI-compatible / OmniRoute)
actor LLMService {
    private var endpoint: String
    private var model: String
    private var apiKey: String

    init(endpoint: String, model: String = "llama3.2", apiKey: String = "") {
        self.endpoint = endpoint
        self.model = model
        self.apiKey = apiKey
    }

    func setEndpoint(_ e: String) { endpoint = e }
    func setModel(_ m: String) { model = m }
    func setApiKey(_ k: String) { apiKey = k }
    func getEndpoint() -> String { endpoint }
    func getModel() -> String { model }
    func getApiKey() -> String { apiKey }

    private var isOpenAICompatible: Bool {
        endpoint.contains("/v1") || endpoint.contains(":20128") || endpoint.contains(":20129")
    }

    func analyzeProcess(_ process: SystemProcess) async throws -> LLMAnalysis {
        let prompt = """
        Analise o processo '\(process.name)' (PID: \(process.id), CPU: \(String(format: "%.1f", process.cpuUsage))%, RAM: \(String(format: "%.0f", process.memoryUsageMB)) MB).
        Responda APENAS com JSON no formato:
        {"safeToKill": true/false, "reason": "justificativa curta de até 1 linha", "warning": "aviso se houver risco de instabilidade"}
        """

        let responseText = try await generateCompletion(prompt: prompt)
        return parse(responseText, for: process)
    }

    func diagnoseIncident(incident: SystemIncident, process: SystemProcess?) async -> (reason: String, recommendedAction: AnomalyAction, safeToAct: Bool) {
        let prompt = """
        Você é o guardião System Sentinel do macOS.
        Anomalia detectada:
        Tipo: \(incident.type.rawValue)
        Título: \(incident.title)
        Detalhes: \(incident.description)
        \(process != nil ? "Processo: \(process!.name) (PID: \(process!.id), CPU: \(String(format: "%.1f", process!.cpuUsage))%)" : "")

        Responda APENAS com JSON no formato:
        {"safeToAct": true/false, "action": "Encerrar" | "Reiniciar" | "Ignorar", "reason": "explicação curta e direta em português do que está acontecendo e por que tomar essa ação"}
        """

        do {
            let responseText = try await generateCompletion(prompt: prompt)
            let parsed = parseIncidentResponse(responseText)
            return (parsed.reason, parsed.action, parsed.safeToAct)
        } catch {
            // Heurística de fallback resiliente quando a LLM estiver offline
            return fallbackDiagnosis(for: incident, process: process)
        }
    }

    private func generateCompletion(prompt: String) async throws -> String {
        if isOpenAICompatible {
            return try await generateOpenAI(prompt: prompt)
        } else {
            return try await generateOllama(prompt: prompt)
        }
    }

    private func generateOllama(prompt: String) async throws -> String {
        guard let url = URL(string: "\(endpoint)/api/generate") else {
            throw LLMError.invalidEndpoint
        }

        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": ["temperature": 0.2, "num_predict": 300]
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LLMError.requestFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["response"] as? String else {
            throw LLMError.invalidResponse
        }

        return text
    }

    private func generateOpenAI(prompt: String) async throws -> String {
        let base = endpoint.hasSuffix("/") ? String(endpoint.dropLast()) : endpoint
        let endpointURL = base.hasSuffix("/chat/completions") ? base : "\(base)/chat/completions"
        guard let url = URL(string: endpointURL) else {
            throw LLMError.invalidEndpoint
        }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "Você é o System Sentinel do macOS. Responda estritamente em JSON puro sem markdown."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.2
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LLMError.requestFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw LLMError.invalidResponse
        }

        return text
    }

    private func parseIncidentResponse(_ text: String) -> (reason: String, action: AnomalyAction, safeToAct: Bool) {
        let pattern = #"\{[\s\S]*?\}"#
        if let range = text.range(of: pattern, options: .regularExpression) {
            let jsonStr = String(text[range])
            if let data = jsonStr.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let reason = (json["reason"] as? String) ?? "Anomalia detectada."
                let safe = (json["safeToAct"] as? Bool) ?? true
                let actionStr = (json["action"] as? String)?.lowercased() ?? ""
                let action: AnomalyAction = actionStr.contains("reinici") ? .restart :
                                           (actionStr.contains("parar") ? .stopDocker : .kill)
                return (reason, action, safe)
            }
        }
        return (String(text.prefix(120)), .kill, true)
    }

    private func fallbackDiagnosis(for incident: SystemIncident, process: SystemProcess?) -> (reason: String, recommendedAction: AnomalyAction, safeToAct: Bool) {
        switch incident.type {
        case .dockerCrashLoop:
            return ("Contêiner em ciclo contínuo de falhas. Recomenda-se reiniciar ou verificar dependências de banco.", .restart, true)
        case .runawayCommand:
            return ("Busca ou script recursivo preso consumindo disco e CPU. Seguro encerrar.", .kill, true)
        case .cpuSpike:
            if let p = process, p.name.lowercased().contains("next") || p.name.lowercased().contains("node") {
                return ("Servidor de desenvolvimento travado em alto uso de CPU. Reiniciar o processo libera o núcleo.", .restart, true)
            }
            return ("Processo em alto uso prolongado de CPU sem liberação de recursos.", .kill, true)
        case .highLoad:
            return ("Fila de processos saturando o agendador do macOS. Reduzir processos pesados.", .kill, false)
        case .orphanProcess:
            return ("Processo órfão ativo sem aplicativo pai correspondente.", .kill, true)
        case .buildInProgress:
            return ("Compilação ou empacotamento de software em andamento. É normal consumir alta CPU temporariamente.", .ignore, false)
        }
    }

    private func parse(_ text: String, for process: SystemProcess) -> LLMAnalysis {
        let pattern = #"\{[\s\S]*?\}"#
        if let range = text.range(of: pattern, options: .regularExpression) {
            let jsonStr = String(text[range])
            if let data = jsonStr.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let safe = json["safeToKill"] as? Bool,
               let reason = json["reason"] as? String {
                return LLMAnalysis(
                    processId: process.id,
                    processName: process.name,
                    safeToKill: safe,
                    reason: reason,
                    warning: json["warning"] as? String
                )
            }
        }

        let safe = text.lowercased().contains("sim") || text.lowercased().contains("seguro") || text.lowercased().contains("true")
        return LLMAnalysis(
            processId: process.id,
            processName: process.name,
            safeToKill: safe,
            reason: String(text.prefix(120)),
            warning: safe ? nil : "Pode afetar a estabilidade do sistema."
        )
    }

    func checkConnection() async -> Bool {
        if isOpenAICompatible {
            let base = endpoint.hasSuffix("/") ? String(endpoint.dropLast()) : endpoint
            guard let url = URL(string: "\(base)/models") else { return false }
            var req = URLRequest(url: url)
            if !apiKey.isEmpty {
                req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            req.timeoutInterval = 5
            do {
                let (_, response) = try await URLSession.shared.data(for: req)
                return (response as? HTTPURLResponse)?.statusCode == 200
            } catch {
                return false
            }
        } else {
            guard let url = URL(string: "\(endpoint)/api/tags") else { return false }
            var req = URLRequest(url: url)
            req.timeoutInterval = 5
            do {
                let (_, response) = try await URLSession.shared.data(for: req)
                return (response as? HTTPURLResponse)?.statusCode == 200
            } catch {
                return false
            }
        }
    }

    func fetchAvailableModels() async -> [String] {
        if isOpenAICompatible {
            let base = endpoint.hasSuffix("/") ? String(endpoint.dropLast()) : endpoint
            guard let url = URL(string: "\(base)/models") else { return [] }
            var req = URLRequest(url: url)
            if !apiKey.isEmpty {
                req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            req.timeoutInterval = 5
            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let dataArray = json["data"] as? [[String: Any]] else { return [] }
                return dataArray.compactMap { $0["id"] as? String }
            } catch {
                return []
            }
        } else {
            guard let url = URL(string: "\(endpoint)/api/tags") else { return [] }
            var req = URLRequest(url: url)
            req.timeoutInterval = 5
            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let modelsArray = json["models"] as? [[String: Any]] else { return [] }
                return modelsArray.compactMap { $0["name"] as? String }
            } catch {
                return []
            }
        }
    }

    enum LLMError: Error, LocalizedError {
        case invalidEndpoint
        case requestFailed
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint: return "Endpoint inválido."
            case .requestFailed: return "Falha na requisição ao serviço de IA."
            case .invalidResponse: return "Resposta inválida da LLM."
            }
        }
    }
}
