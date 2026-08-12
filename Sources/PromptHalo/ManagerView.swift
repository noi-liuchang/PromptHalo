import SwiftUI
import UniformTypeIdentifiers

private struct PromptJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct ManagerView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store: PromptStore
    @ObservedObject private var language = AppLanguageSettings.shared

    @State private var selectedID: UUID?
    @State private var search = ""
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var showingTriggerHotKeySettings = false
    @State private var exportDocument = PromptJSONDocument()

    init(state: AppState) {
        self.state = state
        self.store = state.store
    }

    var body: some View {
        VStack(spacing: 0) {
            quickSlots
            Divider()

            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 320)
            } detail: {
                detail
            }
        }
        .frame(minWidth: 790, minHeight: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    let item = state.createPrompt()
                    selectedID = item.id
                } label: {
                    Label(
                        language.text("新建 Prompt", "New Prompt"),
                        systemImage: "plus"
                    )
                }

                Button {
                    state.previewWheel()
                } label: {
                    Label(
                        language.text("预览轮盘", "Preview Wheel"),
                        systemImage: "circle.hexagongrid"
                    )
                }

                Menu {
                    Button(language.text("导入 JSON…", "Import JSON…")) {
                        showingImporter = true
                    }
                    Button(language.text("导出 JSON…", "Export JSON…")) {
                        do {
                            exportDocument = PromptJSONDocument(data: try store.exportData())
                            showingExporter = true
                        } catch {
                            state.notify(
                                language.text(
                                    "导出失败",
                                    "Export failed"
                                )
                            )
                        }
                    }

                    Divider()

                    Picker(
                        language.text("界面语言", "Interface Language"),
                        selection: $language.selection
                    ) {
                        Text(
                            language.text(
                                "跟随系统",
                                "System Default"
                            )
                        )
                        .tag(InterfaceLanguage.system)
                        Text("中文").tag(InterfaceLanguage.chinese)
                        Text("English").tag(InterfaceLanguage.english)
                    }
                } label: {
                    Label(
                        language.text("更多", "More"),
                        systemImage: "ellipsis.circle"
                    )
                }
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer {
                    if access {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                try store.importPrompts(from: url)
                state.notify(
                    language.text(
                        "Prompt 已导入",
                        "Prompts imported"
                    )
                )
            } catch {
                state.notify(
                    language.text(
                        "导入失败：文件格式不对",
                        "Import failed: invalid file format"
                    )
                )
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "PromptHalo-Prompts"
        ) { result in
            if case .success = result {
                state.notify(
                    language.text(
                        "Prompt 已导出",
                        "Prompts exported"
                    )
                )
            }
        }
        .sheet(isPresented: $showingTriggerHotKeySettings) {
            TriggerHotKeySettingsView(state: state)
        }
        .onAppear {
            if selectedID == nil {
                selectedID = store.activePrompts.first?.id
            }
        }
        .environment(\.locale, language.locale)
    }

    private var quickSlots: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(language.text("快捷位", "Quick Slots"))
                        .font(.headline)
                    Text(
                        triggerInstruction
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Label(
                    permissionStatusText,
                    systemImage: state.accessibilityGranted
                        ? "checkmark.shield.fill"
                        : "exclamationmark.shield"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(
                    state.accessibilityGranted ? Color.green : Color.orange
                )
            }

            HStack(spacing: 10) {
                Label(
                    language.text("呼出键", "Trigger"),
                    systemImage: "keyboard"
                )
                    .font(.subheadline.weight(.medium))

                Text(
                    state.triggerHotKey.isSingleKeyTrigger
                        ? language.text(
                            "单独长按即可呼出",
                            "Hold the key to open"
                        )
                        : language.text(
                            "长按组合键即可呼出",
                            "Hold the shortcut to open"
                        )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    showingTriggerHotKeySettings = true
                } label: {
                    HStack(spacing: 7) {
                        Text(state.triggerHotKey.displayString)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 100)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 10)
            )

            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { slot in
                    slotCard(slot)
                }
            }

            if !state.accessibilityGranted {
                HStack(spacing: 10) {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(.orange)
                    Text(permissionHelpText)
                        .font(.caption)
                    Spacer()
                    Button(
                        language.text(
                            "去授权",
                            "Open Settings"
                        )
                    ) {
                        state.requestAccessibility()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(10)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
            }
        }
        .padding(18)
    }

    private var triggerInstruction: String {
        if state.triggerHotKey.isSingleKeyTrigger {
            return language.text(
                "长按 \(state.triggerHotKey.displayString) 呼出；"
                    + "再按 1–5，或移动鼠标后松开。",
                "Hold \(state.triggerHotKey.displayString) to open; "
                    + "press 1–5 or move the pointer, then release."
            )
        }
        return language.text(
            "按住 \(state.triggerHotKey.displayString)，再按 1–5；"
                + "也可以向对应方向移动鼠标后松开。",
            "Hold \(state.triggerHotKey.displayString), then press 1–5; "
                + "or move the pointer in a direction and release."
        )
    }

    private var permissionStatusText: String {
        if state.accessibilityGranted {
            return language.text("可直接插入", "Direct insert ready")
        }
        return state.triggerHotKey.isSingleKeyTrigger
            ? language.text(
                "需要授权才能呼出",
                "Permission required"
            )
            : language.text("当前仅复制", "Copy only")
    }

    private var permissionHelpText: String {
        if state.triggerHotKey.isSingleKeyTrigger {
            return language.text(
                "单键长按呼出和自动插入都需要“辅助功能”权限。授权后无需重新设置呼出键。",
                "Long-pressing one key and inserting automatically require Accessibility permission. You will not need to set the trigger again."
            )
        }
        return language.text(
            "允许“辅助功能”后，Prompt 才能自动进入当前输入框。未授权时会安全地复制到剪贴板。",
            "Allow Accessibility so Prompts can enter the active text field. Without permission, PromptHalo safely copies them instead."
        )
    }

    private func slotCard(_ slot: Int) -> some View {
        let prompt = store.prompt(in: slot)

        return Button {
            if let prompt {
                selectedID = prompt.id
            } else {
                let item = state.createPrompt(in: slot)
                selectedID = item.id
            }
        } label: {
            HStack(spacing: 9) {
                Text("\(slot)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 27, height: 27)
                    .background(
                        prompt == nil
                            ? Color.secondary.opacity(0.12)
                            : Color.accentColor.opacity(0.15),
                        in: Circle()
                    )
                    .foregroundStyle(prompt == nil ? .secondary : Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        prompt?.title
                            ?? language.text(
                                "添加 Prompt",
                                "Add Prompt"
                            )
                    )
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(
                        prompt.map {
                            language.text(
                                "\($0.body.count) 字",
                                "\($0.body.count) characters"
                            )
                        }
                            ?? language.text("空位", "Empty")
                    )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                selectedID == prompt?.id
                    ? Color.accentColor.opacity(0.1)
                    : Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 11)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(
                        selectedID == prompt?.id
                            ? Color.accentColor.opacity(0.5)
                            : Color.primary.opacity(0.08),
                        lineWidth: 0.8
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private var sidebar: some View {
        List(selection: $selectedID) {
            Section(language.text("Prompts", "Prompts")) {
                ForEach(filteredPrompts) { prompt in
                    PromptRow(prompt: prompt)
                        .tag(prompt.id)
                        .contextMenu {
                            Button(
                                language.text(
                                    "创建副本",
                                    "Duplicate"
                                )
                            ) {
                                if let copy = store.duplicate(id: prompt.id) {
                                    selectedID = copy.id
                                }
                            }
                            Divider()
                            Button(
                                language.text(
                                    "移到最近删除",
                                    "Move to Recently Deleted"
                                ),
                                role: .destructive
                            ) {
                                store.moveToTrash(id: prompt.id)
                                selectedID = store.activePrompts.first?.id
                            }
                        }
                }
            }

            if !store.deletedPrompts.isEmpty {
                Section(
                    language.text(
                        "最近删除",
                        "Recently Deleted"
                    )
                ) {
                    ForEach(store.deletedPrompts) { prompt in
                        HStack {
                            Image(systemName: "trash")
                                .foregroundStyle(.secondary)
                            Text(prompt.title)
                                .lineLimit(1)
                            Spacer()
                            Button(
                                language.text(
                                    "恢复",
                                    "Restore"
                                )
                            ) {
                                store.restore(id: prompt.id)
                                selectedID = prompt.id
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }
                }
            }
        }
        .searchable(
            text: $search,
            prompt: language.text(
                "搜索 Prompt",
                "Search Prompts"
            )
        )
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedID, let prompt = store.prompt(id: selectedID) {
            if prompt.isDeleted {
                ContentUnavailableView {
                    Label(
                        language.text(
                            "这个 Prompt 在最近删除中",
                            "This Prompt is in Recently Deleted"
                        ),
                        systemImage: "trash"
                    )
                } description: {
                    Text(
                        language.text(
                            "恢复后才能继续编辑。",
                            "Restore it before editing."
                        )
                    )
                } actions: {
                    Button(
                        language.text(
                            "恢复",
                            "Restore"
                        )
                    ) {
                        store.restore(id: selectedID)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                PromptEditor(
                    prompt: prompt,
                    store: store,
                    onCopy: {
                        state.copyPrompt(id: selectedID)
                    },
                    onDuplicate: {
                        if let copy = store.duplicate(id: selectedID) {
                            self.selectedID = copy.id
                        }
                    },
                    onDelete: {
                        store.moveToTrash(id: selectedID)
                        self.selectedID = store.activePrompts.first?.id
                    }
                )
            }
        } else {
            ContentUnavailableView {
                Label(
                    language.text(
                        "选择一个 Prompt",
                        "Select a Prompt"
                    ),
                    systemImage: "text.quote"
                )
            } description: {
                Text(
                    language.text(
                        "或者点击右上角的加号新建。",
                        "Or click the plus button to create one."
                    )
                )
            }
        }
    }

    private var filteredPrompts: [PromptItem] {
        guard !search.isEmpty else { return store.activePrompts }
        return store.activePrompts.filter {
            $0.title.localizedCaseInsensitiveContains(search)
                || $0.body.localizedCaseInsensitiveContains(search)
        }
    }
}

private struct PromptRow: View {
    let prompt: PromptItem

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let slot = prompt.slot {
                    Text("\(slot)")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                } else {
                    Image(systemName: "text.quote")
                        .font(.caption)
                }
            }
            .frame(width: 25, height: 25)
            .background(Color.accentColor.opacity(prompt.slot == nil ? 0.07 : 0.14), in: Circle())
            .foregroundStyle(prompt.slot == nil ? .secondary : Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(prompt.title)
                    .lineLimit(1)
                Text(prompt.body.replacingOccurrences(of: "\n", with: " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct PromptEditor: View {
    let prompt: PromptItem
    @ObservedObject var store: PromptStore
    @ObservedObject private var language = AppLanguageSettings.shared
    let onCopy: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                TextField(
                    language.text(
                        "Prompt 名称",
                        "Prompt Name"
                    ),
                    text: titleBinding
                )
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))

                Picker(
                    language.text("快捷位", "Quick Slot"),
                    selection: slotBinding
                ) {
                    Text(
                        language.text(
                            "不放入轮盘",
                            "Not in Wheel"
                        )
                    )
                    .tag(Int?.none)
                    ForEach(1...5, id: \.self) { slot in
                        Text(
                            language.text(
                                "快捷位 \(slot)",
                                "Slot \(slot)"
                            )
                        )
                        .tag(Int?.some(slot))
                    }
                }
                .labelsHidden()
                .frame(width: 126)

                Button(action: onCopy) {
                    Label(
                        language.text("复制", "Copy"),
                        systemImage: "doc.on.doc"
                    )
                }
                .buttonStyle(.bordered)
            }
            .padding(20)

            Divider()

            TextEditor(text: bodyBinding)
                .font(.system(size: 14.5))
                .scrollContentBackground(.hidden)
                .padding(14)
                .background(Color(nsColor: .textBackgroundColor))

            Divider()

            HStack {
                Text(
                    language.text(
                        "\(prompt.body.count) 字",
                        "\(prompt.body.count) characters"
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(
                    language.text(
                        "创建副本",
                        "Duplicate"
                    ),
                    action: onDuplicate
                )
                    .buttonStyle(.borderless)

                Button(
                    language.text(
                        "移到最近删除",
                        "Move to Recently Deleted"
                    ),
                    role: .destructive,
                    action: onDelete
                )
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 20)
            .frame(height: 44)
        }
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { store.prompt(id: prompt.id)?.title ?? "" },
            set: { store.updateTitle(id: prompt.id, title: $0) }
        )
    }

    private var bodyBinding: Binding<String> {
        Binding(
            get: { store.prompt(id: prompt.id)?.body ?? "" },
            set: { store.updateBody(id: prompt.id, body: $0) }
        )
    }

    private var slotBinding: Binding<Int?> {
        Binding(
            get: { store.prompt(id: prompt.id)?.slot },
            set: { store.assign(id: prompt.id, to: $0) }
        )
    }
}
