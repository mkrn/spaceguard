import Foundation

/// `SpaceGuard --self-test <empty dir>`: exercises deletion on throwaway fixtures only.
enum SelfTest {
    static func run(in base: String) -> Int32 {
        var failures = 0
        func check(_ ok: Bool, _ what: String) {
            print(ok ? "  ok   \(what)" : "  FAIL \(what)")
            if !ok { failures += 1 }
        }
        func sh(_ cmd: String) { Shell.run("/bin/sh", ["-c", cmd], timeout: 60) }

        let root = base + "/spaceguard-selftest"
        sh("rm -rf '\(root)' && mkdir -p '\(root)'")
        let cleaner = Cleaner.shared

        print("Refusals:")
        let home = NSHomeDirectory()
        for p in [home, home + "/Sites", home + "/Library/Caches", home + "/Library", home + "/.ssh", "/Applications/Xcode.app", "/usr/local", home + "/Documents"] {
            check(cleaner.refusal(p) != nil, "refuses \(Fmt.path(p))")
        }
        sh("mkdir -p '\(root)/mainrepo' && cd '\(root)/mainrepo' && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init")
        check(cleaner.refusal(root + "/mainrepo") != nil, "refuses a main git repository")

        print("Plain folders:")
        sh("mkdir -p '\(root)/proj/node_modules/a/b' && for i in $(seq 1 200); do echo x > '\(root)/proj/node_modules/a/b/f'$i; done")
        sh("mkdir -p '\(root)/gomod/pkg@v1/sub' && echo x > '\(root)/gomod/pkg@v1/sub/f' && chmod -R a-w '\(root)/gomod/pkg@v1'")
        var nm = CleanItem(id: "t1", category: .node, title: "node_modules", safety: .rebuildable, action: .remove([root + "/proj/node_modules"]))
        nm.paths = [root + "/proj/node_modules"]
        let gomod = CleanItem(id: "t2", category: .go, title: "read-only tree", safety: .safe, action: .remove([root + "/gomod"]))
        let out = cleaner.clean([nm, gomod]) { _, _, _ in }
        check(out.allSatisfy(\.ok), "clean reported success \(out.compactMap(\.error))")
        check(!FS.exists(root + "/proj/node_modules"), "node_modules is gone")
        check(FS.exists(root + "/proj"), "its project folder is kept")
        check(!FS.exists(root + "/gomod"), "read-only tree is gone")

        print("Worktree:")
        let repo = root + "/mainrepo"
        let wt = root + "/wt-feature"
        sh("cd '\(repo)' && git worktree add -q -b feature '\(wt)' && mkdir -p '\(wt)/node_modules' && echo x > '\(wt)/node_modules/f'")
        let info = Git.info(root: wt, dotGitIsFile: true)
        check(info?.isLinkedWorktree == true && info?.branch == "feature", "reads worktree branch from .git file")
        check(Git.uncommittedCount(wt) == 1, "sees 1 untracked change")
        let item = CleanItem(id: "t3", category: .worktree, title: "wt", safety: .rebuildable, action: .worktree(path: wt, commonDir: info?.commonDir ?? ""))
        check(cleaner.clean([item]) { _, _, _ in }.first?.ok == true, "worktree removal reported success")
        check(!FS.exists(wt), "worktree folder is gone")
        let list = Shell.run(Git.exe, ["-C", repo, "worktree", "list"]).out
        check(!list.contains("wt-feature"), "git no longer lists the worktree")
        let branches = Shell.run(Git.exe, ["-C", repo, "branch", "--list", "feature"]).out
        check(branches.contains("feature"), "branch 'feature' is kept")

        cleaner.waitForPurge()
        let leftovers = FS.children(cleaner.staging, dirsOnly: false).count
        check(leftovers == 0, "staging area emptied (\(leftovers) left)")
        sh("rm -rf '\(root)'")
        print(failures == 0 ? "All good." : "\(failures) failure(s).")
        return failures == 0 ? 0 : 1
    }
}
