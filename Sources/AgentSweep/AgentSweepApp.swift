import AppKit
import SwiftUI

@main
struct AgentSweepApp: App {
    @State private var model = AppModel()
    @StateObject private var updater = Updater()

    init() {
        // Also behave like a regular app when launched straight from `swift run`.
        NSApplication.shared.setActivationPolicy(.regular)
        #if DEBUG
        // Debug builds only: quit normally after N seconds, window or not (lets an update test install on quit).
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--quit-after"), i + 1 < args.count, let n = Double(args[i + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + n) { NSApp.terminate(nil) }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup("AgentSweep") {
            RootView()
                .environment(model)
                .environmentObject(updater)
                .frame(minWidth: 1080, minHeight: 700)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                    let args = CommandLine.arguments
                    if args.contains("--scan") { model.startScan() }
                    if let i = args.firstIndex(of: "--section"), i + 1 < args.count, let s = Section(rawValue: args[i + 1]) {
                        model.section = s
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1260, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("检查更新…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheck)
            }
            CommandMenu("清理") {
                Button("开始扫描") { model.section = .clean; model.reset(); model.startScan() }
                    .keyboardShortcut("r")
            }
        }

        Settings {
            SettingsView().environmentObject(updater)
        }
    }
}
