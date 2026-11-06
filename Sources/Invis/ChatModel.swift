import SwiftUI
import Foundation

struct ReasoningChoice: Identifiable, Hashable {
    let id: String
    let description: String

    var title: String {
        switch id {
        case "low": "Быстро"
        case "medium": "Сбалансированно"
        case "high": "Глубоко"
        case "xhigh": "Очень глубоко"
        case "max": "Максимум"
        case "ultra": "Ультра"
        default: id.capitalized
        }
    }
}

struct CodexModel: Identifiable, Hashable {
    let id: String
    let name: String
    let defaultEffort: String
    let efforts: [ReasoningChoice]
    let isDefault: Bool
}

struct ChatSession: Identifiable, Hashable {
    let id: String
    var title: String
    var cwd: String
    var modelID: String
    var effort: String
    var updatedAt: TimeInterval
}

struct ChatMessage: Identifiable, Equatable {
    enum Kind: Equatable { case user, assistant, progress, error }
    let id: String
    let kind: Kind
    var text: String
    var isActive: Bool

    init(id: String = UUID().uuidString, kind: Kind, text: String, isActive: Bool = false) {
        self.id = id
        self.kind = kind
        self.text = text
        self.isActive = isActive
    }
}

struct AgentQuestion: Identifiable {
    struct Option: Identifiable {
        let label: String
        let description: String
        var id: String { label }
    }
    let id: String
    let header: String
    let question: String
    let options: [Option]
    let isSecret: Bool
}

struct PendingQuestion: Identifiable {
    let id = UUID()
    let rpcID: Any
    let questions: [AgentQuestion]
}

struct PendingApproval: Identifiable {
    let id = UUID()
    let rpcID: Any
    let command: String
    let cwd: String
    let reason: String
    let method: String
}

struct CodexUsage {
    var plan = "ChatGPT"
    var shortPercent: Int?
    var shortWindowMinutes: Int?
    var shortResetsAt: TimeInterval?
    var longPercent: Int?
    var longWindowMinutes: Int?
    var longResetsAt: TimeInterval?
}

@MainActor
final class ChatModel: ObservableObject {
    @Published var prompt = ""
    @Published var messages: [ChatMessage] = []
    @Published var sessions: [ChatSession] = []
    @Published var activeThreadID: String?
    @Published var projectPath: String?
    @Published var models: [CodexModel] = []
    @Published var selectedModelID = ""
    @Published var selectedEffort = "low"
    @Published var usage = CodexUsage()
    @Published var status = "Подключаю Codex…"
    @Published var isBusy = false
    @Published var isConnected = false
    @Published var pendingQuestion: PendingQuestion?
    @Published var pendingApproval: PendingApproval?
    @Published var questionAnswers: [String: String] = [:]

    private let wire = CodexWire()
    private var nextRequestID = 1
    private var pendingRequests: [String: ([String: Any]?, String?) -> Void] = [:]
    private var messagesByThread: [String: [ChatMessage]] = [:]
    private var progressMessageIDs: [String: String] = [:]
    private var activeAssistantMessageIDs: [String: String] = [:]
    private var hasStarted = false
    private var catalogDefaultID: String?
    private let defaults = UserDefaults.standard

    var currentProjectName: String { projectPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Выбрать проект" }
    var selectedModel: CodexModel? { models.first { $0.id == selectedModelID } }
    var selectedEffortTitle: String { selectedModel?.efforts.first { $0.id == selectedEffort }?.title ?? selectedEffort.capitalized }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        projectPath = defaults.string(forKey: "inviz.projectPath")
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop").path
        defaults.set(projectPath, forKey: "inviz.projectPath")
        selectedModelID = defaults.string(forKey: "inviz.modelID") ?? ""
        selectedEffort = defaults.string(forKey: "inviz.reasoningEffort") ?? "low"
        activeThreadID = defaults.string(forKey: "inviz.activeThreadID")

        wire.onMessage = { [weak self] message in self?.handleRPC(message) }
        wire.onFailure = { [weak self] message in
            guard let self else { return }
            self.isConnected = false
            self.status = message
            self.append(ChatMessage(kind: .error, text: message))
        }

        do {
            try wire.start()
            request("initialize", params: [
                "clientInfo": ["name": "invis", "title": "Invis", "version": Self.appVersion],
                "capabilities": ["experimentalApi": true]
            ]) { [weak self] result, error in
                guard let self else { return }
                if let error { self.setConnectionError(error); return }
                self.wire.send(["method": "initialized", "params": [:]])
                self.isConnected = true
                self.status = "Codex подключён"
                self.loadModels()
                self.refreshUsage()
                self.refreshSessions(restoreActive: true)
            }
        } catch {
            setConnectionError(error.localizedDescription)
        }
    }

    func newChat() {
        activeThreadID = nil
        messages = []
        questionAnswers = [:]
        pendingQuestion = nil
        pendingApproval = nil
        isBusy = false
        status = projectPath == nil ? "Выберите папку проекта" : "Новый чат · готов к запросу"
        defaults.removeObject(forKey: "inviz.activeThreadID")
        if selectedModelID.isEmpty, let first = models.first(where: \.isDefault) ?? models.first {
            selectModel(first.id)
        }
    }

    func selectModel(_ id: String) {
        guard let model = models.first(where: { $0.id == id }) else { return }
        selectedModelID = model.id
        if !model.efforts.contains(where: { $0.id == selectedEffort }) { selectedEffort = model.defaultEffort }
        defaults.set(selectedModelID, forKey: "inviz.modelID")
        defaults.set(selectedEffort, forKey: "inviz.reasoningEffort")
        if let activeThreadID, let index = sessions.firstIndex(where: { $0.id == activeThreadID }) {
            sessions[index].modelID = selectedModelID
            sessions[index].effort = selectedEffort
        }
    }

    func selectEffort(_ id: String) {
        guard selectedModel?.efforts.contains(where: { $0.id == id }) == true else { return }
        selectedEffort = id
        defaults.set(id, forKey: "inviz.reasoningEffort")
        if let activeThreadID, let index = sessions.firstIndex(where: { $0.id == activeThreadID }) {
            sessions[index].effort = id
        }
    }

    func chooseProject() {
        let panel = NSOpenPanel()
        panel.title = "Выбрать рабочую папку"
        panel.prompt = "Использовать папку"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if let projectPath { panel.directoryURL = URL(fileURLWithPath: projectPath) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        projectPath = url.path
        defaults.set(url.path, forKey: "inviz.projectPath")
        status = "Папка сохранена · \(url.lastPathComponent)"
        if let activeThreadID, let index = sessions.firstIndex(where: { $0.id == activeThreadID }) {
            sessions[index].cwd = url.path
        }
    }

    func selectSession(_ session: ChatSession) {
        guard !isBusy else { return }
        activeThreadID = session.id
        projectPath = session.cwd
        selectedModelID = models.contains(where: { $0.id == session.modelID }) ? session.modelID : (catalogDefaultID ?? models.first?.id ?? "")
        if let model = selectedModel { selectedEffort = model.efforts.contains(where: { $0.id == session.effort }) ? session.effort : model.defaultEffort }
        defaults.set(session.id, forKey: "inviz.activeThreadID")
        defaults.set(session.cwd, forKey: "inviz.projectPath")
        defaults.set(selectedModelID, forKey: "inviz.modelID")
        defaults.set(selectedEffort, forKey: "inviz.reasoningEffort")
        messages = messagesByThread[session.id] ?? []
        status = "Загружаю переписку…"

        request("thread/resume", params: ["threadId": session.id, "excludeTurns": true]) { [weak self] result, error in
            guard let self else { return }
            if let error {
                if Self.isMissingThreadError(error) {
                    self.handleUnavailableSession(session)
                } else {
                    self.status = "Не удалось открыть чат"
                    self.append(ChatMessage(kind: .error, text: error))
                }
                return
            }
            if let resumed = result?["thread"] as? [String: Any] {
                let threadModel = result?["model"] as? String ?? (resumed["model"] as? String ?? session.modelID)
                let effort = result?["reasoningEffort"] as? String ?? session.effort
                if let index = self.sessions.firstIndex(where: { $0.id == session.id }) {
                    self.sessions[index].modelID = threadModel
                    self.sessions[index].effort = effort
                }
                if self.models.contains(where: { $0.id == threadModel }) { self.selectModel(threadModel) }
                if self.selectedModel?.efforts.contains(where: { $0.id == effort }) == true { self.selectEffort(effort) }
            }
            self.request("thread/turns/list", params: ["threadId": session.id, "limit": 100, "sortDirection": "asc", "itemsView": "full"]) { page, pageError in
                if let pageError {
                    if Self.isMissingThreadError(pageError) {
                        self.handleUnavailableSession(session)
                    } else {
                        self.status = "Не удалось загрузить историю"
                        self.append(ChatMessage(kind: .error, text: pageError))
                    }
                    return
                }
                let loaded = self.messagesFromTurns(page?["data"] as? [[String: Any]] ?? [])
                self.messagesByThread[session.id] = loaded
                self.messages = loaded
                self.status = "Готов к работе"
            }
        }
    }

    func send() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        guard isConnected else {
            append(ChatMessage(kind: .error, text: "Codex ещё подключается. Попробуйте отправить запрос через несколько секунд."))
            return
        }
        guard let projectPath else {
            append(ChatMessage(kind: .error, text: "Выберите рабочую папку внизу окна. Она сохранится для следующих запусков."))
            return
        }
        guard let model = selectedModel else {
            append(ChatMessage(kind: .error, text: "Список моделей ещё загружается."))
            return
        }

        prompt = ""
        append(ChatMessage(kind: .user, text: text))
        isBusy = true
        status = "Отправляю запрос · \(model.name) · \(selectedEffortTitle)"

        if let activeThreadID {
            startTurn(threadID: activeThreadID, text: text, cwd: projectPath, model: model.id, effort: selectedEffort)
            return
        }

        request("thread/start", params: [
            "model": model.id,
            "cwd": projectPath,
            "sandbox": "danger-full-access",
            "approvalPolicy": "never"
        ]) { [weak self] result, error in
            guard let self else { return }
            if let error { self.failTurn(error); return }
            guard let thread = result?["thread"] as? [String: Any], let threadID = thread["id"] as? String else {
                self.failTurn("Codex не вернул идентификатор нового чата."); return
            }
            self.activeThreadID = threadID
            self.defaults.set(threadID, forKey: "inviz.activeThreadID")
            let session = ChatSession(id: threadID, title: String(text.prefix(56)), cwd: projectPath, modelID: model.id, effort: self.selectedEffort, updatedAt: Date().timeIntervalSince1970)
            self.sessions.insert(session, at: 0)
            self.messagesByThread[threadID] = self.messages
            self.startTurn(threadID: threadID, text: text, cwd: projectPath, model: model.id, effort: self.selectedEffort)
        }
    }

    func interrupt() {
        guard let activeThreadID, isBusy else { return }
        request("turn/interrupt", params: ["threadId": activeThreadID]) { _, _ in }
    }

    func answerQuestion() {
        guard let question = pendingQuestion else { return }
        var answers: [String: Any] = [:]
        for item in question.questions {
            let answer = questionAnswers[item.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            answers[item.id] = ["answers": answer.isEmpty ? [] : [answer]]
        }
        wire.send(["id": question.rpcID, "result": ["answers": answers]])
        pendingQuestion = nil
        questionAnswers = [:]
        status = "Ответ отправлен Codex"
    }

    func answerApproval(_ decision: String) {
        guard let approval = pendingApproval else { return }
        wire.send(["id": approval.rpcID, "result": ["decision": decision]])
        pendingApproval = nil
        status = decision == "decline" ? "Действие отклонено" : "Действие разрешено"
    }

    func refreshUsage() {
        request("account/rateLimits/read", params: ["excludeResetCreditDetails": true]) { [weak self] result, _ in
            guard let self, let result else { return }
            self.updateUsage(result)
        }
    }

    private static var appVersion: String {
        (try? String(contentsOfFile: Bundle.main.resourceURL?.appendingPathComponent("VERSION").path ?? "", encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "2.0.0"
    }

    private func loadModels() {
        request("model/list", params: ["limit": 100, "includeHidden": false]) { [weak self] result, error in
            guard let self else { return }
            if let error { self.status = "Не удалось загрузить модели: \(error)"; return }
            let rows = result?["data"] as? [[String: Any]] ?? []
            self.models = rows.compactMap { row in
                guard let id = row["id"] as? String else { return nil }
                let efforts = (row["supportedReasoningEfforts"] as? [[String: Any]] ?? []).compactMap { item -> ReasoningChoice? in
                    guard let name = item["reasoningEffort"] as? String else { return nil }
                    return ReasoningChoice(id: name, description: item["description"] as? String ?? "")
                }
                return CodexModel(
                    id: id,
                    name: row["displayName"] as? String ?? id,
                    defaultEffort: row["defaultReasoningEffort"] as? String ?? efforts.first?.id ?? "medium",
                    efforts: efforts,
                    isDefault: row["isDefault"] as? Bool ?? false
                )
            }
            self.catalogDefaultID = self.models.first(where: \.isDefault)?.id
            if !self.models.contains(where: { $0.id == self.selectedModelID }) {
                self.selectModel(self.catalogDefaultID ?? self.models.first?.id ?? "")
            } else if let model = self.selectedModel, !model.efforts.contains(where: { $0.id == self.selectedEffort }) {
                self.selectEffort(model.defaultEffort)
            }
            self.status = "Codex подключён · \(self.models.count) моделей доступны"
        }
    }

    private func refreshSessions(restoreActive: Bool) {
        request("thread/list", params: [
            "limit": 100,
            "sortKey": "updated_at",
            "sortDirection": "desc",
            "sourceKinds": ["appServer", "exec", "cli"]
        ]) { [weak self] result, error in
            guard let self else { return }
            if let error { self.status = "История чатов недоступна: \(error)"; return }
            let rows = result?["data"] as? [[String: Any]] ?? []
            self.sessions = rows.compactMap { row in
                guard let id = row["id"] as? String else { return nil }
                let preview = (row["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    ?? (row["preview"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    ?? "Новый чат"
                return ChatSession(
                    id: id,
                    title: String(preview.prefix(56)),
                    cwd: row["cwd"] as? String ?? "",
                    modelID: row["model"] as? String ?? self.catalogDefaultID ?? "",
                    effort: row["reasoningEffort"] as? String ?? "medium",
                    updatedAt: row["updatedAt"] as? TimeInterval ?? 0
                )
            }
            if restoreActive, let saved = self.defaults.string(forKey: "inviz.activeThreadID") {
                let session = self.sessions.first(where: { $0.id == saved }) ?? ChatSession(
                    id: saved,
                    title: "Продолжить чат",
                    cwd: self.projectPath ?? "",
                    modelID: self.selectedModelID,
                    effort: self.selectedEffort,
                    updatedAt: 0
                )
                self.selectSession(session)
            } else if self.activeThreadID == nil {
                self.status = self.projectPath == nil ? "Выберите папку проекта" : "Готов к работе"
            }
        }
    }

    private func startTurn(threadID: String, text: String, cwd: String, model: String, effort: String, recoverMissingThread: Bool = true) {
        request("turn/start", params: [
            "threadId": threadID,
            "input": [["type": "text", "text": text]],
            "cwd": cwd,
            "model": model,
            "effort": effort,
            "summary": "detailed",
            "approvalPolicy": "never",
            "sandboxPolicy": ["type": "dangerFullAccess"]
        ]) { [weak self] _, error in
            guard let self else { return }
            if let error {
                if recoverMissingThread, Self.isMissingThreadError(error) {
                    self.recoverFromMissingThread(threadID: threadID, text: text, cwd: cwd, model: model, effort: effort)
                } else {
                    self.failTurn(error)
                }
                return
            }
            self.status = "Codex работает · \(self.selectedModel?.name ?? model) · \(self.selectedEffortTitle)"
        }
    }

    private func recoverFromMissingThread(threadID: String, text: String, cwd: String, model: String, effort: String) {
        sessions.removeAll { $0.id == threadID }
        messagesByThread.removeValue(forKey: threadID)
        activeThreadID = nil
        defaults.removeObject(forKey: "inviz.activeThreadID")
        status = "Старый чат недоступен · создаю новый"
        append(ChatMessage(kind: .progress, text: "Codex не нашёл сохранённый чат. Переношу запрос в новую переписку."))

        request("thread/start", params: [
            "model": model,
            "cwd": cwd,
            "sandbox": "danger-full-access",
            "approvalPolicy": "never"
        ]) { [weak self] result, error in
            guard let self else { return }
            if let error { self.failTurn(error); return }
            guard let thread = result?["thread"] as? [String: Any], let replacementID = thread["id"] as? String else {
                self.failTurn("Не удалось создать новый чат для повторного запроса.")
                return
            }

            self.activeThreadID = replacementID
            self.defaults.set(replacementID, forKey: "inviz.activeThreadID")
            let session = ChatSession(
                id: replacementID,
                title: String(text.prefix(56)),
                cwd: cwd,
                modelID: model,
                effort: effort,
                updatedAt: Date().timeIntervalSince1970
            )
            self.sessions.insert(session, at: 0)
            self.messagesByThread[replacementID] = self.messages
            self.startTurn(threadID: replacementID, text: text, cwd: cwd, model: model, effort: effort, recoverMissingThread: false)
        }
    }

    private func handleUnavailableSession(_ session: ChatSession) {
        sessions.removeAll { $0.id == session.id }
        messagesByThread.removeValue(forKey: session.id)
        activeThreadID = nil
        defaults.removeObject(forKey: "inviz.activeThreadID")
        messages = []
        status = "Эта переписка больше недоступна · начните новый чат"
        append(ChatMessage(kind: .error, text: "Codex больше не находит эту переписку. Создайте новый чат и отправьте запрос повторно."))
    }

    private static func isMissingThreadError(_ error: String) -> Bool {
        error.localizedCaseInsensitiveContains("thread not found")
    }

    private func request(_ method: String, params: [String: Any], completion: @escaping ([String: Any]?, String?) -> Void) {
        let id = nextRequestID
        nextRequestID += 1
        pendingRequests[String(id)] = completion
        wire.send(["id": id, "method": method, "params": params])
    }

    private func handleRPC(_ message: [String: Any]) {
        if let method = message["method"] as? String {
            let params = message["params"] as? [String: Any] ?? [:]
            if let id = message["id"] {
                handleServerRequest(method, id: id, params: params)
            } else {
                handleNotification(method, params: params)
            }
            return
        }
        guard let id = message["id"] else { return }
        let key = Self.idKey(id)
        let callback = pendingRequests.removeValue(forKey: key)
        if let error = message["error"] as? [String: Any] {
            callback?(nil, error["message"] as? String ?? "Ошибка Codex")
        } else {
            callback?(message["result"] as? [String: Any], nil)
        }
    }

    private func handleNotification(_ method: String, params: [String: Any]) {
        switch method {
        case "item/agentMessage/delta":
            guard params["threadId"] as? String == activeThreadID,
                  let itemID = params["itemId"] as? String,
                  let delta = params["delta"] as? String else { return }
            appendAssistantDelta(itemID: itemID, delta: delta)
        case "item/plan/delta":
            guard params["threadId"] as? String == activeThreadID,
                  let itemID = params["itemId"] as? String,
                  let delta = params["delta"] as? String else { return }
            appendProgressDelta(itemID: itemID, delta: delta)
        case "item/commandExecution/outputDelta":
            guard params["threadId"] as? String == activeThreadID,
                  let itemID = params["itemId"] as? String,
                  let delta = params["delta"] as? String else { return }
            appendProgressDelta(itemID: itemID, delta: delta)
        case "item/started":
            handleItemStarted(params)
        case "item/completed":
            handleItemCompleted(params)
        case "turn/started":
            status = "Codex начал работу"
        case "turn/completed":
            isBusy = false
            let turn = params["turn"] as? [String: Any] ?? [:]
            if let error = turn["error"] as? [String: Any], let text = error["message"] as? String {
                append(ChatMessage(kind: .error, text: text))
                status = "Codex завершил ход с ошибкой"
            } else {
                status = "Готов к работе"
            }
            saveActiveMessages()
            refreshUsage()
            refreshSessions(restoreActive: false)
        case "turn/plan/updated":
            guard params["threadId"] as? String == activeThreadID,
                  let explanation = params["explanation"] as? String,
                  !explanation.isEmpty else { return }
            append(ChatMessage(kind: .progress, text: "План работы\n\(explanation)"))
        case "account/rateLimits/updated":
            if let limits = params["rateLimits"] as? [String: Any] { updateUsage(["rateLimits": limits]) }
        case "account/updated":
            status = "Авторизация Codex обновлена"
        case "warning", "configWarning":
            if let message = params["message"] as? String, !message.isEmpty { append(ChatMessage(kind: .progress, text: message)) }
        default:
            break
        }
    }

    private func handleItemStarted(_ params: [String: Any]) {
        guard params["threadId"] as? String == activeThreadID,
              let item = params["item"] as? [String: Any],
              let id = item["id"] as? String,
              let type = item["type"] as? String else { return }
        if type == "agentMessage" {
            activeAssistantMessageIDs[id] = id
            append(ChatMessage(id: id, kind: .assistant, text: "", isActive: true))
            return
        }
        let title: String
        let detail: String
        switch type {
        case "plan": title = "Планирую изменения"; detail = item["text"] as? String ?? ""
        case "commandExecution": title = "Выполняю команду"; detail = item["command"] as? String ?? ""
        case "fileChange": title = "Изменяю файлы"; detail = Self.fileChangeSummary(item)
        case "mcpToolCall": title = "Использую подключённый инструмент"; detail = item["tool"] as? String ?? ""
        case "webSearch": title = "Ищу в интернете"; detail = ""
        case "reasoning": title = "Анализирую запрос"; detail = ""
        default: title = "Выполняю шаг"; detail = type
        }
        let messageID = UUID().uuidString
        progressMessageIDs[id] = messageID
        append(ChatMessage(id: messageID, kind: .progress, text: [title, detail].filter { !$0.isEmpty }.joined(separator: "\n"), isActive: true))
    }

    private func handleItemCompleted(_ params: [String: Any]) {
        guard params["threadId"] as? String == activeThreadID,
              let item = params["item"] as? [String: Any],
              let id = item["id"] as? String,
              let type = item["type"] as? String else { return }
        if type == "agentMessage" {
            let text = item["text"] as? String ?? ""
            let messageID = activeAssistantMessageIDs.removeValue(forKey: id) ?? id
            mutateMessage(messageID) { current in
                if current.text.isEmpty { current.text = text }
                current.isActive = false
            }
            saveActiveMessages()
        } else if let messageID = progressMessageIDs.removeValue(forKey: id) {
            mutateMessage(messageID) { $0.isActive = false }
        }
    }

    private func handleServerRequest(_ method: String, id: Any, params: [String: Any]) {
        switch method {
        case "item/tool/requestUserInput":
            let questions = (params["questions"] as? [[String: Any]] ?? []).compactMap { row -> AgentQuestion? in
                guard let question = row["question"] as? String, let questionID = row["id"] as? String else { return nil }
                let options = (row["options"] as? [[String: Any]] ?? []).compactMap { option -> AgentQuestion.Option? in
                    guard let label = option["label"] as? String else { return nil }
                    return AgentQuestion.Option(label: label, description: option["description"] as? String ?? "")
                }
                return AgentQuestion(id: questionID, header: row["header"] as? String ?? "Вопрос", question: question, options: options, isSecret: row["isSecret"] as? Bool ?? false)
            }
            pendingQuestion = PendingQuestion(rpcID: id, questions: questions)
            questionAnswers = [:]
            status = "Codex ждёт вашего ответа"
        case "item/commandExecution/requestApproval":
            pendingApproval = PendingApproval(
                rpcID: id,
                command: params["command"] as? String ?? "Команда Codex",
                cwd: params["cwd"] as? String ?? "",
                reason: params["reason"] as? String ?? "Codex запросил подтверждение",
                method: method
            )
            status = "Нужно подтвердить команду"
        case "item/fileChange/requestApproval":
            pendingApproval = PendingApproval(
                rpcID: id,
                command: Self.fileChangeSummary(params),
                cwd: "",
                reason: params["reason"] as? String ?? "Codex хочет применить изменения",
                method: method
            )
            status = "Нужно подтвердить изменения"
        case "mcpServer/elicitation/request":
            let body = params["message"] as? String ?? "Подключённый сервис просит ответ."
            pendingQuestion = PendingQuestion(rpcID: id, questions: [AgentQuestion(id: "elicitation", header: "Запрос сервиса", question: body, options: [], isSecret: false)])
            questionAnswers = [:]
        default:
            wire.send(["id": id, "error": ["code": -32601, "message": "Запрос не поддерживается приложением Invis."]])
        }
    }

    private func appendAssistantDelta(itemID: String, delta: String) {
        let messageID = activeAssistantMessageIDs[itemID] ?? itemID
        if !messages.contains(where: { $0.id == messageID }) {
            activeAssistantMessageIDs[itemID] = messageID
            append(ChatMessage(id: messageID, kind: .assistant, text: delta, isActive: true))
        } else {
            mutateMessage(messageID) { $0.text += delta }
        }
        saveActiveMessages()
    }

    private func appendProgressDelta(itemID: String, delta: String) {
        guard let messageID = progressMessageIDs[itemID] else { return }
        mutateMessage(messageID) { $0.text += delta }
    }

    private func append(_ message: ChatMessage) {
        messages.append(message)
        saveActiveMessages()
    }

    private func mutateMessage(_ id: String, change: (inout ChatMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        change(&messages[index])
        saveActiveMessages()
    }

    private func saveActiveMessages() {
        if let activeThreadID { messagesByThread[activeThreadID] = messages }
    }

    private func failTurn(_ error: String) {
        isBusy = false
        status = "Ошибка Codex"
        append(ChatMessage(kind: .error, text: error))
    }

    private func setConnectionError(_ error: String) {
        isConnected = false
        status = "Codex не подключён"
        append(ChatMessage(kind: .error, text: error))
    }

    private func updateUsage(_ result: [String: Any]) {
        let buckets = result["rateLimitsByLimitId"] as? [String: Any]
        let limits = (buckets?["codex"] as? [String: Any]) ?? (result["rateLimits"] as? [String: Any]) ?? [:]
        guard !limits.isEmpty else { return }
        if let plan = limits["planType"] as? String { usage.plan = plan.capitalized }
        if let primary = limits["primary"] as? [String: Any] {
            usage.shortPercent = primary["usedPercent"] as? Int
            usage.shortWindowMinutes = primary["windowDurationMins"] as? Int
            usage.shortResetsAt = primary["resetsAt"] as? TimeInterval
        } else {
            usage.shortPercent = nil
            usage.shortWindowMinutes = nil
            usage.shortResetsAt = nil
        }
        if let secondary = limits["secondary"] as? [String: Any] {
            usage.longPercent = secondary["usedPercent"] as? Int
            usage.longWindowMinutes = secondary["windowDurationMins"] as? Int
            usage.longResetsAt = secondary["resetsAt"] as? TimeInterval
        } else {
            usage.longPercent = nil
            usage.longWindowMinutes = nil
            usage.longResetsAt = nil
        }
    }

    private func messagesFromTurns(_ turns: [[String: Any]]) -> [ChatMessage] {
        var loaded: [ChatMessage] = []
        for turn in turns {
            let items = turn["items"] as? [[String: Any]] ?? []
            for item in items {
                let type = item["type"] as? String ?? ""
                let id = item["id"] as? String ?? UUID().uuidString
                switch type {
                case "userMessage":
                    let content = item["content"] as? [[String: Any]] ?? []
                    let text = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
                    if !text.isEmpty { loaded.append(ChatMessage(id: id, kind: .user, text: text)) }
                case "agentMessage":
                    let text = item["text"] as? String ?? ""
                    if !text.isEmpty { loaded.append(ChatMessage(id: id, kind: .assistant, text: text)) }
                case "plan":
                    if let text = item["text"] as? String, !text.isEmpty { loaded.append(ChatMessage(id: id, kind: .progress, text: "План работы\n\(text)")) }
                case "commandExecution":
                    let command = item["command"] as? String ?? "Команда Codex"
                    let output = item["aggregatedOutput"] as? String ?? ""
                    loaded.append(ChatMessage(id: id, kind: .progress, text: "Выполнена команда\n\(command)\n\(String(output.suffix(1200)))"))
                case "fileChange":
                    loaded.append(ChatMessage(id: id, kind: .progress, text: "Изменения в файлах\n\(Self.fileChangeSummary(item))"))
                default: break
                }
            }
        }
        return loaded
    }

    private static func idKey(_ id: Any) -> String {
        if let number = id as? NSNumber { return number.stringValue }
        return String(describing: id)
    }

    private static func fileChangeSummary(_ item: [String: Any]) -> String {
        let changes = item["changes"] as? [[String: Any]] ?? []
        let paths = changes.compactMap { $0["path"] as? String }
        return paths.isEmpty ? "Подготавливаю изменения" : paths.joined(separator: "\n")
    }
}
