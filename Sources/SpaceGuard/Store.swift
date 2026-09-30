import Combine
import Foundation

enum DiskLevel {
    case ok, low, critical
}

enum Disk {
    /// Total and available bytes on the home volume. "Available" matches Finder (includes purgeable space).
    static func status() -> (total: Int64, available: Int64) {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        if let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
           let total = v.volumeTotalCapacity, let available = v.volumeAvailableCapacityForImportantUsage, total > 0 {
            return (Int64(total), available)
        }
        var s = statfs()
        statfs(NSHomeDirectory(), &s)
        return (Int64(s.f_blocks) * Int64(s.f_bsize), Int64(s.f_bavail) * Int64(s.f_bsize))
    }

    /// Plain free space as `df` reports it (no purgeable space).
    static func statfsFree() -> Int64 {
        var s = statfs()
        statfs(NSHomeDirectory(), &s)
        return Int64(s.f_bavail) * Int64(s.f_bsize)
    }
}

/// Items can sit inside other items (node_modules inside a worktree). Totals count the outermost only.
enum Nesting {
    /// id → ids of the items containing it, nearest first.
    static func containers(_ items: [CleanItem]) -> [String: [String]] {
        let list = items.filter { $0.paths.first != nil }
        let parents = Sizer.nestingParents(list.map { $0.paths[0] })
        var out: [String: [String]] = [:]
        for (i, it) in list.enumerated() {
            var chain: [String] = []
            var p = parents[i]
            while let pi = p {
                chain.append(list[pi].id)
                p = parents[pi]
            }
            if !chain.isEmpty { out[it.id] = chain }
        }
        return out
    }

    static func bytes(_ ids: Set<String>, items: [String: CleanItem], containers: [String: [String]]) -> Int64 {
        ids.reduce(0) { sum, id in
            guard let it = items[id] else { return sum }
            if let chain = containers[id], chain.contains(where: ids.contains) { return sum }
            return sum + it.bytes
        }
    }
}

final class Settings: ObservableObject {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    @Published var lowSpaceGB: Double { didSet { defaults.set(lowSpaceGB, forKey: "lowSpaceGB") } }
    @Published var showFreeInMenuBar: Bool { didSet { defaults.set(showFreeInMenuBar, forKey: "showFreeInMenuBar") } }
    @Published var minItemMB: Int { didSet { defaults.set(minItemMB, forKey: "minItemMB") } }
    @Published var autoScanWhenLow: Bool { didSet { defaults.set(autoScanWhenLow, forKey: "autoScanWhenLow") } }
    @Published var notify: Bool { didSet { defaults.set(notify, forKey: "notify") } }
    @Published var extraRoots: [String] { didSet { defaults.set(extraRoots, forKey: "extraRoots") } }
    @Published var ignored: Set<String> { didSet { defaults.set(Array(ignored), forKey: "ignored") } }

    init() {
        defaults.register(defaults: ["lowSpaceGB": 20.0, "showFreeInMenuBar": true, "minItemMB": 50, "autoScanWhenLow": true, "notify": true])
        lowSpaceGB = defaults.double(forKey: "lowSpaceGB")
        showFreeInMenuBar = defaults.bool(forKey: "showFreeInMenuBar")
        minItemMB = defaults.integer(forKey: "minItemMB")
        autoScanWhenLow = defaults.bool(forKey: "autoScanWhenLow")
        notify = defaults.bool(forKey: "notify")
        extraRoots = defaults.stringArray(forKey: "extraRoots") ?? []
        ignored = Set(defaults.stringArray(forKey: "ignored") ?? [])
    }
}

/// App state. Mutated on the main thread only.
final class Store: ObservableObject {
    static let shared = Store()
    let settings = Settings.shared

    @Published private(set) var total: Int64 = 0
    @Published private(set) var available: Int64 = 0
    @Published private(set) var itemsByID: [String: CleanItem] = [:]
    @Published private(set) var containers: [String: [String]] = [:]
    @Published var selected: Set<String> = []
    @Published private(set) var scanning = false
    @Published private(set) var scanPhase = ""
    @Published private(set) var scanFiles = 0
    @Published private(set) var scanBytes: Int64 = 0
    @Published private(set) var lastScan: Date?
    @Published private(set) var lastTiming: Scanner.Timing?
    @Published private(set) var cleaning = false
    @Published var banner: String?

    private var scanner: Scanner?
    private var progressTimer: Timer?
    private var userTouchedSelection = false
    private let pendingLock = NSLock()
    private var pending: [CleanItem] = []
    private var flushScheduled = false
    /// Cleaned while a scan was running; keeps them from reappearing when that scan reports back.
    private var cleanedIDs = Set<String>()
    private var cleanedPaths: [String] = []

    static let savedScanURL = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Caches/SpaceGuard/last-scan.json")

    init() {
        restore()
    }

    private func wasCleaned(_ item: CleanItem) -> Bool {
        if cleanedIDs.contains(item.id) { return true }
        guard let p = item.paths.first else { return false }
        return cleanedPaths.contains { p == $0 || p.hasPrefix($0 + "/") }
    }

    /// Shows the previous session's results instantly; a fresh scan replaces them.
    private func restore() {
        let url = Store.savedScanURL
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([CleanItem].self, from: data) else { return }
        let when = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        var dict: [String: CleanItem] = [:]
        for it in items where it.primaryPath.map(FS.exists) ?? true { dict[it.id] = it }
        itemsByID = dict
        containers = Nesting.containers(Array(dict.values))
        lastScan = when
        selected = recommendedIDs
    }

    private func save() {
        let items = Array(itemsByID.values)
        DispatchQueue.global(qos: .utility).async {
            guard let data = try? JSONEncoder().encode(items) else { return }
            try? FileManager.default.createDirectory(at: Store.savedScanURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: Store.savedScanURL, options: .atomic)
        }
    }

    var level: DiskLevel {
        let gb = Double(available) / 1e9
        if gb < max(2, settings.lowSpaceGB / 4) { return .critical }
        if gb < settings.lowSpaceGB { return .low }
        return .ok
    }

    var visibleItems: [CleanItem] {
        let minBytes = Int64(settings.minItemMB) * 1_000_000
        return itemsByID.values.filter { $0.bytes >= minBytes && !settings.ignored.contains($0.id) }
    }

    var recommendedIDs: Set<String> { Set(visibleItems.filter(\.isRecommended).map(\.id)) }

    func bytes(of ids: Set<String>) -> Int64 {
        Nesting.bytes(ids, items: itemsByID, containers: containers)
    }

    /// Selected ids that are still listed.
    var activeSelection: Set<String> {
        let visible = Set(visibleItems.map(\.id))
        return selected.intersection(visible)
    }

    func isCovered(_ id: String) -> Bool {
        containers[id]?.contains(where: selected.contains) ?? false
    }

    /// Fixed disk numbers for README screenshots (`--snapshot --demo`).
    func overrideDisk(total: Int64, available: Int64) {
        self.total = total
        self.available = available
    }

    func refreshDisk() {
        let s = Disk.status()
        if s.total != total { total = s.total }
        if s.available != available { available = s.available }
    }

    // MARK: Scanning

    func scan(background: Bool = false, completion: (() -> Void)? = nil) {
        guard !scanning, !cleaning else { return }
        scanning = true
        scanPhase = "Starting"
        scanFiles = 0
        scanBytes = 0
        userTouchedSelection = false
        cleanedIDs = []
        cleanedPaths = []
        let scanner = Scanner()
        self.scanner = scanner
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let s = self.scanner else { return }
            self.scanPhase = s.phase
            let p = s.progress
            self.scanFiles = p.files
            self.scanBytes = p.bytes
        }
        let roots = settings.extraRoots
        let qos: QualityOfService = background ? .utility : .userInitiated
        DispatchQueue.global(qos: background ? .utility : .userInitiated).async { [weak self] in
            let items = scanner.run(extraRoots: roots, qos: qos, incremental: background) { batch in self?.enqueue(batch) }
            DispatchQueue.main.async {
                self?.finishScan(items, scanner: scanner)
                completion?()
            }
        }
    }

    func cancelScan() {
        scanner?.cancelled = true
    }

    private func enqueue(_ batch: [CleanItem]) {
        guard !batch.isEmpty else { return }
        pendingLock.lock()
        pending += batch
        let schedule = !flushScheduled
        flushScheduled = true
        pendingLock.unlock()
        if schedule {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.flush() }
        }
    }

    private func flush() {
        pendingLock.lock()
        let batch = pending
        pending.removeAll()
        flushScheduled = false
        pendingLock.unlock()
        guard scanning, !batch.isEmpty else { return }
        var dict = itemsByID
        for it in batch where it.sized && !wasCleaned(it) { dict[it.id] = it }
        itemsByID = dict
        containers = Nesting.containers(Array(dict.values))
    }

    private func finishScan(_ items: [CleanItem], scanner: Scanner) {
        progressTimer?.invalidate()
        progressTimer = nil
        flush()
        if !scanner.cancelled { load(items, timing: scanner.timing) }
        scanning = false
        self.scanner = nil
        let t = scanner.timing
        let summary = "scan \(scanner.cancelled ? "cancelled" : "done") in \(Fmt.duration(t.total)) (discovery \(Fmt.duration(t.discovery)), sizing \(Fmt.duration(t.sizing)), \(scanner.reused) trees from cache): \(items.count) items, \(scanner.progress.files) files, recommended \(Fmt.bytes(bytes(of: recommendedIDs)))"
        log.notice("\(summary, privacy: .public)")
    }

    /// Replaces the list with a finished scan.
    func load(_ items: [CleanItem], timing: Scanner.Timing?, persist: Bool = true) {
        var dict: [String: CleanItem] = [:]
        for it in items where !wasCleaned(it) { dict[it.id] = it }
        itemsByID = dict
        containers = Nesting.containers(Array(dict.values))
        lastScan = Date()
        lastTiming = timing
        if userTouchedSelection {
            selected = selected.filter { dict[$0] != nil }
        } else {
            selected = recommendedIDs
        }
        if persist { save() }
    }

    // MARK: Selection

    func toggle(_ id: String) {
        userTouchedSelection = true
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    func selectRecommended() {
        userTouchedSelection = true
        selected = recommendedIDs
    }

    func selectNone() {
        userTouchedSelection = true
        selected = []
    }

    func ignore(_ id: String) {
        settings.ignored.insert(id)
        selected.remove(id)
    }

    // MARK: Cleaning

    func clean() {
        let ids = activeSelection
        // Anything inside another selected item goes away with it.
        let targets = ids.compactMap { itemsByID[$0] }
            .filter { !(containers[$0.id]?.contains(where: ids.contains) ?? false) }
            .sorted { $0.bytes > $1.bytes }
        guard !targets.isEmpty else { return }
        let estimate = bytes(of: ids)
        // Worktrees living inside a deleted folder (e.g. Claude session temp) need `git worktree prune`.
        let deleted = targets.flatMap(\.paths)
        let worktreeRepos = Set(itemsByID.values.compactMap { item -> String? in
            guard case .worktree(let path, let common) = item.action,
                  deleted.contains(where: { path.hasPrefix($0 + "/") }) else { return nil }
            return common
        })
        cleaning = true
        banner = "Cleaning…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcomes = Cleaner.shared.clean(targets) { done, count, title in
                DispatchQueue.main.async { self?.banner = "Cleaning \(done) of \(count): \(title)" }
            }
            // Worktrees that lived inside deleted folders (e.g. Claude session temp) leave stale git metadata.
            for common in worktreeRepos { Git.prune(commonDir: common) }
            DispatchQueue.main.async {
                self?.finishClean(outcomes, ids: ids, estimate: estimate)
            }
        }
    }

    private func finishClean(_ outcomes: [Cleaner.Outcome], ids: Set<String>, estimate: Int64) {
        cleaning = false
        let done = Set(outcomes.filter(\.ok).map(\.id))
        cleanedIDs.formUnion(done)
        cleanedPaths += done.compactMap { itemsByID[$0]?.paths }.flatMap { $0 }
        var dict = itemsByID
        for id in dict.keys where done.contains(id) || (containers[id]?.contains(where: done.contains) ?? false) {
            dict.removeValue(forKey: id)
        }
        itemsByID = dict
        containers = Nesting.containers(Array(dict.values))
        selected.subtract(ids)
        let failures = outcomes.filter { !$0.ok }
        if failures.isEmpty {
            banner = "Freed about \(Fmt.bytes(estimate)). Big folders keep erasing in the background."
        } else {
            banner = "Cleaned \(done.count), \(failures.count) failed: \(failures[0].error ?? "unknown error")"
        }
        save()
        refreshDisk()
        for delay in [3.0, 10, 30, 90] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.refreshDisk() }
        }
    }
}
