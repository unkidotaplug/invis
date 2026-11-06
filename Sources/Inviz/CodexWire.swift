import Foundation
import AppKit

final class CodexWire {
    var onMessage: (([String: Any]) -> Void)?
    var onFailure: ((String) -> Void)?

    private var process: Process?
    private var input: FileHandle?
    private let writeQueue = DispatchQueue(label: "ru.macboss.inviz.codex-write")
    private let readQueue = DispatchQueue(label: "ru.macboss.inviz.codex-read")
    private var lineBuffer = Data()

    func start() throws {
        guard let executable = CodexPathResolver.executableURL() else {
            throw NSError(domain: "Inviz", code: 1, userInfo: [NSLocalizedDescriptionKey: "Не найден Codex CLI. Установите или обновите ChatGPT для macOS."])
        }

        let child = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        child.executableURL = executable
        child.arguments = ["app-server", "--listen", "stdio://"]
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = FileHandle.nullDevice
        child.terminationHandler = { [weak self] task in
            guard task.terminationStatus != 0 else { return }
            DispatchQueue.main.async { self?.onFailure?("Codex завершился с кодом \(task.terminationStatus).") }
        }

        try child.run()
        process = child
        input = stdin.fileHandleForWriting
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.readQueue.async { [weak self] in self?.consume(data) }
        }
    }

    func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message, options: [.fragmentsAllowed]) else { return }
        writeQueue.async { [weak self] in
            guard let input = self?.input else { return }
            do {
                try input.write(contentsOf: data + Data([0x0A]))
            } catch {
                DispatchQueue.main.async { self?.onFailure?("Не удалось отправить запрос Codex: \(error.localizedDescription)") }
            }
        }
    }

    func stop() {
        input?.readabilityHandler = nil
        process?.terminationHandler = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
        input = nil
    }

    private func consume(_ data: Data) {
        lineBuffer.append(data)
        while let newline = lineBuffer.firstIndex(of: 0x0A) {
            let line = Data(lineBuffer[..<newline])
            lineBuffer.removeSubrange(...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line),
                  let message = object as? [String: Any] else { continue }
            DispatchQueue.main.async { [weak self] in self?.onMessage?(message) }
        }
    }
}

enum CodexPathResolver {
    static func executableURL() -> URL? {
        let manager = FileManager.default
        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex")
            ?? URL(fileURLWithPath: "/Applications/ChatGPT.app")
        let embedded = appURL
            .appendingPathComponent("Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
        if manager.isExecutableFile(atPath: embedded.path) { return embedded }

        let candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            manager.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path
        ]
        return candidates.first(where: manager.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
    }
}
