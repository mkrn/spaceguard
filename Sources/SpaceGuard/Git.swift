import Foundation

/// What we know about a repository or linked worktree, read straight from the .git files (no git process).
struct GitInfo: Sendable {
    let root: String
    let gitDir: String
    let commonDir: String
    let isLinkedWorktree: Bool
    let branch: String?
    let detachedSHA: String?
    let lastActivity: Int
    let locked: Bool

    var mainRoot: String { commonDir.hasSuffix("/.git") ? commonDir.deletingLastPathComponent : commonDir }
    var repoName: String { mainRoot.lastPathComponent }
    var branchLabel: String? { branch ?? detachedSHA.map { "detached @ \($0)" } }
}

enum Git {
    static let exe = "/usr/bin/git"

    static func info(root: String, dotGitIsFile: Bool) -> GitInfo? {
        var gitDir = root + "/.git"
        if dotGitIsFile {
            guard let s = FS.readSmall(gitDir), s.hasPrefix("gitdir:") else { return nil }
            var p = s.dropFirst(7).trimmingCharacters(in: .whitespacesAndNewlines)
            if !p.hasPrefix("/") { p = root + "/" + p }
            gitDir = (p as NSString).standardizingPath
        }
        var commonDir = gitDir
        if let c = FS.readSmall(gitDir + "/commondir")?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
            commonDir = ((c.hasPrefix("/") ? c : gitDir + "/" + c) as NSString).standardizingPath
        }
        let head = FS.readSmall(gitDir + "/HEAD")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var branch: String?
        var sha: String?
        if head.hasPrefix("ref: ") {
            var ref = String(head.dropFirst(5))
            if ref.hasPrefix("refs/heads/") { ref = String(ref.dropFirst(11)) }
            branch = ref
        } else if head.count >= 7 {
            sha = String(head.prefix(8))
        }
        let activity = [gitDir + "/HEAD", gitDir + "/index", gitDir + "/logs/HEAD"].map(FS.mtime).max() ?? 0
        return GitInfo(
            root: root,
            gitDir: gitDir,
            commonDir: commonDir,
            isLinkedWorktree: dotGitIsFile && commonDir != gitDir && gitDir.contains("/worktrees/"),
            branch: branch,
            detachedSHA: sha,
            lastActivity: activity,
            locked: FS.exists(gitDir + "/locked")
        )
    }

    /// Linked worktrees registered in a repository's common dir: (worktree root, per-worktree git dir).
    static func registeredWorktrees(commonDir: String) -> [(path: String, gitDir: String)] {
        FS.children(commonDir + "/worktrees").compactMap { child in
            guard let s = FS.readSmall(child.path + "/gitdir")?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            let path = s.hasSuffix("/.git") ? String(s.dropLast(5)) : s.deletingLastPathComponent
            return (path, child.path)
        }
    }

    /// Number of uncommitted changes (including untracked files). Uses --no-optional-locks so the index is
    /// not rewritten, which would reset the activity time we rank by.
    static func uncommittedCount(_ worktree: String) -> Int? {
        let r = Shell.run(exe, ["--no-optional-locks", "-C", worktree, "status", "--porcelain=v1", "--untracked-files=normal"], timeout: 20)
        guard r.ok else { return nil }
        return r.out.split(separator: "\n", omittingEmptySubsequences: true).count
    }

    /// Whether HEAD is reachable from some branch or remote ref (matters for detached worktrees).
    static func headIsOnABranch(_ worktree: String) -> Bool {
        let r = Shell.run(exe, ["--no-optional-locks", "-C", worktree, "for-each-ref", "--contains", "HEAD", "--count=1",
                                "--format=%(refname)", "refs/heads", "refs/remotes"], timeout: 20)
        return !r.ok || !r.out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func prune(commonDir: String) {
        Shell.run(exe, ["--git-dir=" + commonDir, "worktree", "prune"], timeout: 30)
    }
}
