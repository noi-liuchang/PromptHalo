import AppKit
import SwiftUI

final class PromptHaloAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct PromptHaloApp: App {
    @NSApplicationDelegateAdaptor(PromptHaloAppDelegate.self)
    private var appDelegate

    @StateObject private var state = AppState.shared
    @StateObject private var language = AppLanguageSettings.shared

    var body: some Scene {
        WindowGroup("PromptHalo", id: "manager") {
            ManagerView(state: state)
                .environment(\.locale, language.locale)
        }
        .defaultSize(width: 920, height: 620)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(
                    language.text(
                        "新建 Prompt",
                        "New Prompt"
                    )
                ) {
                    _ = state.createPrompt()
                }
                .keyboardShortcut("n")
            }
        }

        MenuBarExtra {
            PromptHaloMenu(state: state)
        } label: {
            Image(systemName: "quote.bubble")
        }
    }
}

private struct PromptHaloMenu: View {
    @ObservedObject var state: AppState
    @ObservedObject private var language = AppLanguageSettings.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openManager()
        } label: {
            Label(
                language.text(
                    "管理 Prompts",
                    "Manage Prompts"
                ),
                systemImage: "slider.horizontal.3"
            )
        }

        Button {
            state.previewWheel()
        } label: {
            Label(
                language.text(
                    "预览轮盘",
                    "Preview Wheel"
                ),
                systemImage: "circle.hexagongrid"
            )
        }

        Menu {
            Picker(
                language.text(
                    "界面语言",
                    "Interface Language"
                ),
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
                language.text("语言", "Language"),
                systemImage: "globe"
            )
        }

        Divider()

        Text(menuInstruction)
            .foregroundStyle(.secondary)

        Text(state.lastStatus)
            .font(.caption)
            .foregroundStyle(.secondary)

        if !state.accessibilityGranted {
            Divider()
            Button {
                state.requestAccessibility()
            } label: {
                Label(
                    language.text(
                        "开启辅助功能权限",
                        "Enable Accessibility"
                    ),
                    systemImage: "hand.raised"
                )
            }
        }

        Divider()

        Button(
            language.text(
                "退出 PromptHalo",
                "Quit PromptHalo"
            )
        ) {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func openManager() {
        openWindow(id: "manager")
        NSApp.activate(ignoringOtherApps: true)
    }

    private var menuInstruction: String {
        if state.triggerHotKey.isOptionOnly {
            return language.text(
                "长按 \(state.triggerHotKey.displayString) · 方向或数字 1–5",
                "Hold \(state.triggerHotKey.displayString) · direction or 1–5"
            )
        }
        return language.text(
            "按住 \(state.triggerHotKey.displayString) · 方向或数字 1–5",
            "Hold \(state.triggerHotKey.displayString) · direction or 1–5"
        )
    }
}
