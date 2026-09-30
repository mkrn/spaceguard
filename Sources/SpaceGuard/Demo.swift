import Foundation

/// Made-up sample data for README screenshots (`--snapshot out.png --demo`). Never touches the disk.
enum Demo {
    static func items() -> [CleanItem] {
        let home = NSHomeDirectory()

        func item(_ category: Category, _ title: String, _ gb: Double, _ daysAgo: Double?, _ safety: Safety, path: String,
                  project: String? = nil, branch: String? = nil, agent: Agent? = nil, note: String? = nil,
                  warning: String? = nil, ageMatters: Bool = true, inUse: Bool = false, neverUsed: Bool = false) -> CleanItem {
            let full = path.hasPrefix("/") ? path : home + "/" + path
            var it = CleanItem(id: full, category: category, title: title, safety: safety, action: .remove([full]))
            it.paths = [full]
            it.project = project
            it.branch = branch
            it.agent = agent
            it.bytes = Int64(gb * 1e9)
            it.sized = true
            it.lastUsed = daysAgo.map { Date().addingTimeInterval(-$0 * 86_400) }
            it.neverUsed = neverUsed
            it.note = note
            it.warning = warning
            it.ageMatters = ageMatters
            it.inUse = inUse
            return it
        }

        return [
            item(.simulator, "iOS 18.0 simulator runtime", 8.4, nil, .rebuildable, path: "/Library/Developer/CoreSimulator/Volumes/iOS_22A3351",
                 project: "22A3351", note: "re-download in Xcode › Settings › Components", neverUsed: true),
            item(.node, "npm cache", 14.2, 0.2, .safe, path: ".npm/_cacache", note: "re-downloaded on demand", ageMatters: false),
            item(.worktree, "acme-web › fix-login-flow", 5.2, 70, .rebuildable, path: "code/acme-web/.claude/worktrees/fix-login-flow",
                 project: "worktree of acme-web", branch: "claude/fix-login-flow", agent: .claude, note: "clean · branch kept"),
            item(.xcode, "DerivedData", 7.8, 24, .safe, path: "Library/Developer/Xcode/DerivedData/AcmeMobile-bsronpfvmvhfpub",
                 project: "AcmeMobile", branch: "feature/onboarding", note: "~/code/acme-mobile"),
            item(.node, "node_modules", 2.6, 210, .rebuildable, path: "code/landing-2024/node_modules",
                 project: "landing-2024", branch: "main", note: "reinstall restores it"),
            item(.android, "Android NDK", 2.9, 1500, .rebuildable, path: "Library/Android/sdk/ndk/21.1.6352462",
                 project: "21.1.6352462", note: "installed · newest is 28.0.13004108"),
            item(.worktree, "acme-api @ 7c32", 3.9, 120, .rebuildable, path: ".codex/worktrees/7c32/acme-api",
                 project: "worktree of acme-api", branch: "detached @ e0e039fe", agent: .codex, note: "clean · branch kept"),
            item(.xcode, "Xcode build/", 9.8, 1, .safe, path: "code/acme-mobile/ios/build",
                 project: "acme-mobile/ios", branch: "codex/push-notifications", agent: .codex),
            item(.worktree, "acme-web › pricing-review", 1.4, 12, .caution, path: "code/acme-web/.claude/worktrees/pricing-review",
                 project: "worktree of acme-web", branch: "claude/pricing-review", agent: .claude, warning: "3 uncommitted changes"),
            item(.android, "Gradle caches", 4.2, 0.3, .safe, path: ".gradle/caches", note: "re-downloaded on next build", ageMatters: false),
            item(.simulator, "iPhone 17 Pro simulator data", 3.1, 120, .rebuildable,
                 path: "Library/Developer/CoreSimulator/Devices/E4E7C7C5-CE5B-45EE-9B65-BA1BA19E029E",
                 project: "iOS 26.0", note: "erase: removes installed apps & data, keeps the device"),
            item(.ai, "Claude session temp", 2.3, 16, .safe, path: "/private/tmp/claude-501/-Users-you-code-acme-web/3f1c9a2e",
                 project: "acme-web", agent: .claude, note: "scratchpad of a Claude Code session"),
            item(.node, "Next.js .next", 1.4, 180, .safe, path: "code/blog/.next", project: "blog", branch: "main"),
            item(.node, "Node v16.16.0", 1.2, 1400, .rebuildable, path: ".nvm/versions/node/v16.16.0",
                 project: "nvm", note: "installed · nvm install 16.16.0 restores it"),
            item(.xcode, "CocoaPods spec repos", 3.1, 60, .safe, path: ".cocoapods/repos",
                 note: "the trunk CDN is used by default now", ageMatters: false),
            item(.node, "Yarn cache", 3.8, 0.5, .safe, path: "Library/Caches/Yarn", ageMatters: false),
            item(.homebrew, "Old Homebrew versions", 2.4, nil, .safe, path: "/opt/homebrew/Cellar",
                 project: "37 outdated kegs", note: "runs brew cleanup", ageMatters: false),
            item(.ai, "Codex app cache", 2.6, 0.1, .safe, path: "Library/Caches/com.openai.codex", agent: .codex, ageMatters: false),
            item(.ai, "Claude VM bundle", 10.9, 13, .caution, path: "Library/Application Support/Claude/vm_bundles",
                 agent: .claude, note: "re-downloaded when Claude's VM is next used"),
            item(.simulator, "iOS 26.2 simulator runtime", 8.4, 1, .rebuildable, path: "/Library/Developer/CoreSimulator/Volumes/iOS_23C54",
                 project: "23C54", note: "newest iOS runtime", inUse: true),
        ]
    }
}
