import Foundation

/// Runs one full scan: known locations + tool reports + project discovery, then measures everything in
/// a single parallel pass. Items stream out through `emit` as soon as their size is known.
final class Scanner: @unchecked Sendable {
    struct Timing {
        var discovery: TimeInterval = 0
        var sizing: TimeInterval = 0
        var total: TimeInterval = 0
    }

    let home = NSHomeDirectory()
    private(set) var phase = "Starting"
    private(set) var timing = Timing()
    private var sizer: Sizer?
    private var discovery: ProjectDiscovery?
    var cancelled = false {
        didSet { sizer?.cancelled = cancelled }
    }

    var progress: (files: Int, bytes: Int64) {
        if let s = sizer { return (s.progressFiles, s.progressBytes) }
        return (0, 0)
    }

    var foldersVisited: Int { discovery?.dirsVisited ?? 0 }
    /// Trees whose size came from the cache in the last incremental scan.
    private(set) var reused = 0

    /// `incremental`: reuse sizes of trees that were quiet last time and look untouched since (see SizeCache).
    func run(extraRoots: [String] = [], qos: QualityOfService = .userInitiated, incremental: Bool = false,
             emit: @escaping ([CleanItem]) -> Void) -> [CleanItem] {
        let t0 = Date()
        // Metadata reads are I/O bound: more requests in flight than cores keeps the SSD busy.
        let threads = Int(ProcessInfo.processInfo.environment["SPACEGUARD_THREADS"] ?? "") ?? max(8, ProcessInfo.processInfo.activeProcessorCount * 2)
        let providers = Providers(home: home)

        // simctl and docker are slow to answer; ask them while we walk the disk.
        var toolItems: [CleanItem] = []
        let toolLock = NSLock()
        let tools = DispatchGroup()
        for job in [providers.simulators, providers.docker] {
            tools.enter()
            DispatchQueue.global(qos: .utility).async {
                let found = job()
                toolLock.lock()
                toolItems += found
                toolLock.unlock()
                emit(found.filter(\.sized))
                tools.leave()
            }
        }

        phase = "Checking known caches"
        var items = providers.knownItems()

        phase = "Finding projects & worktrees"
        let d = ProjectDiscovery(home: home)
        discovery = d
        d.addAgentWorktreeDirs(providers.globalAgentWorktreeDirs())
        var roots = [ProjectDiscovery.Job(path: home, depth: 0, git: nil)]
        roots += extraRoots.filter { FS.isDir($0) && !$0.hasPrefix(home + "/") }.map { ProjectDiscovery.Job(path: $0, depth: 1, git: nil) }
        let isCancelled: () -> Bool = { [unowned self] in self.cancelled }
        d.walk(roots, maxDepth: 6, threads: threads, qos: qos, cancelled: isCancelled)
        let (worktrees, outside) = worktreeItems(d)
        d.walk(outside, maxDepth: 5, threads: threads, qos: qos, cancelled: isCancelled)
        items += worktrees
        items += artifactItems(d)
        timing.discovery = Date().timeIntervalSince(t0)

        tools.wait()
        items += toolItems
        let claimed = Set(items.flatMap(\.paths))
        items += providers.genericCaches(claimed: claimed)
        items += providers.tempFolders(claimed: claimed)
        items = dedupe(items)
        // Things inside backup folders are listed, but never pre-selected.
        for i in items.indices where items[i].paths.first.map(Scanner.isInBackup) == true {
            items[i].inUse = true
            items[i].note = "inside a backup folder"
        }
        if cancelled { return [] }

        // git status for every worktree runs alongside sizing; worktrees are only shown once checked,
        // so nothing with uncommitted work can be picked before we know about it.
        let checks = WorktreeChecks(items)

        phase = "Measuring"
        let t1 = Date()
        items = measure(items, threads: threads, qos: qos, deferred: checks.indices, incremental: incremental, emit: emit)
        timing.sizing = Date().timeIntervalSince(t1)
        if cancelled { return [] }

        phase = "Checking worktrees"
        checks.apply(to: &items)
        emit(checks.indices.map { items[$0] })
        timing.total = Date().timeIntervalSince(t0)
        phase = "Done"
        return items.filter { $0.bytes >= 1_000_000 }
    }

    static func isInBackup(_ path: String) -> Bool {
        let p = path.lowercased()
        return p.contains("/backup") || p.contains(" backup")
    }

    // MARK: Worktrees

    private static func normalize(_ path: String) -> String {
        if path.hasPrefix("/tmp/") || path.hasPrefix("/var/") { return "/private" + path }
        return path
    }

    static func worktreeLabel(_ g: GitInfo) -> String {
        let name = g.root.lastPathComponent
        if name == g.repoName { return "\(name) @ \(g.root.deletingLastPathComponent.lastPathComponent)" }
        if name.lowercased().contains(g.repoName.lowercased()) { return name }
        return "\(g.repoName) › \(name)"
    }

    private func worktreeItem(_ info: GitInfo, path: String) -> CleanItem {
        var it = CleanItem(id: "wt:" + path, category: .worktree, title: Scanner.worktreeLabel(info), safety: .rebuildable,
                           action: .worktree(path: path, commonDir: info.commonDir))
        it.paths = [path]
        it.project = "worktree of \(info.repoName)"
        it.branch = info.branchLabel
        it.agent = Agent.detect(path: path, branch: info.branch)
        it.activity = FS.date(info.lastActivity)
        if info.locked {
            it.safety = .caution
            it.note = "locked by git"
        }
        return it
    }

    /// Linked worktrees of every repository found, plus agent worktree folders git no longer knows.
    private func worktreeItems(_ d: ProjectDiscovery) -> ([CleanItem], [ProjectDiscovery.Job]) {
        var items: [CleanItem] = []
        var jobs: [ProjectDiscovery.Job] = []
        var registered = Set<String>()
        var commons = Set<String>()
        for main in d.gitRoots.values where !main.isLinkedWorktree && commons.insert(main.commonDir).inserted {
            for wt in Git.registeredWorktrees(commonDir: main.commonDir) {
                let path = Scanner.normalize(wt.path)
                registered.insert(path)
                guard FS.isDir(path), let info = d.gitRoots[path] ?? Git.info(root: path, dotGitIsFile: true) else { continue }
                items.append(worktreeItem(info, path: path))
                if d.gitRoots[path] == nil { jobs.append(.init(path: path, depth: 0, git: info)) }
            }
        }
        for dir in d.agentWorktreeDirs.sorted() where !registered.contains(dir) && FS.isDir(dir) {
            var st = stat()
            let hasGit = lstat(dir + "/.git", &st) == 0
            if hasGit && (st.st_mode & S_IFMT) == S_IFDIR { continue }   // a full clone, not a worktree
            if hasGit, let info = Git.info(root: dir, dotGitIsFile: true), FS.isDir(info.gitDir) {
                // Valid worktree of a repository outside the scanned folders.
                items.append(worktreeItem(info, path: dir))
                jobs.append(.init(path: dir, depth: 0, git: info))
                continue
            }
            var it = CleanItem(id: "wt-orphan:" + dir, category: .worktree, title: dir.lastPathComponent, safety: .caution, action: .remove([dir]))
            it.paths = [dir]
            it.project = "orphaned worktree folder"
            it.agent = Agent.detect(path: dir, branch: nil)
            it.note = "git no longer tracks this folder"
            items.append(it)
        }
        return (items, jobs)
    }

    /// Runs `git status` (and a reachability check for detached HEADs) for all worktrees in the background.
    final class WorktreeChecks: @unchecked Sendable {
        let indices: Set<Int>
        private var results: [Int: (dirty: Int?, lostCommits: Bool)] = [:]
        private let lock = NSLock()
        private let group = DispatchGroup()

        init(_ items: [CleanItem]) {
            let targets: [(Int, String, Bool)] = items.indices.compactMap { i in
                guard case .worktree(let path, _) = items[i].action else { return nil }
                return (i, path, items[i].branch?.hasPrefix("detached") == true)
            }
            indices = Set(targets.map(\.0))
            group.enter()
            DispatchQueue.global(qos: .utility).async { [self] in
                DispatchQueue.concurrentPerform(iterations: targets.count) { k in
                    let (i, path, detached) = targets[k]
                    let dirty = Git.uncommittedCount(path)
                    let lost = detached && !Git.headIsOnABranch(path)
                    lock.lock()
                    results[i] = (dirty, lost)
                    lock.unlock()
                }
                group.leave()
            }
        }

        func apply(to items: inout [CleanItem]) {
            group.wait()
            for (i, r) in results {
                if let n = r.dirty, n > 0 {
                    items[i].warning = "\(n) uncommitted change\(n == 1 ? "" : "s")"
                    items[i].safety = .caution
                } else if r.dirty == 0 {
                    items[i].note = items[i].note ?? "clean · branch kept"
                }
                if r.lostCommits {
                    items[i].warning = "commits not on any branch"
                    items[i].safety = .caution
                }
            }
        }
    }

    // MARK: Project artifacts

    private func artifactItems(_ d: ProjectDiscovery) -> [CleanItem] {
        d.found.map { f in
            var it = CleanItem(id: f.path, category: f.kind.category, title: f.kind.title, safety: f.kind.safety, action: .remove([f.path]))
            it.paths = [f.path]
            it.ageMatters = f.kind.ageMatters
            it.note = f.kind.note
            it.project = Scanner.projectLabel(parent: f.parent, git: f.git)
            it.branch = f.git?.branchLabel
            it.agent = Agent.detect(path: f.path, branch: f.git?.branch)
            // Activity = latest of git activity and the project's manifests/lockfiles.
            let manifests = ["package.json", "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "Podfile.lock", "Cargo.lock", "build.gradle"]
            let touched = max(f.git?.lastActivity ?? 0, manifests.map { FS.mtime(f.parent + "/" + $0) }.max() ?? 0)
            it.activity = FS.date(touched)
            return it
        }
    }

    static func projectLabel(parent: String, git: GitInfo?) -> String {
        guard let g = git else { return parent.lastPathComponent }
        let base = g.isLinkedWorktree ? worktreeLabel(g) : g.repoName
        if parent == g.root { return base }
        if parent.hasPrefix(g.root + "/") { return base + "/" + parent.dropFirst(g.root.count + 1) }
        return parent.lastPathComponent
    }

    // MARK: Sizing

    private func dedupe(_ items: [CleanItem]) -> [CleanItem] {
        var seenPaths = Set<String>(), seenIDs = Set<String>()
        return items.filter { it in
            guard seenIDs.insert(it.id).inserted else { return false }
            guard let p = it.paths.first else { return true }
            return seenPaths.insert(p).inserted
        }
    }

    static func finalize(_ it: inout CleanItem, _ r: SizeResult) {
        it.bytes = r.bytes
        it.files = r.files
        it.sized = true
        let content = FS.date(r.newest)
        it.lastUsed = it.useContentAge ? [it.activity, content].compactMap { $0 }.max() : (it.activity ?? content)
        if r.total - r.bytes > 100_000_000 && r.bytes < r.total / 2 {
            let shared = "\(Fmt.bytes(r.total - r.bytes)) more is hard-linked elsewhere"
            it.note = it.note.map { "\($0) · \(shared)" } ?? shared
        }
    }

    private func measure(_ input: [CleanItem], threads: Int, qos: QualityOfService, deferred: Set<Int>, incremental: Bool,
                         emit: @escaping ([CleanItem]) -> Void) -> [CleanItem] {
        var items = input
        var roots: [String] = []
        var owner: [Int] = []
        for (i, it) in items.enumerated() where !it.sized {
            for p in it.paths {
                roots.append(p)
                owner.append(i)
            }
        }
        // Items containing other items' roots can only be finalized after everything is folded.
        let parents = Sizer.nestingParents(roots)
        var waitsForNested = [Bool](repeating: false, count: items.count)
        for p in parents.compactMap({ $0 }) { waitsForNested[owner[p]] = true }
        for i in deferred { waitsForNested[i] = true }

        var nested = [[String]](repeating: [], count: roots.count)
        for (r, p) in parents.enumerated() { if let p { nested[p].append(roots[r]) } }
        let cache = SizeCache.load()
        let reuse = incremental ? cache.reusable(roots, nested: nested) : [:]
        reused = reuse.count

        let snapshot = items
        var remaining = [Int](repeating: 0, count: items.count)
        for o in owner { remaining[o] += 1 }
        var partial = [SizeResult](repeating: SizeResult(), count: items.count)
        var buffer: [CleanItem] = []
        var lastFlush = Date()
        let lock = NSLock()

        let s = Sizer(roots: roots, reuse: reuse)
        s.cancelled = cancelled
        sizer = s
        let results = s.run(threads: threads, qos: qos) { r, res in
            let i = owner[r]
            lock.lock()
            defer { lock.unlock() }
            partial[i].add(res)
            remaining[i] -= 1
            guard remaining[i] == 0, !waitsForNested[i] else { return }
            var it = snapshot[i]
            Scanner.finalize(&it, partial[i])
            buffer.append(it)
            if Date().timeIntervalSince(lastFlush) > 0.25 {
                emit(buffer)
                buffer.removeAll()
                lastFlush = Date()
            }
        }

        if !cancelled { cache.update(roots, raw: s.raw, mtimes: s.rootMtimes, nested: nested, skip: Set(reuse.keys)) }

        var totals = [SizeResult](repeating: SizeResult(), count: items.count)
        for (r, res) in results.enumerated() { totals[owner[r]].add(res) }
        for i in items.indices where !items[i].sized {
            Scanner.finalize(&items[i], totals[i])
        }
        emit(items.indices.filter { !deferred.contains($0) }.map { items[$0] })
        return items
    }
}

/// Per-tree sizes from earlier scans. A tree is reused only if nothing in it had changed for 3 days
/// when it was last walked, its folder mtime is unchanged, the same nested items sit inside it, and
/// the entry is less than 3 days old. Deep edits in a long-quiet tree can be missed until the next
/// full scan; that only affects the number shown, never what gets deleted.
final class SizeCache: @unchecked Sendable {
    struct Entry: Codable {
        var bytes: Int64
        var total: Int64
        var files: Int
        var newest: Int
        var rootMtime: Int
        var nested: [String]
        var measuredAt: Double
    }

    static let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Caches/SpaceGuard/size-cache.json")
    static let quiet: TimeInterval = 3 * 86_400
    static let maxAge: TimeInterval = 3 * 86_400
    private(set) var entries: [String: Entry] = [:]

    static func load() -> SizeCache {
        let c = SizeCache()
        if let data = try? Data(contentsOf: url), let e = try? JSONDecoder().decode([String: Entry].self, from: data) {
            c.entries = e
        }
        return c
    }

    func reusable(_ roots: [String], nested: [[String]]) -> [Int: SizeResult] {
        let now = Date().timeIntervalSince1970
        var out: [Int: SizeResult] = [:]
        for (i, path) in roots.enumerated() {
            guard let e = entries[path],
                  now - e.measuredAt < SizeCache.maxAge,
                  now - TimeInterval(e.newest) > SizeCache.quiet,
                  e.nested == nested[i].sorted(),
                  e.rootMtime == FS.mtime(path), e.rootMtime > 0 else { continue }
            out[i] = SizeResult(bytes: e.bytes, total: e.total, files: e.files, newest: e.newest)
        }
        return out
    }

    func update(_ roots: [String], raw: [SizeResult], mtimes: [Int], nested: [[String]], skip: Set<Int>) {
        let now = Date().timeIntervalSince1970
        var fresh: [String: Entry] = [:]
        for (i, path) in roots.enumerated() where i < raw.count && mtimes[i] > 0 {
            if skip.contains(i), let old = entries[path] {
                fresh[path] = old
            } else {
                let r = raw[i]
                fresh[path] = Entry(bytes: r.bytes, total: r.total, files: r.files, newest: r.newest, rootMtime: mtimes[i],
                                    nested: nested[i].sorted(), measuredAt: now)
            }
        }
        entries = fresh
        guard let data = try? JSONEncoder().encode(fresh) else { return }
        try? FileManager.default.createDirectory(at: SizeCache.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: SizeCache.url, options: .atomic)
    }
}
