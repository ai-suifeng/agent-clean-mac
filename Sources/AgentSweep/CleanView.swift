import AgentSweepCore
import SwiftUI

struct CleanView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            header
            HStack(alignment: .top, spacing: 12) {
                StageView()
                    .frame(minWidth: 380, maxWidth: 560)
                    .aspectRatio(1, contentMode: .fit)
                FindingsPanel()
                    .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
            .frame(maxHeight: .infinity, alignment: .top)
            BottomBar()
        }
        .confirmationDialog(confirmTitle, isPresented: $model.confirmClean, titleVisibility: .visible) {
            Button("移到废纸篓") { model.clean() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    private var confirmTitle: String { "清理 \(model.selectedBytes.bytes)？" }

    private var confirmMessage: String {
        var m = "\(model.selectedFindings.count) 项内容会移到废纸篓，清空废纸篓之前都可以在「清理记录」里恢复。"
        let running = model.runningSelectedTools
        if !running.isEmpty {
            m += "\n\n\(running.joined(separator: "、")) 正在运行。缓存仍可以清理，但它可能马上重新生成一部分，建议先退出。"
        }
        return m
    }

    private var header: some View {
        let (title, sub): (String, String) = switch model.phase {
        case .idle:
            ("你的 Agent 工具占了多少空间？", "AgentSweep 认识 \(model.tools.count) 种 AI 编程工具的目录结构。它只清理能确认安全的文件，配置和登录凭证一律不碰。")
        case .scanning:
            ("正在扫描…", "只读取文件大小，不打开、不修改任何文件。")
        case .results:
            ("找到 \(model.foundBytes.bytes) 的 Agent 数据",
             "其中 \(model.removableBytes.bytes) 可以放心清理。另有 \(model.compactBytes.bytes) 是数据库，只能压缩，不能删除。")
        case .cleaning:
            ("正在清理…", "文件会移到废纸篓，不会直接删除。")
        case .done:
            ("清理了 \((model.lastRecord?.freedBytes ?? 0).bytes)", "文件已经移到废纸篓，清空废纸篓后磁盘空间才会真正释放。留下的是数据库、受保护的配置和你没选中的条目。")
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 22, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
            Text(sub).font(.system(size: 13.5)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 4)
    }
}

// MARK: Stage

struct StageView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoverPoint: CGPoint?

    var body: some View {
        let engine = model.engine
        let input = StageEngine.Input(phase: model.phase, tools: model.tools, reports: model.reports,
                                      findings: model.findings, selected: model.selected, hovered: model.hovered)
        TimelineView(.animation) { tl in
            ZStack {
                Canvas { ctx, size in
                    engine.reduceMotion = reduceMotion
                    engine.draw(&ctx, size: size, now: tl.date, input: input)
                }
                CoreReadout(value: engine.shown)
            }
        }
        .contentShape(Circle())
        .onContinuousHover { phase in
            guard model.phase == .results || model.phase == .done else { return }
            switch phase {
            case .active(let p):
                hoverPoint = p
                let id = engine.hit(p)
                if model.hovered != id { model.hovered = id }
            case .ended:
                hoverPoint = nil
                model.hovered = nil
            }
        }
        .onTapGesture { p in
            if model.phase == .idle { model.startScan(); return }
            if let id = engine.hit(p) { model.toggle(id) }
        }
        .overlay(alignment: .topLeading) { tooltip }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("空间分布")
    }

    @ViewBuilder private var tooltip: some View {
        if let id = model.hovered, let p = hoverPoint, let f = model.findings.first(where: { $0.id == id }),
           let tool = model.tool(f.toolId) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(tool.name) · \(f.rule.label)").font(.system(size: 13, weight: .semibold))
                Text(f.rule.explain).font(.system(size: 12)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(f.bytes.bytes).foregroundStyle(Theme.ice)
                    Text("·").foregroundStyle(Theme.dim)
                    Text(f.risk.title).foregroundStyle(f.risk.color)
                }
                .font(.system(size: 11.5, design: .monospaced))
            }
            .padding(10)
            .frame(width: 240, alignment: .leading)
            .background(Theme.window.opacity(0.95), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line2))
            .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
            .offset(x: p.x + 14 + 250 > (model.engine.side) ? p.x - 254 : p.x + 14, y: p.y + 14)
            .allowsHitTesting(false)
        }
    }
}

struct CoreReadout: View {
    @Environment(AppModel.self) private var model
    let value: Double

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .bold)).kerning(1.6)
                .foregroundStyle(Theme.muted)
            if model.phase == .idle {
                Text("\(model.tools.count)").font(.system(size: 46, weight: .light, design: .rounded))
                    + Text(" 个工具").font(.system(size: 16, weight: .medium)).foregroundColor(Theme.muted)
                Text("点击开始扫描").font(.system(size: 12)).foregroundStyle(Theme.ice.opacity(0.8))
            } else {
                let (n, u) = ByteFormat.parts(Int64(value))
                (Text(n).font(.system(size: 46, weight: .light, design: .rounded)).monospacedDigit()
                    + Text(" " + u).font(.system(size: 18, weight: .medium)).foregroundColor(Theme.muted))
                    .shadow(color: Theme.ice.opacity(0.35), radius: 16)
                Text(sub).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.muted)
            }
        }
        .allowsHitTesting(false)
    }

    private var label: String {
        switch model.phase {
        case .idle: "待扫描"
        case .scanning: "已发现"
        case .results: "已选中"
        case .cleaning: "正在释放"
        case .done: "已清理"
        }
    }

    private var sub: String {
        switch model.phase {
        case .scanning: "\(model.reports.count) 个工具"
        case .results: "共扫描 \(model.foundBytes.bytes)"
        case .cleaning: "移到废纸篓"
        default: "已移到废纸篓"
        }
    }
}

// MARK: Findings

struct FindingsPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            switch model.phase {
            case .idle: Intro()
            case .scanning: ScanLog()
            default: FindingGroups()
            }
        }
        .scrollIndicators(.automatic)
    }
}

struct Intro: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("只清理认识的文件").font(.system(size: 14, weight: .semibold))
            Text("每条规则都写明了路径、用途和删除后的影响。没有收录的文件一律不动，删除的内容都进废纸篓，可以恢复。")
                .foregroundStyle(Theme.muted).lineSpacing(3)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Risk.order, id: \.self) { r in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Pill(text: r.title, color: r.color).frame(width: 120, alignment: .leading)
                        Text(r.blurb).foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(.top, 4)
        }
        .font(.system(size: 13.5))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 14)
    }
}

struct ScanLog: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 4) {
            ForEach(model.log) { l in
                HStack {
                    Text(l.path).lineLimit(1).truncationMode(.tail).foregroundStyle(Theme.muted)
                    Spacer()
                    Text(l.size).monospacedDigit()
                }
                .font(.system(size: 12))
                .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.35), value: model.log.count)
        .padding(.top, 14)
    }
}

struct FindingGroups: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let all = model.findings
        LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(Risk.order, id: \.self) { risk in
                let items = all.filter { $0.risk == risk }.sorted { $0.bytes > $1.bytes }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            if risk.isRemovable { GroupCheck(risk: risk) }
                            Pill(text: risk.title, color: risk.color)
                            Text(risk.blurb).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                            Spacer()
                            if risk.isRemovable && model.phase == .results && items.count > 1 {
                                Button("反选") { model.invertGroup(risk) }.buttonStyle(MiniButtonStyle())
                                    .help("把这一组里勾选和没勾选的对调")
                            }
                            Text(items.reduce(0) { $0 + $1.bytes }.bytes).font(.system(size: 12, design: .monospaced))
                        }
                        ForEach(items) { f in FindingRow(finding: f) }
                    }
                }
            }
        }
        .padding(.vertical, 6).padding(.trailing, 6)
    }
}

struct FindingRow: View {
    @Environment(AppModel.self) private var model
    let finding: Finding

    var body: some View {
        let f = finding
        let tool = model.tool(f.toolId)
        let removable = f.risk.isRemovable
        let on = model.selected.contains(f.id)
        let gone = model.cleaned.contains(f.id)
        let hl = model.hovered == f.id
        HStack(alignment: .top, spacing: 10) {
            Checkbox(on: on && !gone, locked: !removable)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Circle().fill(tool?.tint ?? .gray).frame(width: 7, height: 7)
                        Text(tool?.name ?? "").foregroundStyle(Theme.muted)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    Text(f.rule.label).font(.system(size: 13, weight: .semibold)).strikethrough(gone)
                }
                Text(pathSummary).font(Theme.mono).foregroundStyle(Theme.dim).lineLimit(2)
                Text(f.rule.explain).font(.system(size: 12)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(f.bytes.bytes).font(.system(size: 12.5, design: .monospaced)).monospacedDigit()
                if f.rule.export != nil && !gone {
                    Button("导出 Markdown") { model.export(f) }.buttonStyle(MiniButtonStyle())
                }
                if f.risk == .compact {
                    Button("去压缩") { model.section = .compact }.buttonStyle(MiniButtonStyle())
                }
                if gone { Text("已清理").font(.system(size: 11, weight: .bold)).foregroundStyle(Risk.safe.color) }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(hl ? Theme.raise : Theme.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(hl ? Theme.ice.opacity(0.45) : Theme.line))
        .opacity(gone ? 0.35 : (removable ? 1 : 0.65))
        .contentShape(Rectangle())
        .onTapGesture { model.toggle(f.id) }
        .onHover { h in model.hovered = h ? f.id : (model.hovered == f.id ? nil : model.hovered) }
        .animation(.easeOut(duration: 0.15), value: hl)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(removable ? .isButton : [])
        .accessibilityValue(on ? "已选中" : "未选中")
    }

    private var pathSummary: String {
        let e = finding.entries
        if e.count == 1 { return abbreviate(e[0]) }
        let parents = Set(e.map { ($0 as NSString).deletingLastPathComponent })
        if parents.count == 1, let p = parents.first, p != appHome { return "\(abbreviate(p))/ · \(e.count) 项" }
        return "\(abbreviate(e[0])) 等 \(e.count) 处"
    }
}

/// Group header checkbox: ticked, mixed or empty. Clicking selects the whole group or clears it.
struct GroupCheck: View {
    @Environment(AppModel.self) private var model
    let risk: Risk

    var body: some View {
        let ids = model.groupIDs(risk)
        let n = ids.filter(model.selected.contains).count
        let all = !ids.isEmpty && n == ids.count
        Button { model.toggleGroup(risk) } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(n > 0 ? Theme.ice : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(n > 0 ? Theme.ice : Theme.dim, lineWidth: 1.5))
                if n > 0 {
                    Image(systemName: all ? "checkmark" : "minus")
                        .font(.system(size: 10, weight: .heavy)).foregroundStyle(Color(hex: "#04121D"))
                }
            }
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.phase != .results || ids.isEmpty)
        .help(all ? "取消这一组的全部勾选" : "勾选这一组的全部条目")
        .accessibilityLabel(all ? "取消全选\(risk.title)" : "全选\(risk.title)")
        .animation(.spring(duration: 0.2), value: n)
    }
}

struct Checkbox: View {
    let on: Bool
    let locked: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(on ? Theme.ice : .clear)
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(on ? Theme.ice : Theme.dim, style: StrokeStyle(lineWidth: 1.5, dash: locked ? [3, 2] : [])))
            if on {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Color(hex: "#04121D"))
            } else if locked {
                Image(systemName: "lock.fill").font(.system(size: 8)).foregroundStyle(Theme.dim)
            }
        }
        .frame(width: 18, height: 18)
        .padding(.top, 1)
        .animation(.spring(duration: 0.2), value: on)
    }
}

// MARK: Bottom bar

struct BottomBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            Spacer()
            if model.phase == .done || model.phase == .results {
                Button("重新扫描") { model.reset(); model.startScan() }.buttonStyle(GhostButtonStyle())
            }
            Button(action: primary) { Text(primaryTitle).contentTransition(.numericText()) }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(primaryDisabled)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
        .background(Theme.panel.opacity(0.6))
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        .animation(.smooth, value: model.selectedBytes)
    }

    private var title: String {
        switch model.phase {
        case .idle: "准备就绪"
        case .scanning: "扫描中"
        case .results: "已选 \(model.selectedBytes.bytes)"
        case .cleaning: "清理中"
        case .done: "清理完成"
        }
    }

    private var subtitle: String {
        switch model.phase {
        case .idle: "扫描只读取文件大小，不会修改任何内容"
        case .scanning: "\(model.tools.count) 个工具 · 规则库 v\(model.rules.version)（\(model.rules.updated)）"
        case .results: "\(model.selectedFindings.count) 项 · 移到废纸篓，可以随时恢复"
        case .cleaning: "正在移到废纸篓"
        case .done: "清空废纸篓后才会真正释放空间；清空前都可以恢复"
        }
    }

    private var primaryTitle: String {
        switch model.phase {
        case .idle: "开始扫描"
        case .scanning: "扫描中…"
        case .results: "清理 \(model.selectedBytes.bytes)"
        case .cleaning: "清理中…"
        case .done: "查看清理记录"
        }
    }

    private var primaryDisabled: Bool {
        model.phase == .scanning || model.phase == .cleaning || (model.phase == .results && model.selectedBytes == 0)
    }

    private func primary() {
        switch model.phase {
        case .idle: model.startScan()
        case .results: model.confirmClean = true
        case .done: model.section = .history
        default: break
        }
    }
}
