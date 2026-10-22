import AgentSweepCore
import SwiftUI

/// Frame-by-frame state for the scanner stage. It is a plain reference type that the Canvas
/// steps and draws each frame, so animation never churns SwiftUI state.
/// Positions are stored in unit space (0…1) and scaled to the canvas side when drawn.
final class StageEngine {
    struct Particle {
        var spiral: Bool
        var x0 = 0.0, y0 = 0.0, qx = 0.0, qy = 0.0, t = 0.0, speed = 1.0 // flow along a curve into the core
        var a = 0.0, r = 0.0, vr = 0.0, delay = 0.0 // spiral into the hole
        var color: Color
        var size: Double
        var prev: CGPoint?
    }

    struct Seg {
        let id: String
        let isTool: Bool
        let a0: Double
        let a1: Double
        let color: Color
        let risk: Risk?
    }

    struct Input {
        let phase: Phase
        let tools: [ToolDef]
        let reports: [String: ToolReport]
        let findings: [Finding]
        let selected: Set<String>
        let hovered: String?
    }

    var reduceMotion = false
    var target = 0.0
    private(set) var shown = 0.0
    private(set) var segs: [Seg] = []
    private(set) var side: CGFloat = 1

    private var last: Date?
    private var rot = 0.0
    private var toolCount = 1
    private var lit: [String: Double] = [:]
    private var live: String?
    private var particles: [Particle] = []
    private var ringBegan: Date?
    private var cleanBegan: Date?
    private var cleanIDs: [String] = []
    private var cleanBytes = 0.0
    private var vanish: [String: Double] = [:]
    private var hole = 0.0
    private var flash = 0.0
    private var spawnedClean = false

    var cleanDuration: Double { reduceMotion ? 0.4 : 3.4 }

    // MARK: Commands

    func reset(toolCount: Int) {
        self.toolCount = max(1, toolCount)
        lit = [:]; live = nil; particles = []; vanish = [:]
        ringBegan = nil; cleanBegan = nil; cleanIDs = []
        hole = 0; flash = 0; target = 0; shown = 0
    }

    func reveal(index: Int, id: String, bytes: Int64, color: Color) {
        live = id
        lit[id] = lit[id] ?? 0.01
        target += Double(bytes)
        guard !reduceMotion else { return }
        let p = planet(index, radius: 0.42 * 0.82)
        let n = min(80, 14 + Int((Double(bytes) / 1e9).squareRoot() * 14))
        for _ in 0..<n {
            particles.append(Particle(spiral: false,
                                      x0: p.x + .random(in: -0.015...0.015), y0: p.y + .random(in: -0.015...0.015),
                                      qx: 0.5 + .random(in: -0.25...0.25), qy: 0.5 + .random(in: -0.25...0.25),
                                      t: -.random(in: 0...0.9), speed: .random(in: 0.9...1.5),
                                      color: color, size: .random(in: 1...2.4)))
        }
    }

    func beginResults(target: Double) {
        live = nil
        ringBegan = Date()
        self.target = target
    }

    func beginClean(ids: [String], bytes: Double) {
        cleanIDs = ids
        cleanBytes = bytes
        shown = bytes
        target = bytes
        cleanBegan = Date()
        spawnedClean = false
    }

    func finishClean(freed: Double) {
        for id in cleanIDs { vanish[id] = 1 }
        cleanBegan = nil
        flash = reduceMotion ? 0 : 1
        target = freed
        shown = freed
    }

    // MARK: Hit testing

    func hit(_ p: CGPoint) -> String? {
        let R = side * 0.42
        let dx = p.x - side / 2, dy = p.y - side / 2
        let d = (dx * dx + dy * dy).squareRoot()
        guard d > R * 0.64, d < R * 0.89 else { return nil }
        var a = atan2(dy, dx)
        if a < -.pi / 2 { a += 2 * .pi }
        return segs.first { !$0.isTool && a >= $0.a0 && a < $0.a1 }?.id
    }

    // MARK: Frame

    func draw(_ ctx: inout GraphicsContext, size: CGSize, now: Date, input: Input) {
        side = min(size.width, size.height)
        let dt = min(0.05, last.map { now.timeIntervalSince($0) } ?? 0)
        last = now
        let R = side * 0.42

        // Light up revealed tools gradually.
        for (k, v) in lit where v < 1 { lit[k] = min(1, v + dt * 3) }

        switch input.phase {
        case .idle, .scanning:
            rot += dt * (input.phase == .idle ? 0.05 : 0.12)
            drawDial(&ctx, R: R, alpha: 1)
            if input.phase == .scanning { drawSweep(&ctx, R: R, now: now) }
            drawPlanets(&ctx, R: R, alpha: 1, now: now, input: input)
        case .results, .cleaning, .done:
            let p = reduceMotion ? 1 : min(1, now.timeIntervalSince(ringBegan ?? .distantPast) / 1.1)
            let grow = 1 - pow(1 - p, 3)
            drawDial(&ctx, R: R, alpha: 0.6)
            if p < 1 { drawPlanets(&ctx, R: R, alpha: 1 - p, now: now, input: input) }
            if input.phase == .cleaning { stepClean(now: now, dt: dt) }
            buildSegs(input)
            drawRing(&ctx, R: R, progress: grow, input: input)
        }
        if input.phase == .done || input.phase == .idle { hole = max(0, hole - dt * 1.4) }
        drawHole(&ctx, R: R, now: now)
        drawParticles(&ctx, dt: dt)
        if flash > 0 {
            let c = CGPoint(x: side / 2, y: side / 2)
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
                Gradient(colors: [Color(red: 0.86, green: 0.94, blue: 1).opacity(flash * 0.9), Theme.ice.opacity(0)]),
                center: c, startRadius: 0, endRadius: R * 1.1))
            flash = max(0, flash - dt * 1.6)
        }
        let rate = input.phase == .cleaning ? 14.0 : 7.0
        shown += (target - shown) * min(1, dt * rate)
        if abs(target - shown) < 1e5 { shown = target }
    }

    // MARK: Pieces

    private func polar(_ c: CGPoint, _ a: Double, _ r: CGFloat) -> CGPoint {
        CGPoint(x: c.x + CGFloat(cos(a)) * r, y: c.y + CGFloat(sin(a)) * r)
    }

    private func planet(_ i: Int, radius: Double) -> (x: Double, y: Double) {
        let a = -Double.pi / 2 + Double(i) * 2 * .pi / Double(toolCount) + rot
        return (0.5 + cos(a) * radius, 0.5 + sin(a) * radius)
    }

    private func drawDial(_ ctx: inout GraphicsContext, R: CGFloat, alpha: Double) {
        let c = CGPoint(x: side / 2, y: side / 2)
        var ticks = Path(), longTicks = Path()
        for k in 0..<120 {
            let a = Double(k) / 120 * 2 * .pi
            let long = k % 10 == 0
            let r0 = R * (long ? 0.92 : 0.95), r1 = R * 0.97
            var p = long ? longTicks : ticks
            p.move(to: polar(c, a, r0))
            p.addLine(to: polar(c, a, r1))
            if long { longTicks = p } else { ticks = p }
        }
        ctx.stroke(ticks, with: .color(Theme.ice.opacity(0.12 * alpha)), lineWidth: 1)
        ctx.stroke(longTicks, with: .color(Theme.ice.opacity(0.32 * alpha)), lineWidth: 1)
        for (i, f) in [0.82, 0.62, 0.4].enumerated() {
            let circle = Path(ellipseIn: CGRect(x: c.x - R * f, y: c.y - R * f, width: R * f * 2, height: R * f * 2))
            ctx.stroke(circle, with: .color(Theme.ice.opacity((0.07 + Double(i) * 0.02) * alpha)),
                       style: StrokeStyle(lineWidth: 1, dash: i == 1 ? [2, 6] : []))
        }
    }

    private func drawSweep(_ ctx: inout GraphicsContext, R: CGFloat, now: Date) {
        let c = CGPoint(x: side / 2, y: side / 2)
        let a = now.timeIntervalSinceReferenceDate / 0.9
        let disc = Path(ellipseIn: CGRect(x: c.x - R * 0.97, y: c.y - R * 0.97, width: R * 1.94, height: R * 1.94))
        ctx.fill(disc, with: .conicGradient(Gradient(stops: [
            .init(color: Theme.ice.opacity(0), location: 0),
            .init(color: Theme.ice.opacity(0), location: 0.86),
            .init(color: Theme.ice.opacity(0.18), location: 0.999),
            .init(color: Theme.ice.opacity(0), location: 1),
        ]), center: c, angle: .radians(a)))
        var beam = Path()
        beam.move(to: c)
        beam.addLine(to: polar(c, a, R * 0.97))
        ctx.stroke(beam, with: .color(Theme.ice.opacity(0.55)), lineWidth: 1)
    }

    private func drawPlanets(_ ctx: inout GraphicsContext, R: CGFloat, alpha: Double, now: Date, input: Input) {
        for (i, tool) in input.tools.enumerated() {
            let u = planet(i, radius: 0.42 * 0.82)
            let p = CGPoint(x: u.x * side, y: u.y * side)
            let l = lit[tool.id] ?? 0
            let gb = Double(input.reports[tool.id]?.bytes ?? 0) / 1e9
            let r = 4 + min(9, gb.squareRoot() * 2) * (0.5 + 0.5 * l)
            if l > 0 {
                let glow = Path(ellipseIn: CGRect(x: p.x - r * 4, y: p.y - r * 4, width: r * 8, height: r * 8))
                ctx.fill(glow, with: .radialGradient(Gradient(colors: [tool.tint.opacity(0.55 * l * alpha), tool.tint.opacity(0)]),
                                                     center: p, startRadius: 0, endRadius: r * 4))
            }
            let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            ctx.fill(dot, with: .color((l > 0 ? tool.tint : Color(hex: "#3A4361")).opacity(alpha)))
            if live == tool.id && input.phase == .scanning {
                let ph = now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.6) / 0.6
                let rr = r + 4 + ph * 16
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2)),
                           with: .color(tool.tint.opacity(alpha * (1 - ph))), lineWidth: 1.2)
            }
            let label = Text(tool.name).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.fg.opacity(alpha * (0.45 + 0.55 * l)))
            ctx.draw(label, at: CGPoint(x: p.x, y: p.y + (p.y > side / 2 ? r + 11 : -r - 11)))
        }
    }

    private func buildSegs(_ input: Input) {
        let live = input.findings.filter { (vanish[$0.id] ?? 0) < 1 }
        let weight: (Finding) -> Double = { f in Double(f.bytes) * (1 - pow(self.vanish[f.id] ?? 0, 2)) }
        let total = live.reduce(0) { $0 + weight($1) }
        guard total > 0 else { segs = []; return }
        var out: [Seg] = []
        var a = -Double.pi / 2
        for tool in input.tools {
            let fs = live.filter { $0.toolId == tool.id }
            guard !fs.isEmpty else { continue }
            let a0 = a
            for f in fs {
                let w = weight(f) / total * 2 * .pi
                out.append(Seg(id: f.id, isTool: false, a0: a, a1: a + w, color: f.risk.ringColor, risk: f.risk))
                a += w
            }
            out.append(Seg(id: "tool:" + tool.id, isTool: true, a0: a0, a1: a, color: tool.tint, risk: nil))
        }
        segs = out
    }

    private func sector(_ r0: CGFloat, _ r1: CGFloat, _ a0: Double, _ a1: Double) -> Path {
        let c = CGPoint(x: side / 2, y: side / 2)
        var p = Path()
        p.addArc(center: c, radius: r1, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
        p.addArc(center: c, radius: r0, startAngle: .radians(a1), endAngle: .radians(a0), clockwise: true)
        p.closeSubpath()
        return p
    }

    private func drawRing(_ ctx: inout GraphicsContext, R: CGFloat, progress: Double, input: Input) {
        let gap = 0.012
        let limit = -Double.pi / 2 + progress * 2 * .pi
        for s in segs where s.a0 < limit {
            let a1 = min(s.a1, limit)
            guard a1 - s.a0 > gap * 1.2 else { continue }
            if s.isTool {
                ctx.fill(sector(R * 0.5, R * 0.6, s.a0 + gap / 2, a1 - gap / 2), with: .color(s.color.opacity(0.85)))
                continue
            }
            let v = vanish[s.id] ?? 0
            let isHover = input.hovered == s.id
            let lit = input.selected.contains(s.id) || s.risk == .protected || s.risk == .compact
            let shrink = v * R * 0.2
            let grow = isHover ? R * 0.03 : 0
            let path = sector(R * 0.64 - shrink, R * 0.86 + grow - shrink, s.a0 + gap / 2, a1 - gap / 2)
            ctx.fill(path, with: .color(s.color.opacity((lit ? 0.92 : 0.26) * (1 - v * 0.85))))
            if s.risk == .compact {
                ctx.drawLayer { l in
                    l.clip(to: path)
                    var hatch = Path()
                    var x = -side
                    while x < side { hatch.move(to: CGPoint(x: x, y: 0)); hatch.addLine(to: CGPoint(x: x + side, y: side)); x += 7 }
                    l.stroke(hatch, with: .color(.black.opacity(0.35)), lineWidth: 2)
                }
            }
            if isHover { ctx.stroke(path, with: .color(.white), lineWidth: 1.5) }
        }
    }

    private func stepClean(now: Date, dt: Double) {
        guard let began = cleanBegan else { return }
        let el = now.timeIntervalSince(began)
        hole = min(1, hole + dt * 2.2)
        if !spawnedClean { spawnClean(); spawnedClean = true }
        let n = Double(max(1, cleanIDs.count))
        for (i, id) in cleanIDs.enumerated() {
            let start = reduceMotion ? 0 : 0.3 + Double(i) * (1.4 / n)
            vanish[id] = max(0, min(1, (el - start) / (reduceMotion ? 0.3 : 1.1)))
        }
        let p = max(0, min(1, (el - 0.3) / (cleanDuration - 0.3)))
        target = cleanBytes * (1 - p)
    }

    private func spawnClean() {
        guard !reduceMotion else { return }
        let n = Double(max(1, cleanIDs.count))
        for (i, id) in cleanIDs.enumerated() {
            guard let s = segs.first(where: { $0.id == id }) else { continue }
            let count = Int(max(8, min(170, (s.a1 - s.a0) * 95)))
            for _ in 0..<count {
                particles.append(Particle(spiral: true,
                                          a: .random(in: s.a0...max(s.a0, s.a1)), r: 0.42 * .random(in: 0.64...0.86),
                                          vr: .random(in: 0.1...0.4), delay: 0.3 + Double(i) * (1.4 / n) + .random(in: 0...0.5),
                                          color: s.color, size: .random(in: 1...2.8)))
            }
        }
    }

    private func drawHole(_ ctx: inout GraphicsContext, R: CGFloat, now: Date) {
        guard hole > 0.01 else { return }
        let c = CGPoint(x: side / 2, y: side / 2)
        let r = R * 0.36 * hole
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 1.9, y: c.y - r * 1.9, width: r * 3.8, height: r * 3.8)),
                 with: .radialGradient(Gradient(stops: [
                    .init(color: Theme.ice.opacity(0), location: 0.2),
                    .init(color: Theme.ice.opacity(0.3), location: 0.5),
                    .init(color: Theme.violet.opacity(0.16), location: 0.65),
                    .init(color: Theme.ice2.opacity(0), location: 1),
                 ]), center: c, startRadius: 0, endRadius: r * 1.9))
        ctx.drawLayer { l in
            l.blendMode = .plusLighter
            let spin = now.timeIntervalSinceReferenceDate * 2
            for k in 0..<3 {
                var arc = Path()
                let rr = r * (1.02 + Double(k) * 0.06)
                arc.addArc(center: c, radius: rr, startAngle: .radians(spin + Double(k) * 2),
                           endAngle: .radians(spin + Double(k) * 2 + .pi * 1.3), clockwise: false)
                let color = [Theme.ice.opacity(0.75), Theme.violet.opacity(0.55), Color.white.opacity(0.5)][k]
                l.stroke(arc, with: .color(color), style: StrokeStyle(lineWidth: 2 - Double(k) * 0.5, lineCap: .round))
            }
        }
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(.black))
    }

    private func drawParticles(_ ctx: inout GraphicsContext, dt: Double) {
        guard !particles.isEmpty else { return }
        let holeR = 0.42 * 0.36 * hole
        var kept: [Particle] = []
        kept.reserveCapacity(particles.count)
        ctx.drawLayer { l in
            l.blendMode = .plusLighter
            for var p in particles {
                var pt: CGPoint
                var alpha: Double
                if !p.spiral {
                    p.t += dt * p.speed
                    if p.t >= 1 { continue }
                    if p.t < 0 { kept.append(p); continue }
                    let u = 1 - p.t, e = p.t * p.t
                    let x: Double = u * u * p.x0 + 2 * u * p.t * p.qx + e * 0.5
                    let y: Double = u * u * p.y0 + 2 * u * p.t * p.qy + e * 0.5
                    pt = CGPoint(x: x * side, y: y * side)
                    alpha = min(1, (1 - p.t) * 2)
                } else {
                    if p.delay > 0 { p.delay -= dt; kept.append(p); continue }
                    p.vr += dt * 0.9
                    p.r -= p.vr * dt * 0.35
                    p.a += dt * (1.2 + 0.1 / max(p.r, 0.02))
                    if p.r <= holeR * 0.9 { continue }
                    let x: Double = 0.5 + cos(p.a) * p.r
                    let y: Double = 0.5 + sin(p.a) * p.r
                    pt = CGPoint(x: x * side, y: y * side)
                    alpha = min(1, (p.r - holeR) / 0.1 + 0.2)
                }
                var seg = Path()
                seg.move(to: p.prev ?? pt)
                seg.addLine(to: pt)
                l.stroke(seg, with: .color(p.color.opacity(alpha)), style: StrokeStyle(lineWidth: p.size, lineCap: .round))
                p.prev = pt
                kept.append(p)
            }
        }
        particles = kept
    }
}
