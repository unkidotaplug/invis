import SwiftUI
import AppKit
import UniformTypeIdentifiers

private enum Palette {
    static let ink = Color(red: 8/255, green: 15/255, blue: 25/255)
    static let glass = Color(red: 17/255, green: 30/255, blue: 44/255)
    static let accent = Color(red: 96/255, green: 117/255, blue: 141/255)
    static let text = Color.white.opacity(0.94)
    static let muted = Color.white.opacity(0.55)
    static let faint = Color.white.opacity(0.34)
    static let line = Color.white.opacity(0.12)
}

struct MainView: View {
    @ObservedObject var model: ChatModel
    @FocusState private var composerFocused: Bool
    @State private var isDropTargeted = false

    var body: some View {
        ZStack {
            background
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 226)
                    .padding(12)
                Rectangle()
                    .fill(Palette.line.opacity(0.65))
                    .frame(width: 1)
                    .padding(.vertical, 20)
                VStack(spacing: 0) {
                    transcript
                    composer
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(4)
        }
        .preferredColorScheme(.dark)
    }

    private var background: some View {
        ZStack {
            Palette.ink
            RadialGradient(colors: [Palette.glass.opacity(0.55), .clear], center: .topTrailing, startRadius: 10, endRadius: 520)
            RadialGradient(colors: [Palette.accent.opacity(0.08), .clear], center: .bottomLeading, startRadius: 5, endRadius: 440)
            LinearGradient(colors: [.white.opacity(0.025), .clear, Palette.accent.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        VStack(spacing: 12) {
            Button(action: model.newChat) {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 20)
                    Text("Новый чат")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("⌘N")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.faint)
                }
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 13)
                .frame(height: 44)
                .background(Palette.glass.opacity(0.88), in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(Palette.accent.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Создать отдельную переписку")

            HStack {
                Text("ПЕРЕПИСКИ")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Palette.faint)
                Spacer()
                Text("\(model.sessions.count)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.faint)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 5) {
                    ForEach(model.sessions) { session in
                        sessionButton(session)
                    }
                }
                .padding(.bottom, 10)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Circle().fill(Palette.accent).frame(width: 7, height: 7)
                Text(model.isConnected ? "Codex подключён" : "Подключаю Codex")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.muted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(.white.opacity(0.045), in: Capsule())
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .stroke(LinearGradient(colors: [.white.opacity(0.18), Palette.accent.opacity(0.12), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.20), radius: 24, y: 12)
    }

    private func sessionButton(_ session: ChatSession) -> some View {
        Button { model.selectSession(session) } label: {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: model.activeThreadID == session.id ? "bubble.left.and.bubble.right.fill" : "bubble.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(model.activeThreadID == session.id ? Palette.accent : Palette.muted)
                    .frame(width: 16)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 5) {
                    Text(session.title.isEmpty ? "Новый чат" : session.title)
                        .font(.system(size: 11, weight: model.activeThreadID == session.id ? .semibold : .regular))
                        .foregroundStyle(Palette.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(URL(fileURLWithPath: session.cwd.isEmpty ? NSHomeDirectory() : session.cwd).lastPathComponent)
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.faint)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if model.activeThreadID == session.id {
                    RoundedRectangle(cornerRadius: 13).fill(.white.opacity(0.11))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.10), lineWidth: 1))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Открыть рабочую папку") {
                model.projectPath = session.cwd
                UserDefaults.standard.set(session.cwd, forKey: "inviz.projectPath")
            }
        }
        .accessibilityLabel("Чат: \(session.title)")
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 21) {
                    if model.messages.isEmpty {
                        welcome
                            .frame(maxWidth: .infinity, minHeight: 320)
                    } else {
                        ForEach(model.messages) { message in
                            messageView(message).id(message.id)
                        }
                    }
                    if let question = model.pendingQuestion { questionCard(question) }
                    if let approval = model.pendingApproval { approvalCard(approval) }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 24)
                .padding(.top, 26)
                .padding(.bottom, 18)
            }
            .onChange(of: model.messages.count) { _ in withAnimation(.easeOut(duration: 0.24)) { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: model.messages.last?.text) { _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: model.pendingQuestion?.id) { _ in withAnimation(.easeOut(duration: 0.24)) { proxy.scrollTo("bottom", anchor: .bottom) } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Palette.accent.opacity(0.08)).frame(width: 76, height: 76).blur(radius: 15)
                Circle().fill(.ultraThinMaterial).frame(width: 58, height: 58)
                    .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1))
                Image(systemName: "sparkle")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(Palette.accent)
            }
            VStack(spacing: 7) {
                Text(model.activeThreadID == nil ? "Что создаём?" : "Продолжаем чат")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.text)
                Text("Опиши задачу. Codex покажет план и будет сообщать о действиях по ходу работы.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 340)
            }
            HStack(spacing: 7) {
                Image(systemName: "folder.fill").foregroundStyle(Palette.accent)
                Text(model.currentProjectName).lineLimit(1)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Palette.text.opacity(0.82))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
        }
        .padding(24)
    }

    @ViewBuilder private func messageView(_ message: ChatMessage) -> some View {
        switch message.kind {
        case .user:
            HStack {
                Spacer(minLength: 60)
                VStack(alignment: .trailing, spacing: 8) {
                    if !message.text.isEmpty {
                        Text(markdown(message.text))
                            .font(.system(size: 13.5))
                            .foregroundStyle(.white)
                            .textSelection(.enabled)
                    }
                    ForEach(message.attachments) { attachment in
                        attachmentChip(attachment, compact: false, removable: false)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Palette.glass.opacity(0.88), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.accent.opacity(0.24), lineWidth: 1))
            }
        case .assistant:
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "sparkle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 25, height: 25)
                    .background(Palette.glass, in: Circle())
                    .overlay(Circle().stroke(Palette.accent.opacity(0.18), lineWidth: 1))
                VStack(alignment: .leading, spacing: 7) {
                    Text(markdown(message.text))
                        .font(.system(size: 13.5))
                        .foregroundStyle(Palette.text.opacity(0.93))
                        .lineSpacing(3.5)
                        .textSelection(.enabled)
                    if message.isActive { ProgressView().controlSize(.small).tint(Palette.accent) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .progress:
            HStack(alignment: .top, spacing: 10) {
                if message.isActive {
                    ProgressView().controlSize(.small).tint(Palette.accent).frame(width: 22, height: 22)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 22, height: 22)
                }
                Text(markdown(message.text))
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.muted)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.08), lineWidth: 1))
        case .error:
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.accent).font(.system(size: 13))
                Text(message.text).font(.system(size: 12)).foregroundStyle(Palette.text.opacity(0.88)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.accent.opacity(0.24), lineWidth: 1))
        }
    }

    private func questionCard(_ pending: PendingQuestion) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill").foregroundStyle(Palette.accent)
                Text("Codex спрашивает").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
            }
            ForEach(pending.questions) { question in
                VStack(alignment: .leading, spacing: 9) {
                    Text(question.header.uppercased()).font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(Palette.faint)
                    Text(question.question).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text).textSelection(.enabled)
                    if !question.options.isEmpty {
                        FlowButtons(options: question.options, selected: model.questionAnswers[question.id]) { value in
                            model.questionAnswers[question.id] = value
                        }
                    }
                    if question.options.isEmpty || question.options.contains(where: { $0.label == "Other" || $0.label == "Другое" }) {
                        Group {
                            if question.isSecret {
                                SecureField("Ваш ответ…", text: answerBinding(question.id))
                            } else {
                                TextField("Ваш ответ…", text: answerBinding(question.id))
                            }
                        }
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.12), lineWidth: 1))
                        .overlay(ArrowCursorOverlay().allowsHitTesting(false))
                    }
                }
            }
            HStack {
                Spacer()
                Button("Отправить ответ") { model.answerQuestion() }
                    .buttonStyle(GlassPrimaryButton())
                    .disabled(pending.questions.contains { model.questionAnswers[$0.id, default: ""].isEmpty && $0.options.isEmpty })
            }
        }
        .padding(16)
        .glassCard(radius: 18, accent: Palette.accent)
    }

    private func approvalCard(_ request: PendingApproval) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Codex запрашивает доступ", systemImage: "lock.open.fill")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.accent)
            Text(request.reason).font(.system(size: 12)).foregroundStyle(Palette.text)
            if !request.command.isEmpty {
                Text(request.command).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted).textSelection(.enabled)
            }
            HStack {
                Button("Отказать") { model.answerApproval("decline") }.buttonStyle(GlassSecondaryButton())
                Spacer()
                Button("Разрешить на чат") { model.answerApproval("acceptForSession") }.buttonStyle(GlassSecondaryButton())
                Button("Разрешить") { model.answerApproval("accept") }.buttonStyle(GlassPrimaryButton())
            }
        }
        .padding(16)
        .glassCard(radius: 18, accent: Palette.accent)
    }

    private var composer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                modelMenu
                effortMenu
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Circle().fill(Palette.accent).frame(width: 6, height: 6)
                    Text(model.isBusy ? model.status : "Готов")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                .help(model.status)
            }

            if !model.pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.pendingAttachments) { attachment in
                            attachmentChip(attachment, compact: true, removable: true)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button(action: model.chooseAttachments) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 30, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Прикрепить изображения и файлы")
                .disabled(model.isBusy)

                Button(action: model.attachClipboardImage) {
                    Image(systemName: "photo")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 27, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Прикрепить изображение из буфера обмена")
                .disabled(model.isBusy)

                TextField("Опиши задачу для Codex…", text: $model.prompt, axis: .vertical)
                    .font(.system(size: 13.5))
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .focused($composerFocused)
                    .onSubmit { model.send() }
                    .onPasteCommand(of: [UTType.image, UTType.fileURL]) { providers in
                        if providers.contains(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
                            model.attachClipboardImage()
                        } else {
                            _ = model.acceptDroppedAttachments(providers)
                        }
                    }
                    .disabled(model.isBusy)
                    .padding(.vertical, 7)
                    .overlay(ArrowCursorOverlay().allowsHitTesting(false))
                    .accessibilityLabel("Сообщение для Codex")
                Button {
                    if model.isBusy { model.interrupt() } else { model.send() }
                } label: {
                    Image(systemName: model.isBusy ? "stop.fill" : "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 35, height: 35)
                        .background {
                            if model.isBusy {
                                RoundedRectangle(cornerRadius: 11).fill(Palette.glass)
                            } else {
                                RoundedRectangle(cornerRadius: 11).fill(Palette.accent.opacity(0.34))
                            }
                        }
                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(0.24), lineWidth: 1))
                        .shadow(color: Palette.accent.opacity(0.08), radius: 8, y: 2)
                }
                .buttonStyle(.plain)
                .help(model.isBusy ? "Остановить ответ" : "Отправить · ⌘↵")
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.isBusy && ((model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.pendingAttachments.isEmpty) || !model.isConnected))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.black.opacity(0.17), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(composerFocused ? Palette.accent.opacity(0.28) : .white.opacity(0.12), lineWidth: 1))

            HStack(spacing: 8) {
                Button(action: model.chooseProject) {
                    HStack(spacing: 7) {
                        Image(systemName: "folder")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                        Text(model.currentProjectName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Palette.text.opacity(0.85))
                            .lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(Palette.faint)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(.white.opacity(0.055), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(model.projectPath ?? "Выбрать рабочую папку")
                Spacer(minLength: 0)
                usageMenu
                Text("Полный доступ").font(.system(size: 9, weight: .medium)).foregroundStyle(Palette.faint)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(.white.opacity(0.035), in: Capsule())
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(LinearGradient(colors: [.white.opacity(0.20), Palette.accent.opacity(0.12), .white.opacity(0.07)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Palette.accent.opacity(0.55), lineWidth: 2)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            model.acceptDroppedAttachments(providers)
        }
        .shadow(color: .black.opacity(0.24), radius: 24, y: 9)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private func attachmentChip(_ attachment: ChatAttachment, compact: Bool, removable: Bool) -> some View {
        let thumbnailSize: CGFloat = compact ? 34 : 92
        return HStack(spacing: 8) {
            if attachment.isImage, attachment.url.isFileURL, let image = NSImage(contentsOf: attachment.url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: thumbnailSize, height: thumbnailSize)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: attachment.isImage ? "photo" : "doc.text")
                    .font(.system(size: compact ? 14 : 18, weight: .medium))
                    .foregroundStyle(Palette.accent)
                    .frame(width: thumbnailSize, height: thumbnailSize)
                    .background(Palette.ink.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(attachment.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(attachment.isImage ? "Изображение" : "Файл")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: compact ? 138 : 180, alignment: .leading)

            if removable {
                Button { model.removeAttachment(attachment) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.muted)
                }
                .buttonStyle(.plain)
                .help("Убрать вложение")
            }
        }
        .padding(6)
        .background(Palette.glass.opacity(0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.accent.opacity(0.16), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(attachment.name)
    }

    private var modelMenu: some View {
        Menu {
            ForEach(model.models) { item in
                Button {
                    model.selectModel(item.id)
                } label: {
                    if item.id == model.selectedModelID { Label(item.name, systemImage: "checkmark") }
                    else { Text(item.name) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(Palette.accent)
                Text(model.selectedModel?.name ?? "Модель").foregroundStyle(Palette.text)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(Palette.faint)
            }
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.white.opacity(0.065), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.11), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .help("Модель доступна вашему аккаунту ChatGPT")
    }

    private var effortMenu: some View {
        Menu {
            ForEach(model.selectedModel?.efforts ?? []) { effort in
                Button {
                    model.selectEffort(effort.id)
                } label: {
                    if effort.id == model.selectedEffort { Label(effort.title, systemImage: "checkmark") }
                    else { Text(effort.title) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "dial.low.fill").foregroundStyle(Palette.accent)
                Text(model.selectedEffortTitle).foregroundStyle(Palette.text)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(Palette.faint)
            }
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.white.opacity(0.065), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.11), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .help("Уровень усилий рассуждения")
    }

    private var usageMenu: some View {
        Menu {
            Section("Общий лимит Codex · \(model.usage.plan)") {
                if let percent = model.usage.shortPercent {
                    Text(limitSummary(percent, duration: model.usage.shortWindowMinutes, fallback: "Короткое окно"))
                }
                if let percent = model.usage.longPercent {
                    Text(limitSummary(percent, duration: model.usage.longWindowMinutes, fallback: "Длинное окно"))
                }
            }
            if let reset = model.usage.shortResetsAt {
                Text("Сброс \(windowTitle(model.usage.shortWindowMinutes, fallback: "короткого окна")): \(Date(timeIntervalSince1970: reset).formatted(date: .omitted, time: .shortened))")
            }
            if let reset = model.usage.longResetsAt {
                Text("Сброс \(windowTitle(model.usage.longWindowMinutes, fallback: "длинного окна")): \(Date(timeIntervalSince1970: reset).formatted(date: .abbreviated, time: .shortened))")
            }
            Button("Обновить данные") { model.refreshUsage() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "gauge.with.dots.needle.67percent").foregroundStyle(Palette.accent)
                Text("Лимиты")
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette.text.opacity(0.82))
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(.white.opacity(0.045), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .help("Общие лимиты Codex для аккаунта \(model.usage.plan)")
    }

    private func limitSummary(_ used: Int, duration: Int?, fallback: String) -> String {
        let remaining = max(0, 100 - used)
        return "\(windowTitle(duration, fallback: fallback)): использовано \(used)% · осталось \(remaining)%"
    }

    private func windowTitle(_ minutes: Int?, fallback: String) -> String {
        guard let minutes, minutes > 0 else { return fallback }
        if minutes % 1_440 == 0 { return "\(minutes / 1_440) дн." }
        if minutes % 60 == 0 { return "\(minutes / 60) ч" }
        return "\(minutes) мин"
    }

    private func answerBinding(_ id: String) -> Binding<String> {
        Binding(get: { model.questionAnswers[id, default: ""] }, set: { model.questionAnswers[id] = $0 })
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

private struct FlowButtons: View {
    let options: [AgentQuestion.Option]
    let selected: String?
    let choose: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(options) { option in
                Button { choose(option.label) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: selected == option.label ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selected == option.label ? Palette.accent : Palette.faint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.text)
                            if !option.description.isEmpty { Text(option.description).font(.system(size: 9)).foregroundStyle(Palette.muted) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(selected == option.label ? Palette.accent.opacity(0.14) : .white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected == option.label ? Palette.accent.opacity(0.20) : .white.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct GlassPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(Palette.accent.opacity(0.26), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.26), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private struct GlassSecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Palette.text.opacity(0.9))
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(.white.opacity(configuration.isPressed ? 0.13 : 0.07), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.13), lineWidth: 1))
    }
}

private struct GlassCard: ViewModifier {
    let radius: CGFloat
    let accent: Color
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(LinearGradient(colors: [.white.opacity(0.20), accent.opacity(0.24), .white.opacity(0.07)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .shadow(color: .black.opacity(0.20), radius: 18, y: 8)
    }
}

private extension View {
    func glassCard(radius: CGFloat, accent: Color) -> some View { modifier(GlassCard(radius: radius, accent: accent)) }
}

private struct ArrowCursorOverlay: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ArrowCursorView() }
    func updateNSView(_ view: NSView, context: Context) { view.window?.invalidateCursorRects(for: view) }
}

private final class ArrowCursorView: NSView {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }
}
