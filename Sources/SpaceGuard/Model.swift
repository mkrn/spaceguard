import Foundation

enum Category: String, CaseIterable, Sendable, Codable {
    case worktree, xcode, simulator, android, node, python, rust, go, jvm, ruby, flutter
    case homebrew, docker, misc, ai, ide, temp, appCache

    var label: String {
        switch self {
        case .worktree: return "Worktrees"
        case .xcode: return "Xcode"
        case .simulator: return "Simulators"
        case .android: return "Android"
        case .node: return "Node"
        case .python: return "Python"
        case .rust: return "Rust"
        case .go: return "Go"
        case .jvm: return "JVM"
        case .ruby: return "Ruby"
        case .flutter: return "Flutter"
        case .homebrew: return "Homebrew"
        case .docker: return "Docker"
        case .misc: return "Other dev"
        case .ai: return "AI tools"
        case .ide: return "Editors"
        case .temp: return "Temp"
        case .appCache: return "App caches"
        }
    }

    var symbol: String {
        switch self {
        case .worktree: return "arrow.triangle.branch"
        case .xcode: return "hammer.fill"
        case .simulator: return "iphone"
        case .android: return "candybarphone"
        case .node: return "shippingbox.fill"
        case .python: return "p.circle.fill"
        case .rust: return "gearshape.2.fill"
        case .go: return "g.circle.fill"
        case .jvm: return "cup.and.saucer.fill"
        case .ruby: return "diamond.fill"
        case .flutter: return "bird.fill"
        case .homebrew: return "mug.fill"
        case .docker: return "cube.box.fill"
        case .misc: return "wrench.and.screwdriver.fill"
        case .ai: return "sparkles"
        case .ide: return "curlybraces"
        case .temp: return "clock.arrow.circlepath"
        case .appCache: return "archivebox.fill"
        }
    }
}

enum Safety: Int, Comparable, Sendable, Codable {
    case safe, rebuildable, caution

    static func < (a: Safety, b: Safety) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .safe: return "safe"
        case .rebuildable: return "rebuild"
        case .caution: return "review"
        }
    }

    var explanation: String {
        switch self {
        case .safe: return "Pure cache: tools recreate it automatically."
        case .rebuildable: return "Comes back by reinstalling, rebuilding or re-downloading."
        case .caution: return "May hold state you care about. Review before deleting."
        }
    }
}

/// Which coding agent (if any) produced an item, inferred from its path or branch name.
enum Agent: String, CaseIterable, Sendable, Codable {
    case claude, codex, cursor, conductor, gemini, windsurf, copilot

    var label: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .conductor: return "Conductor"
        case .gemini: return "Gemini"
        case .windsurf: return "Windsurf"
        case .copilot: return "Copilot"
        }
    }

    static func detect(path: String, branch: String?) -> Agent? {
        let p = path.lowercased()
        if p.contains("/.claude/worktrees/") || p.contains("/tmp/claude-") || p.contains("/application support/claude/") { return .claude }
        if p.contains("/.codex/") || p.contains("codex-runtimes") || p.contains("com.openai.codex") { return .codex }
        if p.contains("/.cursor/") || p.contains("/application support/cursor/") { return .cursor }
        if p.contains("/conductor/workspaces/") { return .conductor }
        if p.contains("/.gemini/") { return .gemini }
        if p.contains("/.windsurf/") || p.contains("/.codeium/") { return .windsurf }
        guard let b = branch?.lowercased() else { return nil }
        if b.hasPrefix("claude/") || b.hasPrefix("claude-") || b.hasSuffix("-claude") { return .claude }
        if b.hasPrefix("codex/") || b.contains("codex") { return .codex }
        if b.hasPrefix("cursor/") { return .cursor }
        if b.hasPrefix("copilot/") { return .copilot }
        if b.hasPrefix("conductor/") { return .conductor }
        if b.contains("gemini") { return .gemini }
        return nil
    }
}

enum CleanAction: Sendable, Codable {
    /// Delete these paths (moved aside instantly, then erased in the background).
    case remove([String])
    /// Delete a linked git worktree folder, then `git worktree prune` its repository. The branch is kept.
    case worktree(path: String, commonDir: String)
    /// Let the owning tool do it (simctl, brew, docker, pnpm).
    case command([String])
}

struct CleanItem: Identifiable, Sendable, Codable {
    let id: String
    var category: Category
    var title: String
    var project: String? = nil
    var branch: String? = nil
    var agent: Agent? = nil
    /// Paths measured by the scanner (and usually the ones deleted).
    var paths: [String] = []
    /// Shown in the UI when the item has no measurable path (e.g. simulator runtimes).
    var displayPath: String? = nil
    /// Bytes freed by deleting (hard links shared with the outside are not counted).
    var bytes: Int64 = 0
    var files: Int = 0
    /// Age hint from metadata (git activity, simctl, Xcode). Combined with file mtimes when `useContentAge`.
    var activity: Date? = nil
    var lastUsed: Date? = nil
    var neverUsed = false
    var useContentAge = true
    /// false for global download caches: their freshness says nothing about whether you need them.
    var ageMatters = true
    var safety: Safety
    var note: String? = nil
    var warning: String? = nil
    /// Currently-used version (active Node, newest NDK, ...): listed but never recommended.
    var inUse = false
    var action: CleanAction
    var sized = false

    var primaryPath: String? { paths.first ?? displayPath }

    var ageDays: Double? {
        guard let d = lastUsed else { return nil }
        return max(0, Date().timeIntervalSince(d) / 86_400)
    }

    var effectiveAge: Double { neverUsed ? 400 : (ageDays ?? 30) }

    /// Higher = better candidate. Size weighted by staleness and how safe it is to delete.
    var priority: Double {
        let gb = Double(bytes) / 1_000_000_000
        let staleness = log2(1 + effectiveAge / 7)   // 0 today, 1 at a week, 4 at ~3.5 months
        let ageFactor: Double
        if !ageMatters { ageFactor = 1.6 }
        else if safety == .safe { ageFactor = min(3, 0.6 + 0.4 * staleness) }
        else { ageFactor = min(4, 0.1 + 0.9 * staleness) }
        let safetyFactor: Double = [1.0, 0.75, 0.3][safety.rawValue]
        return gb * ageFactor * safetyFactor * (warning == nil ? 1 : 0.3) * (inUse ? 0.3 : 1)
    }

    var isRecommended: Bool {
        guard sized, bytes >= 20_000_000, warning == nil, !inUse else { return false }
        switch safety {
        case .safe: return !ageMatters || effectiveAge >= 2
        case .rebuildable: return effectiveAge >= 21
        case .caution: return false
        }
    }
}

enum Fmt {
    static func bytes(_ b: Int64) -> String {
        let d = Double(b)
        if d >= 1e12 { return String(format: "%.1f TB", d / 1e12) }
        if d >= 1e11 { return String(format: "%.0f GB", d / 1e9) }
        if d >= 1e9 { return String(format: "%.1f GB", d / 1e9) }
        if d >= 1e6 { return String(format: "%.0f MB", d / 1e6) }
        if d >= 1e3 { return String(format: "%.0f KB", d / 1e3) }
        return "\(b) B"
    }

    /// Menu bar text: "117GB", "9.5GB", "640MB", "1.2TB".
    static func compact(_ b: Int64) -> String {
        let d = Double(b)
        if d >= 1e12 { return String(format: "%.1fTB", d / 1e12) }
        if d >= 1e10 { return String(format: "%.0fGB", d / 1e9) }
        if d >= 1e9 { return String(format: "%.1fGB", d / 1e9) }
        return String(format: "%.0fMB", d / 1e6)
    }

    static func age(_ item: CleanItem) -> String {
        if item.neverUsed { return "never used" }
        guard let d = item.ageDays else { return "" }
        if d < 1 { return "today" }
        if d < 2 { return "yesterday" }
        if d < 14 { return "\(Int(d))d ago" }
        if d < 60 { return "\(Int(d / 7))w ago" }
        if d < 365 { return "\(Int(d / 30))mo ago" }
        return String(format: "%.1fy ago", d / 365)
    }

    static func path(_ p: String) -> String {
        let home = NSHomeDirectory()
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }

    static func duration(_ t: TimeInterval) -> String {
        t < 10 ? String(format: "%.1fs", t) : String(format: "%.0fs", t)
    }
}

extension String {
    var lastPathComponent: String { (self as NSString).lastPathComponent }
    var deletingLastPathComponent: String { (self as NSString).deletingLastPathComponent }
}
