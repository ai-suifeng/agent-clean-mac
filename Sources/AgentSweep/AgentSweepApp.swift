import AppKit
import SwiftUI

@main
struct AgentSweepApp: App {
    @State private var model = AppModel()

    init() {
        // Also behave like a regular app when launched straight from `swift run`.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("AgentSweep") {
            RootView()
                .environment(model)
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
            CommandMenu("清理") {
                Button("开始扫描") { model.section = .clean; model.reset(); model.startScan() }
                    .keyboardShortcut("r")
            }
        }
    }
}
