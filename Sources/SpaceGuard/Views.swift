import AppKit
import ServiceManagement
import SwiftUI

enum SortKey: String, CaseIterable {
    case priority = "Priority"
    case size = "Size"
    case age = "Age"
}

enum Filter: Hashable {
    case all, recommended
    case category(Category)
    case agent(Agent)
}

struct Chip: Identifiable {
    let filter: Filter
    let title: String
    let bytes: Int64
    var id: Filter { filter }
}

extension Category {
    var tint: Color {
        switch self {
        case .worktree: return .purple
        case .xcode: return .blue
        case .simulator: return .indigo
        case .android: return .green
        case .node: return Color(red: 0.25, green: 0.6, blue: 0.3)
        case .python: return Color(red: 0.2, green: 0.45, blue: 0.7)
        case .rust: return Color(red: 0.72, green: 0.35, blue: 0.2)
        case .go: return .cyan
        case .jvm: return Color(red: 0.8, green: 0.35, blue: 0.3)
        case .ruby: return .red
        case .flutter: return Color(red: 0.2, green: 0.55, blue: 0.85)
        case .homebrew: return .orange
        case .docker: return Color(red: 0.1, green: 0.5, blue: 0.9)
        case .misc: return .gray
        case .ai: return Color(red: 0.85, green: 0.47, blue: 0.34)
        case .ide: return .teal
        case .temp: return .brown
        case .appCache: return .gray
        }
    }
}

extension Agent {
    var tint: Color {
        switch self {
        case .claude: return Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: return Color(red: 0.2, green: 0.6, blue: 0.55)
        case .cursor: return .gray
        case .conductor: return .pink
        case .gemini: return .blue
        case .windsurf: return .cyan
        case .copilot: return .purple
        }
    }
}

extension Safety {
    var tint: Color {
        switch self {
        case .safe: return .green
        case .rebuildable: return .blue
        case .caution: return .orange
        }
    }
}

struct PanelView: View {
    static let width: CGFloat = 470
    static let height: CGFloat = 660

    @ObservedObject var store: Store
    @ObservedObject var settings: Settings
    @State private var filter: Filter = .all
    @State private var sort: SortKey = .priority
    @State private var showSettings: Bool
    @State private var confirming = false

    init(store: Store, settings: Settings, showSettings: Bool = false) {
        self.store = store
        self.settings = settings
        _showSettings = State(initialValue: showSettings)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if showSettings {
                SettingsView(store: store, settings: settings)
            } else {
                filterBar
                Divider()
                list
                Divider()
                footer
            }
        }
        .frame(width: Self.width, height: Self.height)
    }

    // MARK: Header

    private var levelColor: Color {
        switch store.level {
        case .ok: return .accentColor
        case .low: return .orange
        case .critical: return .red
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: store.level == .ok ? "internaldrive.fill" : "externaldrive.fill.badge.exclamationmark")
                    .font(.system(size: 22))
                    .foregroundStyle(levelColor)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(Fmt.bytes(store.available)) available")
                        .font(.system(size: 15, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                iconButton("arrow.clockwise", help: "Scan again") { store.scan() }
                    .disabled(store.scanning || store.cleaning)
                iconButton(showSettings ? "xmark.circle" : "gearshape", help: "Settings") { showSettings.toggle() }
                iconButton("power", help: "Quit SpaceGuard") { NSApp.terminate(nil) }
            }
            UsageBar(fraction: store.total > 0 ? 1 - Double(store.available) / Double(store.total) : 0, color: levelColor)
            if store.scanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(scanText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("Stop") { store.cancelScan() }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                }
            }
        }
        .padding(14)
    }

    private var subtitle: String {
        var s = "of \(Fmt.bytes(store.total))"
        if let last = store.lastScan, !store.scanning {
            s += " · scanned \(last.formatted(.relative(presentation: .named)))"
            if let t = store.lastTiming { s += " in \(Fmt.duration(t.total))" }
        }
        return s
    }

    private var scanText: String {
        var s = store.scanPhase
        if store.scanFiles > 0 { s += " · \(store.scanFiles.formatted()) files · \(Fmt.bytes(store.scanBytes))" }
        return s
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    // MARK: Filters

    private var chips: [Chip] {
        let items = store.visibleItems
        func total(_ list: [CleanItem]) -> Int64 { store.bytes(of: Set(list.map(\.id))) }
        var out = [
            Chip(filter: .all, title: "All", bytes: total(items)),
            Chip(filter: .recommended, title: "Recommended", bytes: store.bytes(of: store.recommendedIDs)),
        ]
        let byCategory = Dictionary(grouping: items, by: \.category).map { ($0.key, total($0.value)) }
        out += byCategory.sorted { $0.1 > $1.1 }.map { Chip(filter: .category($0.0), title: $0.0.label, bytes: $0.1) }
        let byAgent = Dictionary(grouping: items.filter { $0.agent != nil }, by: { $0.agent! }).map { ($0.key, total($0.value)) }
        out += byAgent.sorted { $0.1 > $1.1 }.map { Chip(filter: .agent($0.0), title: "by \($0.0.label)", bytes: $0.1) }
        return out
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chips) { chip in
                        ChipButton(chip: chip, selected: filter == chip.filter) { filter = chip.filter }
                    }
                }
                .padding(.horizontal, 14)
            }
            HStack {
                Text("\(rows.count) items")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Sort", selection: $sort) {
                    ForEach(SortKey.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 200)
            }
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 8)
    }

    // MARK: List

    private var rows: [CleanItem] {
        var items = store.visibleItems
        switch filter {
        case .all: break
        case .recommended: items = items.filter(\.isRecommended)
        case .category(let c): items = items.filter { $0.category == c }
        case .agent(let a): items = items.filter { $0.agent == a }
        }
        switch sort {
        case .priority: items.sort { ($0.priority, $0.id) > ($1.priority, $1.id) }
        case .size: items.sort { ($0.bytes, $0.id) > ($1.bytes, $1.id) }
        case .age: items.sort { ($0.effectiveAge, $0.bytes) > ($1.effectiveAge, $1.bytes) }
        }
        return items
    }

    private var list: some View {
        let rows = self.rows
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(rows) { item in
                    ItemRow(item: item, selected: store.selected.contains(item.id), covered: store.isCovered(item.id)) {
                        store.toggle(item.id)
                    }
                    .contextMenu { menu(for: item) }
                    Divider().padding(.leading, 62)
                }
            }
            if rows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: store.scanning ? "magnifyingglass" : "checkmark.seal")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text(store.scanning ? "Looking for dev caches…" : "Nothing here to clean")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 80)
            }
        }
    }

    @ViewBuilder
    private func menu(for item: CleanItem) -> some View {
        if let p = item.primaryPath, FS.exists(p) {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(p, forType: .string)
            }
            Divider()
        }
        Button("Hide This Item") { store.ignore(item.id) }
    }

    // MARK: Footer

    private var footer: some View {
        let selection = store.activeSelection
        let selectedBytes = store.bytes(of: selection)
        return VStack(alignment: .leading, spacing: 8) {
            if let banner = store.banner {
                Text(banner)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if confirming {
                confirmation(selection, bytes: selectedBytes)
            } else {
                HStack(spacing: 8) {
                    Button("Recommended") { store.selectRecommended() }
                        .help("Select stale items that are safe to delete")
                    Button("None") { store.selectNone() }
                    Spacer()
                    Button {
                        confirming = true
                    } label: {
                        Text(selection.isEmpty ? "Clean" : "Clean \(Fmt.bytes(selectedBytes))")
                            .fontWeight(.semibold)
                            .frame(minWidth: 110)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.large)
                    .disabled(selection.isEmpty || store.cleaning)
                }
            }
        }
        .padding(14)
    }

    private func confirmation(_ selection: Set<String>, bytes: Int64) -> some View {
        let items = selection.compactMap { store.itemsByID[$0] }
        let review = items.filter { $0.safety == .caution || $0.warning != nil }
        let dirty = items.filter { $0.warning != nil }
        return VStack(alignment: .leading, spacing: 6) {
            Text("Delete \(items.count) item\(items.count == 1 ? "" : "s") and free about \(Fmt.bytes(bytes))?")
                .font(.system(size: 13, weight: .semibold))
            if !dirty.isEmpty {
                Label("\(dirty.count) with uncommitted or unreachable work: \(dirty.prefix(3).map(\.title).joined(separator: ", "))",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            } else if !review.isEmpty {
                Label("Includes \(review.count) item\(review.count == 1 ? "" : "s") marked review: \(review.prefix(3).map(\.title).joined(separator: ", "))",
                      systemImage: "eye")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            Text("Deleted for good, not moved to the Trash. Worktree branches are kept.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { confirming = false }
                    .keyboardShortcut(.cancelAction)
                Button("Delete") {
                    confirming = false
                    store.clean()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

struct UsageBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(color.gradient).frame(width: max(6, g.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 6)
    }
}

struct ChipButton: View {
    let chip: Chip
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(chip.title).fontWeight(.medium)
                Text(Fmt.bytes(chip.bytes)).opacity(0.7)
            }
            .font(.system(size: 11))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(selected ? Color.accentColor : Color.primary.opacity(0.07)))
            .foregroundStyle(selected ? Color.white : Color.primary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct Tag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.16)))
            .foregroundStyle(color)
            .fixedSize()   // never squeezed: next to a long title it used to wrap one letter per line
    }
}

struct ItemRow: View {
    let item: CleanItem
    let selected: Bool
    let covered: Bool
    let toggle: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: selected || covered ? "checkmark.square.fill" : "square")
                .font(.system(size: 14))
                .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(covered ? 0.6 : 1))
                .padding(.top, 6)
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(item.category.tint.opacity(0.15))
                Image(systemName: item.category.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(item.category.tint)
            }
            .frame(width: 28, height: 28)
            .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    titleLine
                        .lineLimit(1)
                    if let agent = item.agent { Tag(text: agent.label, color: agent.tint) }
                    if item.inUse { Tag(text: "in use", color: .blue) }
                }
                meta
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(Fmt.path(item.primaryPath ?? ""))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                Text(Fmt.bytes(item.bytes))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                Tag(text: item.safety.label, color: item.safety.tint)
                    .help(item.safety.explanation)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(hover ? Color.primary.opacity(0.05) : (selected ? Color.accentColor.opacity(0.07) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .onHover { hover = $0 }
    }

    /// Title and project as one text, so a long title truncates as a whole instead of crushing the project label.
    private var titleLine: Text {
        let title = Text(item.title).font(.system(size: 13, weight: .semibold))
        // A worktree's title already names its repo; "worktree of <repo>" would only repeat it.
        guard let project = item.project, item.category != .worktree else { return title }
        return title + Text("  " + project).font(.system(size: 12)).foregroundColor(.secondary)
    }

    private var meta: Text {
        var parts: [Text] = []
        if let branch = item.branch {
            parts.append(Text(Image(systemName: "arrow.triangle.branch")) + Text(" " + branch))
        }
        let age = Fmt.age(item)
        if !age.isEmpty {
            let old = item.neverUsed || item.effectiveAge > 90
            parts.append(Text(age).foregroundColor(old ? .orange : .secondary))
        }
        if let warning = item.warning {
            parts.append((Text(Image(systemName: "exclamationmark.triangle.fill")) + Text(" " + warning)).foregroundColor(.orange))
        } else if let note = item.note {
            parts.append(Text(note))
        }
        guard var text = parts.first else { return Text(" ") }
        for part in parts.dropFirst() { text = text + Text("  ·  ") + part }
        return text
    }
}

struct SettingsView: View {
    @ObservedObject var store: Store
    @ObservedObject var settings: Settings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Low disk alerts") {
                Picker("Warn when free space is below", selection: $settings.lowSpaceGB) {
                    ForEach([10.0, 20, 50, 100], id: \.self) { Text("\(Int($0)) GB").tag($0) }
                }
                Toggle("Send a notification", isOn: $settings.notify)
                Toggle("Scan automatically when space runs low", isOn: $settings.autoScanWhenLow)
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
            Section("List") {
                Picker("Hide items smaller than", selection: $settings.minItemMB) {
                    ForEach([1, 10, 50, 100, 500], id: \.self) { Text("\($0) MB").tag($0) }
                }
                HStack {
                    Text("\(settings.ignored.count) hidden item\(settings.ignored.count == 1 ? "" : "s")")
                    Spacer()
                    Button("Show Again") { settings.ignored = [] }
                        .disabled(settings.ignored.isEmpty)
                }
            }
            Section {
                ForEach(settings.extraRoots, id: \.self) { root in
                    HStack {
                        Text(Fmt.path(root)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button {
                            settings.extraRoots.removeAll { $0 == root }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button("Add Folder…") { addFolder() }
            } header: {
                Text("Extra project folders")
            } footer: {
                Text("Your home folder is scanned automatically, except Documents, Desktop, Downloads, Library and media folders.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Text("SpaceGuard \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Link("github.com/mkrn/spaceguard", destination: URL(string: "https://github.com/mkrn/spaceguard")!)
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Scan"
        NSApp.activate()
        if panel.runModal() == .OK {
            let new = panel.urls.map(\.path).filter { !settings.extraRoots.contains($0) }
            settings.extraRoots += new
        }
    }
}
