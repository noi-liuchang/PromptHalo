import Foundation
import SwiftUI

@MainActor
final class PromptStore: ObservableObject {
    @Published private(set) var prompts: [PromptItem] = []

    private let fileURL: URL
    private let initialPrompts: [PromptItem]
    private var saveWorkItem: DispatchWorkItem?

    init(
        fileURL: URL? = nil,
        initialLanguage: ResolvedInterfaceLanguage =
            AppLanguageSettings.shared.resolvedLanguage
    ) {
        let destination: URL
        if let fileURL {
            destination = fileURL
        } else {
            let support = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            destination = support
                .appendingPathComponent("PromptHalo", isDirectory: true)
                .appendingPathComponent("prompts.json")
        }

        self.fileURL = destination
        self.initialPrompts = PromptTemplates.defaults(for: initialLanguage)
        let directory = destination.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            print("PromptHalo: could not create support directory: \(error)")
        }

        load()
    }

    var activePrompts: [PromptItem] {
        prompts
            .filter { !$0.isDeleted }
            .sorted {
                switch ($0.slot, $1.slot) {
                case let (lhs?, rhs?) where lhs != rhs:
                    return lhs < rhs
                case (nil, _?):
                    return false
                case (_?, nil):
                    return true
                default:
                    return $0.updatedAt > $1.updatedAt
                }
            }
    }

    var deletedPrompts: [PromptItem] {
        prompts.filter(\.isDeleted).sorted { $0.updatedAt > $1.updatedAt }
    }

    func prompt(id: UUID) -> PromptItem? {
        prompts.first { $0.id == id }
    }

    func prompt(in slot: Int) -> PromptItem? {
        prompts.first { !$0.isDeleted && $0.slot == slot }
    }

    func slottedPrompts() -> [PromptItem?] {
        (1...5).map(prompt(in:))
    }

    @discardableResult
    func addPrompt(slot: Int? = nil) -> PromptItem {
        if let slot {
            clearSlot(slot, excluding: nil)
        }

        let item = PromptItem(
            title: slot.map { "Prompt \($0)" }
                ?? AppLanguageSettings.shared.text(
                    "未命名 Prompt",
                    "Untitled Prompt"
                ),
            slot: slot
        )
        prompts.append(item)
        scheduleSave()
        return item
    }

    func updateTitle(id: UUID, title: String) {
        mutate(id: id) {
            $0.title = title
        }
    }

    func updateBody(id: UUID, body: String) {
        mutate(id: id) {
            $0.body = body
        }
    }

    func assign(id: UUID, to slot: Int?) {
        if let slot {
            clearSlot(slot, excluding: id)
        }
        mutate(id: id) {
            $0.slot = slot
        }
    }

    func moveToTrash(id: UUID) {
        mutate(id: id) {
            $0.isDeleted = true
            $0.slot = nil
        }
    }

    func restore(id: UUID) {
        mutate(id: id) {
            $0.isDeleted = false
        }
    }

    func duplicate(id: UUID) -> PromptItem? {
        guard var copy = prompt(id: id) else { return nil }
        copy.id = UUID()
        copy.title += AppLanguageSettings.shared.text(" 副本", " Copy")
        copy.slot = nil
        copy.createdAt = Date()
        copy.updatedAt = Date()
        copy.isDeleted = false
        prompts.append(copy)
        scheduleSave()
        return copy
    }

    func importPrompts(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let imported = try JSONDecoder().decode([PromptItem].self, from: data)

        var occupied = Set(
            prompts.compactMap { !$0.isDeleted ? $0.slot : nil }
        )
        let normalized = imported.map { item -> PromptItem in
            var copy = item
            copy.id = UUID()
            if let slot = copy.slot, occupied.contains(slot) {
                copy.slot = nil
            } else if let slot = copy.slot {
                occupied.insert(slot)
            }
            copy.updatedAt = Date()
            return copy
        }

        prompts.append(contentsOf: normalized)
        scheduleSave()
    }

    func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(prompts.filter { !$0.isDeleted })
    }

    private func mutate(id: UUID, change: (inout PromptItem) -> Void) {
        guard let index = prompts.firstIndex(where: { $0.id == id }) else { return }
        change(&prompts[index])
        prompts[index].updatedAt = Date()
        scheduleSave()
    }

    private func clearSlot(_ slot: Int, excluding id: UUID?) {
        for index in prompts.indices
        where prompts[index].slot == slot && prompts[index].id != id {
            prompts[index].slot = nil
            prompts[index].updatedAt = Date()
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            prompts = initialPrompts
            scheduleSave()
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            prompts = try decoder.decode([PromptItem].self, from: data)
        } catch {
            print("PromptHalo: could not load prompts: \(error)")
            prompts = initialPrompts
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let snapshot = prompts
        let destination = fileURL

        let workItem = DispatchWorkItem {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [
                    .prettyPrinted,
                    .sortedKeys,
                    .withoutEscapingSlashes
                ]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(snapshot)
                try data.write(to: destination, options: .atomic)
            } catch {
                print("PromptHalo: could not save prompts: \(error)")
            }
        }

        saveWorkItem = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + 0.18,
            execute: workItem
        )
    }
}
