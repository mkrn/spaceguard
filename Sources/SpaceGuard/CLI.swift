import AppKit
import SwiftUI

/// Headless modes for testing: `--scan [--json]`, `--size <path>...`, `--snapshot <out.png> [--dark]`.
enum CLI {
    static func pad(_ s: String, _ n: Int, right: Bool = false) -> String {
        let s = s.count > n ? String(s.prefix(n - 1)) + "…" : s
        let fill = String(repeating: " ", count: max(0, n - s.count))
        return right ? fill + s : s + fill
    }

    static func scan(json: Bool, incremental: Bool) {
        let disk = Disk.status()
        let scanner = Scanner()
        let items = scanner.run(incremental: incremental) { _ in }
        let sorted = items.sorted { $0.priority > $1.priority }
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let containers = Nesting.containers(items)
        let all = Nesting.bytes(Set(byID.keys), items: byID, containers: containers)
        let recommended = Nesting.bytes(Set(items.filter(\.isRecommended).map(\.id)), items: byID, containers: containers)

        if json {
            let rows: [[String: Any]] = sorted.map { it in
                [
                    "id": it.id, "category": it.category.rawValue, "title": it.title, "project": it.project ?? "",
                    "branch": it.branch ?? "", "agent": it.agent?.label ?? "", "path": it.primaryPath ?? "",
                    "bytes": it.bytes, "files": it.files, "age": Fmt.age(it), "safety": it.safety.label,
                    "note": it.note ?? "", "warning": it.warning ?? "", "recommended": it.isRecommended,
                    "priority": (it.priority * 100).rounded() / 100,
                ]
            }
            if let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]) {
                print(String(decoding: data, as: UTF8.self))
            }
            return
        }

        print("\(pad("PRIO", 6, right: true)) \(pad("SIZE", 9, right: true))  \(pad("AGE", 11)) \(pad("SAFETY", 8)) \(pad("CATEGORY", 11)) ITEM")
        for it in sorted {
            var label = it.title
            if let p = it.project { label += "  [\(p)]" }
            if let b = it.branch { label += "  ⎇ \(b)" }
            if let a = it.agent { label += "  <\(a.label)>" }
            if let w = it.warning { label += "  ⚠ \(w)" } else if let n = it.note { label += "  — \(n)" }
            let mark = it.isRecommended ? "*" : " "
            print("\(pad(String(format: "%.2f", it.priority), 6, right: true)) \(pad(Fmt.bytes(it.bytes), 9, right: true))\(mark) \(pad(Fmt.age(it), 11)) \(pad(it.safety.label, 8)) \(pad(it.category.label, 11)) \(label)")
            print("\(String(repeating: " ", count: 49))\(Fmt.path(it.primaryPath ?? ""))")
        }
        print("")
        print("Disk: \(Fmt.bytes(disk.available)) available (df free \(Fmt.bytes(Disk.statfsFree()))) of \(Fmt.bytes(disk.total))")
        print("\(items.count) items · \(Fmt.bytes(all)) reclaimable · \(Fmt.bytes(recommended)) recommended (*)")
        let t = scanner.timing
        print("Timing: discovery \(Fmt.duration(t.discovery)) (\(scanner.foldersVisited) folders), sizing \(Fmt.duration(t.sizing)) (\(scanner.progress.files.formatted()) files, \(Fmt.bytes(scanner.progress.bytes))), total \(Fmt.duration(t.total)); \(scanner.reused) trees reused from cache")
    }

    static func size(_ paths: [String]) {
        let t = Date()
        let threads = Int(ProcessInfo.processInfo.environment["SPACEGUARD_THREADS"] ?? "") ?? max(8, ProcessInfo.processInfo.activeProcessorCount * 2)
        let results = Sizer(roots: paths).run(threads: threads, qos: .userInitiated)
        for (p, r) in zip(paths, results) {
            print("\(pad(Fmt.bytes(r.bytes), 9, right: true)) reclaimable  \(pad(Fmt.bytes(r.total), 9, right: true)) allocated  \(r.files) files  \(r.bytes / 1024) KiB  \(p)")
        }
        print("took \(Fmt.duration(Date().timeIntervalSince(t)))")
    }

    /// Renders AppIcon.iconset (turn it into .icns with `iconutil -c icns`).
    @MainActor
    static func makeIcon(dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = points * scale
                guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0, bitsPerPixel: 0) else { continue }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                let s = CGFloat(px) / 1024
                let tile = NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s), xRadius: 185 * s, yRadius: 185 * s)
                let top = NSColor(red: 0.16, green: 0.78, blue: 0.62, alpha: 1)
                let bottom = NSColor(red: 0.12, green: 0.42, blue: 0.86, alpha: 1)
                NSGradient(starting: bottom, ending: top)?.draw(in: tile, angle: 90)
                // A shield guarding a drive.
                drawSymbol("shield.fill", pointSize: 470 * s, center: NSPoint(x: 512 * s, y: 505 * s), color: .white)
                drawSymbol("internaldrive.fill", pointSize: 150 * s, center: NSPoint(x: 512 * s, y: 525 * s),
                           color: NSColor(red: 0.13, green: 0.55, blue: 0.78, alpha: 1))
                NSGraphicsContext.restoreGraphicsState()
                let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/" + name))
            }
        }
        print("wrote \(dir)")
    }

    private static func drawSymbol(_ name: String, pointSize: CGFloat, center: NSPoint, color: NSColor) {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
        let size = image.size
        image.draw(in: NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height))
    }

    @MainActor
    static func snapshot(path: String, dark: Bool, cached: Bool, settings: Bool, demo: Bool) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let store = Store.shared   // restores the last saved scan
        store.refreshDisk()
        if demo {
            store.overrideDisk(total: 994_662_584_320, available: 12_400_000_000)
            store.load(Demo.items(), timing: Scanner.Timing(discovery: 3.1, sizing: 23.8, total: 27.2), persist: false)
        } else if !cached {
            let scanner = Scanner()
            let items = scanner.run { _ in }
            store.load(items, timing: scanner.timing)
        }

        let host = NSHostingView(rootView: PanelView(store: store, settings: store.settings, showSettings: settings)
            .background(Color(nsColor: .windowBackgroundColor)))
        host.frame = NSRect(x: 0, y: 0, width: PanelView.width, height: PanelView.height)
        let window = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: PanelView.width, height: PanelView.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = app.appearance
        window.backgroundColor = dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.97, alpha: 1)
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}
