import AgentSweepCore
import SwiftUI

struct SessionsView: View {
    @Environment(AppModel.self) private var model
    @State private var sessions: [SessionInfo] = []
    @State private var loading = true
    @State private var tool: SessionFormat?
    @State private var onlyOld = false
    @State private var query = ""
    @State private var selection = Set<String>()
    @State private var sort = [KeyPathComparator(\SessionInfo.date, order: .reverse)]
    @State private var confirmDelete = false
    @State private var busy = false

    static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private var cutoff: Date { Date().addingTimeInterval(-Double(model.rules.defaults.historyMaxAgeDays) * 86_400) }

    private var shown: [SessionInfo] {
        sessions.filter { s in
            (tool == nil || s.format == tool)
                && (!onlyOld || s.date < cutoff)
                && (query.isEmpty || s.title.localizedCaseInsensitiveContains(query) || s.project.localizedCaseInsensitiveContains(query))
        }
        .sorted(using: sort)
    }

    private var picked: [SessionInfo] { sessions.filter { selection.contains($0.id) } }
    private var pickedBytes: Int64 { picked.reduce(0) { $0 + $1.bytes } }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "会话历史",
                       subtitle: loading ? "正在读取 Claude Code 和 Codex 的会话…" :
                        "共 \(sessions.count) 个会话，占用 \(sessions.reduce(0) { $0 + $1.bytes }.bytes)。删除之前可以先导出成 Markdown 留档。")
            filters
            if Sessions.zstdPath == nil && sessions.contains(where: { $0.path.hasSuffix(".zst") }) {
                Label("部分 Codex 旧会话是 zstd 压缩格式。要导出它们，请先在终端运行 brew install zstd。", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12)).foregroundStyle(Risk.history.color)
                    .padding(.horizontal, 28).padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            table
            bar
        }
        .task { await load() }
        .confirmationDialog("把 \(picked.count) 个会话移到废纸篓？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("移到废纸篓", role: .destructive) { delete(picked) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("移走后对应工具里就看不到这些会话了。在「清理记录」里可以恢复。")
        }
    }

    private var filters: some View {
        HStack(spacing: 12) {
            Picker("", selection: $tool) {
                Text("全部").tag(SessionFormat?.none)
                Text("Claude Code").tag(SessionFormat?.some(.claude))
                Text("Codex").tag(SessionFormat?.some(.codex))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 280)
            Toggle("只看 \(model.rules.defaults.historyMaxAgeDays) 天前的", isOn: $onlyOld).toggleStyle(.switch).controlSize(.small)
            Spacer()
            TextField("搜索标题或项目", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
        }
        .padding(.horizontal, 28).padding(.bottom, 10)
    }

    private var table: some View {
        Table(shown, selection: $selection, sortOrder: $sort) {
            TableColumn("标题", value: \.title) { s in
                Text(s.title).lineLimit(1).help(s.title)
            }
            TableColumn("工具", value: \.format.rawValue) { s in
                Text(s.format.toolName).foregroundStyle(Theme.muted)
            }
            .width(90)
            TableColumn("项目", value: \.projectName) { s in
                Text(s.projectName).foregroundStyle(Theme.muted).help(s.project)
            }
            .width(min: 90, ideal: 140)
            TableColumn("最后更新", value: \.date) { s in
                Text(Self.dateFormat.string(from: s.date))
                    .foregroundStyle(s.date < cutoff ? Risk.history.color : Theme.muted)
                    .monospacedDigit()
            }
            .width(140)
            TableColumn("大小", value: \.bytes) { s in
                Text(s.bytes.bytes).monospacedDigit()
            }
            .width(80)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.panel.opacity(0.5))
        .overlay { if loading { ProgressView().controlSize(.large) } }
        .padding(.horizontal, 20)
        .contextMenu(forSelectionType: String.self) { ids in
            Button("在 Finder 中显示") {
                NSWorkspace.shared.activateFileViewerSelecting(ids.map { URL(fileURLWithPath: $0) })
            }
        }
    }

    private var bar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selection.isEmpty ? "未选择" : "已选 \(picked.count) 个 · \(pickedBytes.bytes)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("按住 ⌘ 或 ⇧ 可以多选，⌘A 全选当前列表").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button("移到废纸篓") { confirmDelete = true }.buttonStyle(GhostButtonStyle())
            Button("导出后移到废纸篓") { export(picked, thenDelete: true) }.buttonStyle(GhostButtonStyle())
            Button("导出 Markdown") { export(picked, thenDelete: false) }.buttonStyle(PrimaryButtonStyle())
        }
        .disabled(selection.isEmpty || busy)
        .padding(.horizontal, 24).padding(.vertical, 14)
        .background(Theme.panel.opacity(0.6))
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        .padding(.top, 10)
    }

    private func load() async {
        loading = true
        let home = model.home
        sessions = await Task.detached { Sessions.discover(home: home) }.value
        loading = false
    }

    private func export(_ list: [SessionInfo], thenDelete: Bool) {
        guard let dir = model.chooseExportFolder() else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let files = try await Task.detached { try Sessions.export(list, to: dir) }.value
                model.show("已导出 \(files.count) 个会话")
                NSWorkspace.shared.activateFileViewerSelecting([dir])
                if thenDelete { delete(list) }
            } catch {
                model.show(error.localizedDescription)
            }
        }
    }

    private func delete(_ list: [SessionInfo]) {
        let paths = list.map(\.path)
        let bytes = list.reduce(0) { $0 + $1.bytes }
        let home = model.home
        busy = true
        Task {
            let record = await Task.detached {
                Cleaner.trashFiles(paths, label: "手动删除的 \(paths.count) 个会话", toolName: "会话历史", bytes: bytes, home: home)
            }.value
            try? model.historyStore.save(record)
            model.history = model.historyStore.load()
            selection = []
            await load()
            busy = false
            model.show("已把 \(record.moveCount) 个会话移到废纸篓")
        }
    }
}
