import Darwin
import Foundation

struct ArtifactKind: Sendable {
    let title: String
    let category: Category
    let safety: Safety
    var ageMatters = true
    var note: String? = nil
}

/// Build artifacts and dependency folders recognised inside projects, keyed by folder name plus the
/// marker files sitting next to it.
enum ArtifactRules {
    static let markerFiles: Set<String> = [
        "package.json", "Cargo.toml", "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts",
        "gradlew", "Podfile", "Package.swift", "pubspec.yaml", "pom.xml", "mix.exs", "build.zig", "composer.json",
        "Cartfile", "CMakeLists.txt", "cdk.json", "serverless.yml", "serverless.yaml", "template.yaml", "samconfig.toml",
    ]

    static func match(name: String, markers: Set<String>, path: String) -> ArtifactKind? {
        let js = markers.contains("package.json")
        let gradle = markers.contains("build.gradle") || markers.contains("build.gradle.kts")
            || markers.contains("settings.gradle") || markers.contains("settings.gradle.kts") || markers.contains("gradlew")
        switch name {
        case "node_modules":
            return ArtifactKind(title: "node_modules", category: .node, safety: .rebuildable, note: "reinstall restores it")
        case "bower_components":
            return ArtifactKind(title: "bower_components", category: .node, safety: .rebuildable)
        case ".next":
            return js ? ArtifactKind(title: "Next.js .next", category: .node, safety: .safe) : nil
        case ".nuxt", ".output":
            return js ? ArtifactKind(title: "Nuxt \(name)", category: .node, safety: .safe) : nil
        case ".svelte-kit":
            return js ? ArtifactKind(title: "SvelteKit build", category: .node, safety: .safe) : nil
        case ".turbo":
            return js ? ArtifactKind(title: "Turborepo cache", category: .node, safety: .safe) : nil
        case ".parcel-cache":
            return js ? ArtifactKind(title: "Parcel cache", category: .node, safety: .safe) : nil
        case ".angular":
            return js ? ArtifactKind(title: "Angular cache", category: .node, safety: .safe) : nil
        case ".expo":
            return js ? ArtifactKind(title: "Expo project cache", category: .node, safety: .safe) : nil
        case ".docusaurus":
            return js ? ArtifactKind(title: "Docusaurus cache", category: .node, safety: .safe) : nil
        case ".pnpm-store":
            return ArtifactKind(title: "pnpm store", category: .node, safety: .safe)
        case "target":
            if markers.contains("Cargo.toml") { return ArtifactKind(title: "Rust target/", category: .rust, safety: .safe, note: "cargo build recreates it") }
            if markers.contains("pom.xml") { return ArtifactKind(title: "Maven target/", category: .jvm, safety: .safe) }
            return nil
        case "build":
            if gradle { return ArtifactKind(title: "Gradle build/", category: .android, safety: .safe) }
            if markers.contains("pubspec.yaml") { return ArtifactKind(title: "Flutter build/", category: .flutter, safety: .safe) }
            if markers.contains("*.xcodeproj") || markers.contains("Podfile") { return ArtifactKind(title: "Xcode build/", category: .xcode, safety: .safe) }
            if markers.contains("CMakeLists.txt") { return ArtifactKind(title: "CMake build/", category: .misc, safety: .safe) }
            return nil
        case ".gradle":
            return gradle ? ArtifactKind(title: "Gradle project cache", category: .android, safety: .safe) : nil
        case ".cxx", ".externalNativeBuild":
            return gradle ? ArtifactKind(title: "NDK build cache", category: .android, safety: .safe) : nil
        case "Pods":
            return markers.contains("Podfile") ? ArtifactKind(title: "CocoaPods Pods/", category: .xcode, safety: .rebuildable, note: "pod install restores it") : nil
        case ".build":
            return markers.contains("Package.swift") ? ArtifactKind(title: "SwiftPM .build/", category: .xcode, safety: .safe) : nil
        case "DerivedData":
            return ArtifactKind(title: "DerivedData (in project)", category: .xcode, safety: .safe)
        case "Carthage":
            return markers.contains("Cartfile") ? ArtifactKind(title: "Carthage/", category: .xcode, safety: .rebuildable) : nil
        case ".dart_tool":
            return markers.contains("pubspec.yaml") ? ArtifactKind(title: "Dart tool cache", category: .flutter, safety: .safe) : nil
        case ".venv", "venv", "env", ".env", "virtualenv":
            return access(path + "/pyvenv.cfg", F_OK) == 0
                ? ArtifactKind(title: "Python virtualenv", category: .python, safety: .rebuildable, note: "pip install recreates it") : nil
        case ".tox", ".nox":
            return ArtifactKind(title: "Python \(name) envs", category: .python, safety: .safe)
        case ".mypy_cache", ".pytest_cache", ".ruff_cache":
            return ArtifactKind(title: "Python \(name)", category: .python, safety: .safe)
        case ".terraform":
            return markers.contains("*.tf") ? ArtifactKind(title: "Terraform providers", category: .misc, safety: .rebuildable) : nil
        case "zig-cache", ".zig-cache", "zig-out":
            return markers.contains("build.zig") ? ArtifactKind(title: "Zig \(name)", category: .misc, safety: .safe) : nil
        case "_build", "deps":
            return markers.contains("mix.exs") ? ArtifactKind(title: "Elixir \(name)/", category: .misc, safety: .rebuildable) : nil
        case "vendor":
            return markers.contains("composer.json") ? ArtifactKind(title: "Composer vendor/", category: .misc, safety: .rebuildable, note: "composer install restores it") : nil
        case "cmake-build-debug", "cmake-build-release":
            return ArtifactKind(title: "CLion \(name)", category: .misc, safety: .safe)
        case "cdk.out":
            return markers.contains("cdk.json") ? ArtifactKind(title: "AWS CDK cdk.out", category: .misc, safety: .safe, note: "synthesized on next cdk synth/deploy") : nil
        case ".aws-sam":
            return markers.contains("template.yaml") || markers.contains("samconfig.toml") ? ArtifactKind(title: "AWS SAM build", category: .misc, safety: .safe) : nil
        case ".serverless":
            return markers.contains("serverless.yml") || markers.contains("serverless.yaml") ? ArtifactKind(title: "Serverless build", category: .misc, safety: .safe) : nil
        case "Library":
            return markers.contains("unity") ? ArtifactKind(title: "Unity Library cache", category: .misc, safety: .safe, note: "rebuilt when the project opens") : nil
        default:
            return nil
        }
    }
}

/// Walks the home folder in parallel looking for projects, their build artifacts and git worktrees.
final class ProjectDiscovery: @unchecked Sendable {
    struct Found {
        let path: String
        let kind: ArtifactKind
        let parent: String
        let git: GitInfo?
    }

    struct Job {
        let path: String
        let depth: Int
        let git: GitInfo?
    }

    /// Folders that hold many projects; a .git right at this level (like a repo of everything) is not
    /// a meaningful "project" to attribute things to.
    static let containerNames: Set<String> = [
        "Sites", "Projects", "projects", "Developer", "code", "Code", "dev", "Dev", "src", "repos", "git",
        "GitHub", "Github", "workspace", "Workspace", "work", "Work", "Repositories",
    ]

    /// Top-level home folders never walked: private (TCC-protected), media, cloud-synced or covered elsewhere.
    static let homeSkip: Set<String> = [
        "Library", "Applications", "Movies", "Music", "Pictures", "Public", "Desktop", "Documents", "Downloads",
        "Dropbox", "Google Drive", "OneDrive", "iCloud Drive (Archive)", "Parallels", "VirtualBox VMs",
        "Creative Cloud Files", "Postman", "go",
    ]

    static let skipNames: Set<String> = [
        "node_modules", "bower_components", "Pods", "Carthage", "DerivedData", "build", "dist", "out", "target",
        "vendor", "__pycache__", "site-packages", "coverage", "xcuserdata",
    ]

    static let skipSuffixes: [String] = [
        ".app", ".framework", ".xcframework", ".xcodeproj", ".xcworkspace", ".xcassets", ".lproj", ".bundle",
        ".photoslibrary", ".xcarchive", ".dSYM", ".playground", ".imageset", ".appiconset", ".colorset",
        ".xcresult", ".docc", ".scnassets", ".mlmodelc", ".localized", ".fcpbundle", ".logicx",
    ]

    let home: String
    private let lock = NSLock()
    private(set) var found: [Found] = []
    private(set) var gitRoots: [String: GitInfo] = [:]
    /// Children of `.claude/worktrees`, `.worktrees`, ~/.codex/worktrees etc. (to spot orphans).
    private(set) var agentWorktreeDirs: Set<String> = []
    private(set) var dirsVisited = 0

    init(home: String) {
        self.home = home
    }

    func walk(_ roots: [Job], maxDepth: Int, threads: Int, qos: QualityOfService, cancelled: @escaping () -> Bool) {
        let queue = ParallelQueue<Job>()
        queue.run(roots, threads: threads, qos: qos, sizes: false) { job, reader, children in
            if cancelled() { return }
            self.visit(job, maxDepth: maxDepth, reader: reader, children: &children)
        }
    }

    func addAgentWorktreeDirs(_ dirs: [String]) {
        lock.lock()
        agentWorktreeDirs.formUnion(dirs)
        lock.unlock()
    }

    private func visit(_ job: Job, maxDepth: Int, reader: DirReader, children: inout [Job]) {
        var dirs: [String] = []
        var markers = Set<String>()
        var gitDir = false
        var gitFile = false
        let ok = reader.list(job.path) { e in
            let name = e.nameString
            if e.isDir {
                if name == ".git" {
                    gitDir = true
                    return
                }
                dirs.append(name)
                if name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace") { markers.insert("*.xcodeproj") }
            } else if name == ".git" {
                gitFile = true
            } else if ArtifactRules.markerFiles.contains(name) {
                markers.insert(name)
            } else if name.hasSuffix(".tf") {
                markers.insert("*.tf")
            }
        }
        guard ok else { return }
        if dirs.contains("Assets") && dirs.contains("ProjectSettings") { markers.insert("unity") }

        let isHome = job.path == home
        var git = job.git
        let isContainer = isHome || (job.depth <= 1 && ProjectDiscovery.containerNames.contains(job.path.lastPathComponent))
        if (gitDir || gitFile) && !isContainer, let info = Git.info(root: job.path, dotGitIsFile: gitFile) {
            git = info
            var agentDirs: [String] = []
            if dirs.contains(".claude") { agentDirs += FS.children(job.path + "/.claude/worktrees").map(\.path) }
            if dirs.contains(".worktrees") { agentDirs += FS.children(job.path + "/.worktrees").map(\.path) }
            lock.lock()
            gitRoots[job.path] = info
            agentWorktreeDirs.formUnion(agentDirs)
            lock.unlock()
        }

        var local: [Found] = []
        for name in dirs {
            let path = job.path + "/" + name
            // In the home folder itself only a stray node_modules counts; dot-folders there are tool state.
            if (!isHome || name == "node_modules"), let kind = ArtifactRules.match(name: name, markers: markers, path: path) {
                local.append(Found(path: path, kind: kind, parent: job.path, git: git))
                continue
            }
            if job.depth >= maxDepth || name.hasPrefix(".") || ProjectDiscovery.skipNames.contains(name) { continue }
            if ProjectDiscovery.skipSuffixes.contains(where: { name.hasSuffix($0) }) { continue }
            if isHome && (ProjectDiscovery.homeSkip.contains(name) || name.contains("Cloud") || name.hasSuffix(" Projects")) { continue }
            children.append(Job(path: path, depth: job.depth + 1, git: git))
        }

        lock.lock()
        found.append(contentsOf: local)
        dirsVisited += 1
        lock.unlock()
    }
}
