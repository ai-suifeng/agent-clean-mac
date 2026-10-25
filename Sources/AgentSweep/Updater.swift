import Combine
import Sparkle
import SwiftUI

/// In-app updates through Sparkle. The feed is the `appcast.xml` attached to the latest GitHub release;
/// every update archive is EdDSA-signed in CI and checked against `SUPublicEDKey` before it is installed.
@MainActor
final class Updater: ObservableObject {
    @Published private(set) var canCheck = false
    private let controller: SPUStandardUpdaterController?

    /// Bundles built by scripts/build-app.sh carry a feed; `swift run` does not, so updating is off there.
    static var isConfigured: Bool { Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil }

    init() {
        guard Updater.isConfigured else { controller = nil; return }
        let c = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        controller = c
        c.updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main).assign(to: &$canCheck)
        if CommandLine.arguments.contains("--check-updates") { c.updater.checkForUpdatesInBackground() }
    }

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    func checkForUpdates() { controller?.checkForUpdates(nil) }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { objectWillChange.send(); controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloads: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? false }
        set { objectWillChange.send(); controller?.updater.automaticallyDownloadsUpdates = newValue }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var updater: Updater

    var body: some View {
        Form {
            SwiftUI.Section("更新") {
                LabeledContent("当前版本", value: updater.version)
                Toggle("自动检查更新", isOn: Binding(get: { updater.automaticallyChecks }, set: { updater.automaticallyChecks = $0 }))
                Toggle("自动下载并安装更新", isOn: Binding(get: { updater.automaticallyDownloads }, set: { updater.automaticallyDownloads = $0 }))
                    .disabled(!updater.automaticallyChecks)
                HStack {
                    Text("新版本通过 GitHub Releases 发布，安装前会校验签名。").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("检查更新…") { updater.checkForUpdates() }.disabled(!updater.canCheck)
                }
            }
            SwiftUI.Section("关于") {
                LabeledContent("开源地址") {
                    Link("github.com/ai-suifeng/agent-clean-mac", destination: URL(string: "https://github.com/ai-suifeng/agent-clean-mac")!)
                }
                LabeledContent("官网") {
                    Link("ai-suifeng.github.io/agent-clean-mac", destination: URL(string: "https://ai-suifeng.github.io/agent-clean-mac/")!)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .disabled(!Updater.isConfigured)
    }
}
