import SwiftUI
import AppKit

@main
struct InvizApp: App {
    @StateObject private var model = ChatModel()

    var body: some Scene {
        WindowGroup {
            MainView(model: model)
                .frame(minWidth: 740, minHeight: 600)
                .background(WindowConfigurator())
                .task { model.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 880, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Новый чат") { model.newChat() }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { configure(view.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.level = .floating
        window.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary])
        window.sharingType = .none
        window.isMovableByWindowBackground = true
    }
}
