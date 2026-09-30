import Foundation

/// Deletes items. Folders are first renamed into a staging folder (instant on APFS, so the UI is done
/// right away) and then erased in the background. Tools own their own data (simctl, brew, docker).
final class Cleaner: @unchecked Sendable {
    static let shared = Cleaner()

    struct Outcome {
        let id: String
        let ok: Bool
        let error: String?
    }

    let home = NSHomeDirectory()
    let staging: String
    private let purgeQueue = DispatchQueue(label: "spaceguard.purge", qos: .utility)

    /// Never deleted, and neither is anything that contains them.
    private let protectedPaths: Set<String>

    init() {
        staging = home + "/Library/Caches/SpaceGuard/Trash"
        let rel = [
            "", "Library", "Library/Caches", "Library/Application Support", "Library/Developer", "Library/Developer/Xcode",
            "Library/Developer/CoreSimulator", "Library/Android", "Library/Android/sdk", "Library/Logs", "Documents", "Desktop",
            "Downloads", "Pictures", "Movies", "Music", "Applications", ".ssh", ".gnupg", ".config", ".claude", ".claude/projects",
            ".codex", ".codex/sessions", ".cursor", ".local", ".local/share", ".cache", ".npm", ".gradle", ".android", ".cargo",
            ".rustup", ".nvm", ".nvm/versions", "go", "go/pkg",
        ] + ProjectDiscovery.containerNames.map { $0 }
        protectedPaths = Set(rel.map { $0.isEmpty ? NSHomeDirectory() : NSHomeDirectory() + "/" + $0 })
    }

    /// Why a path must not be deleted, or nil if it's fine.
    func refusal(_ path: String) -> String? {
        let p = (path as NSString).standardizingPath
        guard p.hasPrefix("/"), !path.contains("/../") else { return "not an absolute path" }
        if protectedPaths.contains(p) || protectedPaths.contains(where: { $0.hasPrefix(p + "/") }) { return "protected folder" }
        let allowed = [home + "/", "/private/tmp/", "/private/var/folders/", "/tmp/", "/var/folders/"]
        guard allowed.contains(where: { p.hasPrefix($0) }) else { return "outside the folders SpaceGuard manages" }
        if p.hasPrefix(home + "/") {
            let depth = p.dropFirst(home.count + 1).split(separator: "/").count
            if depth < 2 && p.lastPathComponent != "node_modules" && p.lastPathComponent != ".pnpm-store" && !p.lastPathComponent.hasPrefix(".") {
                return "top-level home folder"
            }
        }
        if FS.isDir(p + "/.git") { return "a git repository (only worktrees are removed)" }
        return nil
    }

    func clean(_ items: [CleanItem], progress: @escaping (Int, Int, String) -> Void) -> [Outcome] {
        var outcomes: [Outcome] = []
        for (i, item) in items.enumerated() {
            progress(i + 1, items.count, item.title)
            outcomes.append(clean(item))
        }
        return outcomes
    }

    private func clean(_ item: CleanItem) -> Outcome {
        switch item.action {
        case .remove(let paths):
            for p in paths {
                if let why = refusal(p) { return Outcome(id: item.id, ok: false, error: "\(Fmt.path(p)): \(why)") }
            }
            for p in paths {
                if let err = remove(p) { return Outcome(id: item.id, ok: false, error: err) }
            }
            return Outcome(id: item.id, ok: true, error: nil)
        case .worktree(let path, let commonDir):
            if let why = refusal(path) { return Outcome(id: item.id, ok: false, error: "\(Fmt.path(path)): \(why)") }
            if let err = remove(path) { return Outcome(id: item.id, ok: false, error: err) }
            Git.prune(commonDir: commonDir)
            return Outcome(id: item.id, ok: true, error: nil)
        case .command(let argv):
            guard let exe = argv.first else { return Outcome(id: item.id, ok: false, error: "empty command") }
            let r = Shell.run(exe, Array(argv.dropFirst()), timeout: 1800)
            let message = (r.err.isEmpty ? r.out : r.err).split(separator: "\n").last.map(String.init)
            return Outcome(id: item.id, ok: r.ok, error: r.ok ? nil : (message ?? "exit \(r.code)"))
        }
    }

    /// Returns an error message, or nil once the path is gone (or staged for erasing).
    private func remove(_ path: String) -> String? {
        guard FS.exists(path) else { return nil }
        try? FileManager.default.createDirectory(atPath: staging, withIntermediateDirectories: true)
        let target = staging + "/" + UUID().uuidString.prefix(8) + "-" + path.lastPathComponent
        if rename(path, target) == 0 {
            purge(target)
            return nil
        }
        return erase(path)
    }

    @discardableResult
    private func erase(_ path: String) -> String? {
        var r = Shell.run("/bin/rm", ["-rf", path], timeout: 3600)
        if FS.exists(path) {
            // Read-only trees (Go module cache) and locked files.
            Shell.run("/bin/chmod", ["-R", "u+w", path], timeout: 900)
            Shell.run("/usr/bin/chflags", ["-R", "nouchg", path], timeout: 900)
            r = Shell.run("/bin/rm", ["-rf", path], timeout: 3600)
        }
        guard FS.exists(path) else { return nil }
        let detail = r.err.split(separator: "\n").first.map(String.init) ?? "could not delete"
        return "\(Fmt.path(path)): \(detail)"
    }

    private func purge(_ staged: String) {
        purgeQueue.async { self.erase(staged) }
    }

    /// Finish erasing anything left in staging by a previous run.
    func resumePurge() {
        for c in FS.children(staging, dirsOnly: false) { purge(c.path) }
    }

    /// Blocks until background erasing is done (used by the self-test).
    func waitForPurge() {
        purgeQueue.sync {}
    }
}
