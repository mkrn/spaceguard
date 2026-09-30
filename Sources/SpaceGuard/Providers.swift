import AppKit
import Foundation

/// Well-known cache and toolchain locations, plus tool-reported items (simctl, docker, brew).
struct Providers {
    let home: String

    func abs(_ rel: String) -> String { rel.hasPrefix("/") ? rel : home + "/" + rel }

    func item(_ path: String, _ title: String, _ category: Category, _ safety: Safety) -> CleanItem {
        var it = CleanItem(id: path, category: category, title: title, safety: safety, action: .remove([path]))
        it.paths = [path]
        it.agent = Agent.detect(path: path, branch: nil)
        return it
    }

    // MARK: Whole-folder caches

    struct Loc {
        let path: String
        let title: String
        let category: Category
        let safety: Safety
        var ageMatters = false
        var note: String? = nil
    }

    static let locations: [Loc] = [
        // Xcode
        Loc(path: "Library/Developer/Xcode/UserData/Previews", title: "SwiftUI Previews data", category: .xcode, safety: .safe),
        Loc(path: "Library/Developer/Xcode/DocumentationCache", title: "Xcode documentation cache", category: .xcode, safety: .safe),
        Loc(path: "Library/Developer/Xcode/DocumentationIndex", title: "Xcode documentation index", category: .xcode, safety: .safe),
        Loc(path: "Library/Developer/Xcode/Products", title: "Xcode Products", category: .xcode, safety: .safe),
        Loc(path: "Library/Developer/Xcode/iOS Device Logs", title: "iOS device logs", category: .xcode, safety: .safe),
        Loc(path: "Library/Developer/Xcode/DeviceLogs", title: "Device logs", category: .xcode, safety: .safe),
        Loc(path: "Library/Developer/DVTDownloads", title: "Xcode downloads", category: .xcode, safety: .safe),
        Loc(path: "Library/Developer/DeveloperDiskImages", title: "Developer disk images", category: .xcode, safety: .safe),
        Loc(path: "Library/Caches/com.apple.dt.Xcode", title: "Xcode cache", category: .xcode, safety: .safe),
        Loc(path: "Library/Caches/org.swift.swiftpm", title: "SwiftPM cache", category: .xcode, safety: .safe),
        Loc(path: "Library/Caches/CocoaPods", title: "CocoaPods cache", category: .xcode, safety: .safe),
        Loc(path: ".cocoapods/repos", title: "CocoaPods spec repos", category: .xcode, safety: .safe, note: "the trunk CDN is used by default now"),
        Loc(path: "Library/Caches/org.carthage.CarthageKit", title: "Carthage cache", category: .xcode, safety: .safe),
        // Simulators
        Loc(path: "Library/Developer/CoreSimulator/Caches", title: "Simulator caches", category: .simulator, safety: .safe),
        Loc(path: "Library/Developer/XCTestDevices", title: "Test-runner simulator clones", category: .simulator, safety: .safe),
        Loc(path: "Library/Developer/XCPGDevices", title: "Playground simulators", category: .simulator, safety: .safe),
        Loc(path: "Library/Logs/CoreSimulator", title: "Simulator logs", category: .simulator, safety: .safe),
        // Android / Gradle
        Loc(path: ".gradle/caches", title: "Gradle caches", category: .android, safety: .safe, note: "re-downloaded on next build"),
        Loc(path: ".gradle/daemon", title: "Gradle daemon logs", category: .android, safety: .safe),
        Loc(path: ".gradle/native", title: "Gradle native libs", category: .android, safety: .safe),
        Loc(path: ".gradle/kotlin-profile", title: "Kotlin build reports", category: .android, safety: .safe),
        Loc(path: ".android/cache", title: "Android cache", category: .android, safety: .safe),
        Loc(path: ".android/build-cache", title: "Android build cache", category: .android, safety: .safe),
        Loc(path: ".konan", title: "Kotlin/Native toolchains", category: .android, safety: .rebuildable, ageMatters: true),
        // JVM
        Loc(path: ".m2/repository", title: "Maven repository", category: .jvm, safety: .safe),
        Loc(path: ".ivy2/cache", title: "Ivy cache", category: .jvm, safety: .safe),
        Loc(path: ".sbt/boot", title: "sbt boot", category: .jvm, safety: .safe),
        Loc(path: "Library/Caches/Coursier", title: "Coursier cache", category: .jvm, safety: .safe),
        Loc(path: ".cache/coursier", title: "Coursier cache", category: .jvm, safety: .safe),
        // Node
        Loc(path: ".npm/_cacache", title: "npm cache", category: .node, safety: .safe, note: "re-downloaded on demand"),
        Loc(path: ".npm/_npx", title: "npx cache", category: .node, safety: .safe),
        Loc(path: ".npm/_logs", title: "npm logs", category: .node, safety: .safe),
        Loc(path: ".npm/_prebuilds", title: "npm prebuilds", category: .node, safety: .safe),
        Loc(path: "Library/Caches/Yarn", title: "Yarn cache", category: .node, safety: .safe),
        Loc(path: ".yarn/berry/cache", title: "Yarn Berry cache", category: .node, safety: .safe),
        Loc(path: ".cache/yarn", title: "Yarn cache", category: .node, safety: .safe),
        Loc(path: "Library/Caches/pnpm", title: "pnpm metadata cache", category: .node, safety: .safe),
        Loc(path: ".bun/install/cache", title: "Bun cache", category: .node, safety: .safe),
        Loc(path: "Library/Caches/deno", title: "Deno cache", category: .node, safety: .safe),
        Loc(path: ".nvm/.cache", title: "nvm downloads", category: .node, safety: .safe),
        Loc(path: "Library/Caches/node-gyp", title: "node-gyp headers", category: .node, safety: .safe),
        Loc(path: ".node-gyp", title: "node-gyp headers", category: .node, safety: .safe),
        Loc(path: ".cache/node-gyp", title: "node-gyp headers", category: .node, safety: .safe),
        Loc(path: ".electron-gyp", title: "electron-gyp headers", category: .node, safety: .safe),
        Loc(path: "Library/Caches/electron", title: "Electron downloads", category: .node, safety: .safe),
        Loc(path: "Library/Caches/electron-builder", title: "electron-builder cache", category: .node, safety: .safe),
        Loc(path: "Library/Caches/ms-playwright", title: "Playwright browsers", category: .node, safety: .rebuildable, note: "npx playwright install"),
        Loc(path: ".cache/ms-playwright", title: "Playwright browsers", category: .node, safety: .rebuildable, note: "npx playwright install"),
        Loc(path: ".cache/puppeteer", title: "Puppeteer browsers", category: .node, safety: .rebuildable, note: "re-downloaded on install"),
        Loc(path: "Library/Caches/Cypress", title: "Cypress binaries", category: .node, safety: .rebuildable),
        Loc(path: ".cache/node/corepack", title: "Corepack cache", category: .node, safety: .safe),
        Loc(path: ".cache/prisma", title: "Prisma engines", category: .node, safety: .safe),
        Loc(path: "Library/Caches/typescript", title: "TypeScript cache", category: .node, safety: .safe),
        Loc(path: ".expo/ios-simulator-app-cache", title: "Expo simulator apps", category: .node, safety: .safe),
        Loc(path: ".expo/android-apk-cache", title: "Expo Android APKs", category: .node, safety: .safe),
        Loc(path: ".expo/expo-go", title: "Expo Go builds", category: .node, safety: .safe),
        Loc(path: ".cache/firebase", title: "Firebase emulators", category: .node, safety: .rebuildable),
        // Python
        Loc(path: "Library/Caches/pip", title: "pip cache", category: .python, safety: .safe),
        Loc(path: ".cache/pip", title: "pip cache", category: .python, safety: .safe),
        Loc(path: ".cache/uv", title: "uv cache", category: .python, safety: .safe),
        Loc(path: "Library/Caches/pypoetry", title: "Poetry cache", category: .python, safety: .safe),
        Loc(path: ".cache/pre-commit", title: "pre-commit envs", category: .python, safety: .safe),
        Loc(path: "miniconda3/pkgs", title: "Conda package cache", category: .python, safety: .safe),
        Loc(path: "anaconda3/pkgs", title: "Conda package cache", category: .python, safety: .safe),
        Loc(path: "miniforge3/pkgs", title: "Conda package cache", category: .python, safety: .safe),
        Loc(path: "opt/anaconda3/pkgs", title: "Conda package cache", category: .python, safety: .safe),
        Loc(path: ".conda/pkgs", title: "Conda package cache", category: .python, safety: .safe),
        // Rust / Go / Ruby / Dart / .NET
        Loc(path: ".cargo/registry", title: "Cargo registry", category: .rust, safety: .safe),
        Loc(path: ".cargo/git", title: "Cargo git checkouts", category: .rust, safety: .safe),
        Loc(path: "Library/Caches/Mozilla.sccache", title: "sccache", category: .rust, safety: .safe),
        Loc(path: "Library/Caches/go-build", title: "Go build cache", category: .go, safety: .safe),
        Loc(path: "go/pkg/mod", title: "Go module cache", category: .go, safety: .safe, note: "re-downloaded on demand"),
        Loc(path: ".gem/specs", title: "RubyGems specs cache", category: .ruby, safety: .safe),
        Loc(path: ".bundle/cache", title: "Bundler cache", category: .ruby, safety: .safe),
        Loc(path: ".pub-cache", title: "Dart/Flutter packages", category: .flutter, safety: .rebuildable, note: "flutter pub get restores it"),
        Loc(path: ".dartServer", title: "Dart analysis cache", category: .flutter, safety: .safe),
        Loc(path: ".nuget/packages", title: "NuGet packages", category: .misc, safety: .safe),
        // Homebrew
        Loc(path: "Library/Caches/Homebrew", title: "Homebrew downloads", category: .homebrew, safety: .safe),
        Loc(path: "Library/Logs/Homebrew", title: "Homebrew logs", category: .homebrew, safety: .safe),
        // Editors
        Loc(path: "Library/Caches/vscode-cpptools", title: "C/C++ IntelliSense cache", category: .ide, safety: .safe),
        Loc(path: "Library/Application Support/Code/User/workspaceStorage", title: "VS Code workspace storage", category: .ide, safety: .caution, ageMatters: true),
        Loc(path: "Library/Application Support/Cursor/User/workspaceStorage", title: "Cursor workspace storage", category: .ide, safety: .caution, ageMatters: true, note: "holds Cursor chat history"),
        Loc(path: "Library/Logs/JetBrains", title: "JetBrains logs", category: .ide, safety: .safe),
        // AI tools
        Loc(path: "Library/Caches/claude-cli-nodejs", title: "Claude Code logs", category: .ai, safety: .safe),
        Loc(path: ".claude/debug", title: "Claude Code debug logs", category: .ai, safety: .safe),
        Loc(path: "Library/Application Support/Claude/simulator-builds", title: "Claude simulator builds", category: .ai, safety: .safe, ageMatters: true),
        Loc(path: "Library/Application Support/Claude/sim-recordings", title: "Claude simulator recordings", category: .ai, safety: .caution, ageMatters: true),
        Loc(path: "Library/Application Support/Claude/vm_bundles", title: "Claude VM bundle", category: .ai, safety: .caution, ageMatters: true, note: "re-downloaded when Claude's VM is next used"),
        Loc(path: "Library/Caches/com.openai.codex", title: "Codex app cache", category: .ai, safety: .safe),
        Loc(path: ".codex/.tmp", title: "Codex temp files", category: .ai, safety: .safe, ageMatters: true),
        Loc(path: ".cache/huggingface", title: "Hugging Face models", category: .ai, safety: .caution, ageMatters: true),
        Loc(path: ".cache/torch", title: "PyTorch hub models", category: .ai, safety: .caution, ageMatters: true),
        Loc(path: ".cache/whisper", title: "Whisper models", category: .ai, safety: .caution, ageMatters: true),
        Loc(path: ".ollama/models", title: "Ollama models", category: .ai, safety: .caution, ageMatters: true),
        Loc(path: ".lmstudio/models", title: "LM Studio models", category: .ai, safety: .caution, ageMatters: true),
        Loc(path: ".cache/lm-studio", title: "LM Studio models", category: .ai, safety: .caution, ageMatters: true),
    ]

    /// Electron apps keep several regenerable caches side by side; each app becomes one item.
    static let electronCacheDirs = ["Cache", "Code Cache", "GPUCache", "CachedData", "CachedExtensionVSIXs", "CachedProfilesData",
                                    "DawnGraphiteCache", "DawnWebGPUCache", "Service Worker/CacheStorage", "logs"]
    static let electronApps: [(dir: String, title: String, category: Category)] = [
        ("Library/Application Support/Code", "VS Code caches", .ide),
        ("Library/Application Support/Cursor", "Cursor caches", .ide),
        ("Library/Application Support/Windsurf", "Windsurf caches", .ide),
        ("Library/Application Support/Claude", "Claude app caches", .ai),
    ]

    func knownItems() -> [CleanItem] {
        var items: [CleanItem] = []
        for loc in Self.locations {
            let p = abs(loc.path)
            guard FS.isDir(p) else { continue }
            var it = item(p, loc.title, loc.category, loc.safety)
            it.ageMatters = loc.ageMatters
            it.note = loc.note
            items.append(it)
        }
        for app in Self.electronApps {
            let base = abs(app.dir)
            let paths = Self.electronCacheDirs.map { base + "/" + $0 }.filter(FS.isDir)
            guard !paths.isEmpty else { continue }
            var it = CleanItem(id: base + "#caches", category: app.category, title: app.title, safety: .safe, action: .remove(paths))
            it.paths = paths
            it.agent = Agent.detect(path: base + "/", branch: nil)
            it.ageMatters = false
            it.note = "Electron caches, rebuilt automatically"
            items.append(it)
        }
        items += derivedData()
        items += archives()
        items += deviceSupport()
        items += androidSDK()
        items += androidEmulators()
        items += gradleExtras()
        items += androidStudioAndJetBrains()
        items += nodeVersions()
        items += otherToolchains()
        items += aiToolVersions()
        items += homebrewOld()
        items += claudeSessionTemp()
        items += tmpdirCaches()
        return items
    }

    // MARK: Xcode

    private func derivedData() -> [CleanItem] {
        let base = abs("Library/Developer/Xcode/DerivedData")
        var items: [CleanItem] = []
        var shared: [String] = []
        for c in FS.children(base) {
            if c.name.hasSuffix(".noindex") {
                shared.append(c.path)
                continue
            }
            var it = item(c.path, "DerivedData", .xcode, .safe)
            let plist = Self.plist(c.path + "/info.plist")
            if let ws = plist?["WorkspacePath"] as? String {
                it.project = ((ws as NSString).lastPathComponent as NSString).deletingPathExtension
                if let g = Self.gitContext(ws) {
                    it.branch = g.branchLabel
                    it.agent = Agent.detect(path: ws, branch: g.branch)
                }
                if FS.exists(ws) {
                    it.note = Fmt.path(ws.deletingLastPathComponent)
                } else {
                    it.note = "its project no longer exists"
                    it.ageMatters = false
                }
            } else {
                it.project = c.name.split(separator: "-").dropLast().joined(separator: "-")
            }
            it.activity = plist?["LastAccessedDate"] as? Date
            items.append(it)
        }
        if !shared.isEmpty {
            var it = CleanItem(id: base + "#shared", category: .xcode, title: "DerivedData shared caches", safety: .safe, action: .remove(shared))
            it.paths = shared
            it.ageMatters = false
            it.note = "module & compilation caches"
            items.append(it)
        }
        return items
    }

    private func archives() -> [CleanItem] {
        var items: [CleanItem] = []
        for day in FS.children(abs("Library/Developer/Xcode/Archives")) {
            for a in FS.children(day.path) where a.name.hasSuffix(".xcarchive") {
                var it = item(a.path, "Xcode archive", .xcode, .caution)
                let info = Self.plist(a.path + "/Info.plist")
                let name = info?["Name"] as? String ?? (a.name as NSString).deletingPathExtension
                let props = info?["ApplicationProperties"] as? [String: Any]
                if let v = props?["CFBundleShortVersionString"] as? String {
                    let build = props?["CFBundleVersion"] as? String
                    it.project = "\(name) \(v)" + (build.map { " (\($0))" } ?? "")
                } else {
                    it.project = name
                }
                it.note = "dSYMs for crash symbolication of shipped builds"
                it.activity = (info?["CreationDate"] as? Date) ?? FS.date(a.mtime)
                it.useContentAge = false
                items.append(it)
            }
        }
        return items
    }

    private func deviceSupport() -> [CleanItem] {
        var items: [CleanItem] = []
        for os in ["iOS", "watchOS", "tvOS", "visionOS", "macOS"] {
            for c in FS.children(abs("Library/Developer/Xcode/\(os) DeviceSupport")) {
                var it = item(c.path, "\(os) device support", .xcode, .safe)
                it.project = c.name
                it.note = "re-copied when that device reconnects"
                items.append(it)
            }
        }
        return items
    }

    // MARK: Android

    private var androidSDKPath: String? {
        let env = ProcessInfo.processInfo.environment
        return [env["ANDROID_HOME"], env["ANDROID_SDK_ROOT"], abs("Library/Android/sdk")].compactMap { $0 }.first(where: FS.isDir)
    }

    /// system image path (relative to the SDK) → names of AVDs using it.
    private func avdImageUsers() -> [String: [String]] {
        var users: [String: [String]] = [:]
        for c in FS.children(abs(".android/avd")) where c.name.hasSuffix(".avd") {
            guard let config = FS.readSmall(c.path + "/config.ini", limit: 65536) else { continue }
            for line in config.split(separator: "\n") where line.hasPrefix("image.sysdir.1") {
                guard let eq = line.firstIndex(of: "=") else { continue }
                var rel = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                while rel.hasSuffix("/") { rel.removeLast() }
                users[rel, default: []].append(String(c.name.dropLast(4)))
            }
        }
        return users
    }

    private func androidSDK() -> [CleanItem] {
        guard let sdk = androidSDKPath else { return [] }
        var items: [CleanItem] = []
        let users = avdImageUsers()
        for api in FS.children(sdk + "/system-images") {
            for tag in FS.children(api.path) {
                for abi in FS.children(tag.path) {
                    var it = item(abi.path, "Android system image", .android, .rebuildable)
                    it.project = "\(api.name) · \(tag.name) · \(abi.name)"
                    if let names = users["system-images/\(api.name)/\(tag.name)/\(abi.name)"] {
                        it.inUse = true
                        it.note = "used by AVD " + names.joined(separator: ", ")
                    } else {
                        it.note = "no emulator uses it"
                    }
                    it.activity = FS.date(abi.mtime)
                    it.useContentAge = false
                    items.append(it)
                }
            }
        }
        for (dir, title) in [("ndk", "Android NDK"), ("build-tools", "Android build-tools"), ("platforms", "Android platform"), ("cmake", "Android CMake")] {
            let versions = FS.children(sdk + "/" + dir).sorted { Self.versionLess($0.name, $1.name) }
            guard let newest = versions.last else { continue }
            for v in versions {
                var it = item(v.path, title, .android, .rebuildable)
                it.project = v.name
                it.activity = FS.date(v.mtime)
                it.useContentAge = false
                if v.name == newest.name {
                    it.inUse = true
                    it.note = "newest installed"
                } else {
                    it.note = "installed · newest is \(newest.name)"
                }
                items.append(it)
            }
        }
        for s in FS.children(sdk + "/sources") {
            var it = item(s.path, "Android sources", .android, .safe)
            it.project = s.name
            items.append(it)
        }
        if FS.isDir(sdk + "/tools") {
            var it = item(sdk + "/tools", "Obsolete SDK tools/", .android, .rebuildable)
            it.note = "replaced by cmdline-tools"
            items.append(it)
        }
        return items
    }

    private func androidEmulators() -> [CleanItem] {
        let dir = abs(".android/avd")
        return FS.children(dir).filter { $0.name.hasSuffix(".avd") }.map { c in
            let name = String(c.name.dropLast(4))
            var it = item(c.path, "Android emulator", .android, .caution)
            it.project = name.replacingOccurrences(of: "_", with: " ")
            it.action = .remove([c.path, dir + "/" + name + ".ini"])
            it.note = "emulator disk with its apps & data"
            return it
        }
    }

    private func gradleExtras() -> [CleanItem] {
        var items: [CleanItem] = []
        for c in FS.children(abs(".gradle/wrapper/dists")) {
            var it = item(c.path, "Gradle distribution", .android, .safe)
            it.project = c.name
            it.note = "gradlew re-downloads it when needed"
            items.append(it)
        }
        for c in FS.children(abs(".gradle/jdks")) {
            var it = item(c.path, "Gradle-provisioned JDK", .jvm, .rebuildable)
            it.project = c.name
            items.append(it)
        }
        return items
    }

    private func androidStudioAndJetBrains() -> [CleanItem] {
        var items: [CleanItem] = []
        for c in FS.children(abs("Library/Caches/Google")) where c.name.hasPrefix("AndroidStudio") {
            var it = item(c.path, "Android Studio cache", .android, .safe)
            it.project = c.name
            items.append(it)
        }
        let settings = FS.children(abs("Library/Application Support/Google"))
            .filter { $0.name.hasPrefix("AndroidStudio") }
            .sorted { Self.versionLess($0.name, $1.name) }
        for c in settings.dropLast() {
            var it = item(c.path, "Old Android Studio settings", .android, .safe)
            it.project = c.name
            it.note = "newest is \(settings.last!.name)"
            items.append(it)
        }
        for c in FS.children(abs("Library/Logs/Google")) where c.name.hasPrefix("AndroidStudio") {
            var it = item(c.path, "Android Studio logs", .android, .safe)
            it.project = c.name
            items.append(it)
        }
        for c in FS.children(abs("Library/Caches/JetBrains")) {
            var it = item(c.path, "JetBrains cache", .ide, .safe)
            it.project = c.name
            items.append(it)
        }
        return items
    }

    // MARK: Toolchain versions

    private func nodeVersions() -> [CleanItem] {
        var items: [CleanItem] = []
        let nvm = abs(".nvm/versions/node")
        let versions = FS.children(nvm)
        if !versions.isEmpty {
            let alias = FS.readSmall(abs(".nvm/alias/default"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let current = Self.resolveNodeAlias(alias, versions.map(\.name))
            for v in versions {
                var it = item(v.path, "Node \(v.name)", .node, .rebuildable)
                it.project = "nvm"
                it.activity = FS.date(v.mtime)
                it.useContentAge = false
                if v.name == current {
                    it.inUse = true
                    it.note = "nvm default"
                } else {
                    it.note = "installed · nvm install \(v.name.dropFirst()) restores it"
                }
                items.append(it)
            }
        }
        for (dir, manager) in [(".volta/tools/image/node", "volta"), ("Library/Application Support/fnm/node-versions", "fnm")] {
            for v in FS.children(abs(dir)) {
                var it = item(v.path, "Node \(v.name)", .node, .rebuildable)
                it.project = manager
                it.activity = FS.date(v.mtime)
                it.useContentAge = false
                items.append(it)
            }
        }
        return items
    }

    private func otherToolchains() -> [CleanItem] {
        var items: [CleanItem] = []
        func versions(_ dir: String, _ title: String, _ category: Category, current: String?) {
            for v in FS.children(abs(dir)) {
                var it = item(v.path, "\(title) \(v.name)", category, .rebuildable)
                it.activity = FS.date(v.mtime)
                it.useContentAge = false
                if let current, v.name == current || v.name.hasPrefix(current + "-") || current.hasPrefix(v.name) {
                    it.inUse = true
                    it.note = "default"
                } else {
                    it.note = "installed"
                }
                items.append(it)
            }
        }
        let firstLine = { (p: String) in FS.readSmall(abs(p))?.split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespaces) } }
        versions(".pyenv/versions", "Python", .python, current: firstLine(".pyenv/version"))
        versions(".rbenv/versions", "Ruby", .ruby, current: firstLine(".rbenv/version"))
        versions(".rvm/rubies", "Ruby", .ruby, current: nil)
        var rustDefault: String?
        if let settings = FS.readSmall(abs(".rustup/settings.toml")) {
            for line in settings.split(separator: "\n") where line.hasPrefix("default_toolchain") {
                rustDefault = line.split(separator: "=").last?.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            }
        }
        versions(".rustup/toolchains", "Rust", .rust, current: rustDefault)
        return items
    }

    private func aiToolVersions() -> [CleanItem] {
        var items: [CleanItem] = []
        // Claude Code native installs keep every version they downloaded.
        let current = FS.readLink(abs(".local/bin/claude"))?.lastPathComponent
        for v in FS.children(abs(".local/share/claude/versions"), dirsOnly: false) {
            var it = item(v.path, "Claude Code \(v.name)", .ai, .safe)
            it.agent = .claude
            it.activity = FS.date(v.mtime)
            it.useContentAge = false
            if v.name == current {
                it.inUse = true
                it.note = "active version"
            } else {
                it.note = "old version"
            }
            items.append(it)
        }
        // Claude desktop's bundled Claude Code builds: all but the newest are leftovers.
        let bundled = FS.children(abs("Library/Application Support/Claude/claude-code")).sorted { Self.versionLess($0.name, $1.name) }
        for v in bundled.dropLast() {
            var it = item(v.path, "Claude app's Claude Code \(v.name)", .ai, .safe)
            it.note = "old version · newest is \(bundled.last!.name)"
            it.activity = FS.date(v.mtime)
            it.useContentAge = false
            items.append(it)
        }
        for c in FS.children(abs(".cache/codex-runtimes")) where c.name.hasPrefix("codex-runtime-install-") {
            var it = item(c.path, "Leftover Codex runtime install", .ai, .safe)
            it.note = "abandoned download"
            items.append(it)
        }
        return items
    }

    // MARK: Homebrew

    private func homebrewOld() -> [CleanItem] {
        for prefix in ["/opt/homebrew", "/usr/local"] {
            guard FS.isDir(prefix + "/Cellar"), FS.exists(prefix + "/bin/brew") else { continue }
            var old: [String] = []
            for formula in FS.children(prefix + "/Cellar") {
                let kegs = FS.children(formula.path)
                guard kegs.count > 1 else { continue }
                let linked = FS.readLink(prefix + "/opt/" + formula.name)?.lastPathComponent
                for keg in kegs where keg.name != linked { old.append(keg.path) }
            }
            guard !old.isEmpty else { continue }
            var it = CleanItem(id: "brew-old:" + prefix, category: .homebrew, title: "Old Homebrew versions", safety: .safe,
                               action: .command([prefix + "/bin/brew", "cleanup", "--prune=all"]))
            it.paths = old
            it.project = "\(old.count) outdated keg\(old.count == 1 ? "" : "s")"
            it.displayPath = prefix + "/Cellar"
            it.ageMatters = false
            it.note = "runs brew cleanup"
            return [it]
        }
        return []
    }

    // MARK: Temp

    /// Claude Code session scratch folders: /private/tmp/claude-<uid>/<project>/<session>.
    private func claudeSessionTemp() -> [CleanItem] {
        var items: [CleanItem] = []
        for project in FS.children("/private/tmp/claude-\(getuid())") {
            let name = Self.decodeClaudeProject(project.name, home: home)
            for session in FS.children(project.path) {
                var it = item(session.path, "Claude session temp", .ai, .safe)
                it.project = name
                it.agent = .claude
                it.note = "scratchpad of a Claude Code session"
                items.append(it)
            }
        }
        return items
    }

    /// Bundler/test-runner caches under the per-user temp dir.
    private func tmpdirCaches() -> [CleanItem] {
        let tmp = (NSTemporaryDirectory() as NSString).standardizingPath
        let prefixes = ["metro-", "haste-map", "react-native-packager-cache", "jest_", "node-compile-cache", "turbo-"]
        var items: [CleanItem] = []
        for c in FS.children(tmp) where prefixes.contains(where: { c.name.hasPrefix($0) }) {
            var it = item(c.path, "Bundler temp cache", .temp, .safe)
            it.project = c.name
            items.append(it)
        }
        let cacheDir = tmp.deletingLastPathComponent + "/C"
        for (sub, title) in [("clang", "Clang module cache"), ("com.apple.DeveloperTools", "Xcode tools cache")] where FS.isDir(cacheDir + "/" + sub) {
            items.append(item(cacheDir + "/" + sub, title, .xcode, .safe))
        }
        return items
    }

    /// User-owned folders in /private/tmp that nothing else claimed.
    func tempFolders(claimed: Set<String>) -> [CleanItem] {
        let skip = ["com.apple.", "claude-", "launchd", "powerlog", "boost_interprocess"]
        var items: [CleanItem] = []
        for c in FS.children("/private/tmp") where !claimed.contains(c.path) && !skip.contains(where: { c.name.hasPrefix($0) }) {
            var st = stat()
            guard lstat(c.path, &st) == 0, st.st_uid == getuid() else { continue }
            var it = item(c.path, "Temp folder", .temp, .safe)
            it.project = c.name
            items.append(it)
        }
        return items
    }

    // MARK: Generic app caches

    static let cacheSkip: Set<String> = ["CloudKit", "GeoServices", "PassKit", "Metadata", "FamilyCircle", "SiriTTS",
                                         "familycircled", "storeassetd", "SpaceGuard", "io.github.mkrn.spaceguard"]

    /// Everything else in ~/Library/Caches and ~/.cache. Folders that contain an already-claimed item are
    /// split one level down so nothing is counted twice.
    func genericCaches(claimed: Set<String>) -> [CleanItem] {
        var items: [CleanItem] = []
        func consider(_ dir: String, depth: Int) {
            for c in FS.children(dir) {
                if claimed.contains(c.path) || c.name.hasPrefix("com.apple.") || Self.cacheSkip.contains(c.name) { continue }
                let prefix = c.path + "/"
                if claimed.contains(where: { $0.hasPrefix(prefix) }) {
                    if depth == 0 { consider(c.path, depth: 1) }
                    continue
                }
                var it = item(c.path, Self.cacheTitle(c.name), .appCache, .safe)
                if depth == 1 { it.project = dir.lastPathComponent }
                items.append(it)
            }
        }
        consider(abs("Library/Caches"), depth: 0)
        consider(abs(".cache"), depth: 0)
        return items
    }

    static func cacheTitle(_ name: String) -> String {
        if name.split(separator: ".").count >= 3,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) {
            let app = FileManager.default.displayName(atPath: url.path)
            return (app.hasSuffix(".app") ? String(app.dropLast(4)) : app) + " cache"
        }
        return name + " cache"
    }

    // MARK: Agent worktree folders outside repositories

    func globalAgentWorktreeDirs() -> [String] {
        var dirs: [String] = []
        for base in [".codex/worktrees", ".cursor/worktrees", "conductor/workspaces", ".claude/worktrees"] {
            for c in FS.children(abs(base)) {
                dirs += FS.children(c.path).map(\.path)
            }
        }
        return dirs
    }

    // MARK: Tool-reported items

    func simulators() -> [CleanItem] {
        guard FS.exists("/usr/bin/xcrun"), FS.isDir(abs("Library/Developer/CoreSimulator")) else { return [] }
        var items: [CleanItem] = []
        let iso = ISO8601DateFormatter()

        let rt = Shell.run("/usr/bin/xcrun", ["simctl", "runtime", "list", "-j"], timeout: 40)
        if rt.ok, let json = try? JSONSerialization.jsonObject(with: Data(rt.out.utf8)) as? [String: [String: Any]] {
            var newest: [String: (String, String)] = [:]   // platform → (version, identifier)
            for (id, r) in json {
                let platform = r["platformIdentifier"] as? String ?? ""
                let version = r["version"] as? String ?? "0"
                if let cur = newest[platform], !Self.versionLess(cur.0, version) { continue }
                newest[platform] = (version, id)
            }
            for (id, r) in json {
                guard r["deletable"] as? Bool ?? true else { continue }
                let platform = r["platformIdentifier"] as? String ?? ""
                let os = Self.osName(platform)
                let version = r["version"] as? String ?? "?"
                var it = CleanItem(id: "simruntime:" + id, category: .simulator, title: "\(os) \(version) simulator runtime",
                                   safety: .rebuildable, action: .command(["/usr/bin/xcrun", "simctl", "runtime", "delete", id]))
                it.project = r["build"] as? String
                it.bytes = (r["sizeBytes"] as? NSNumber)?.int64Value ?? 0
                it.sized = true
                it.displayPath = r["path"] as? String
                if let s = r["lastUsedAt"] as? String, let d = iso.date(from: s) {
                    it.lastUsed = d
                } else {
                    it.neverUsed = true
                }
                if newest[platform]?.1 == id {
                    it.inUse = true
                    it.note = "newest \(os) runtime"
                } else {
                    it.note = "re-download in Xcode › Settings › Components"
                }
                items.append(it)
            }
        }

        let dv = Shell.run("/usr/bin/xcrun", ["simctl", "list", "devices", "-j"], timeout: 40)
        if dv.ok, let json = try? JSONSerialization.jsonObject(with: Data(dv.out.utf8)) as? [String: Any],
           let byRuntime = json["devices"] as? [String: [[String: Any]]] {
            var known = Set<String>()
            for (runtime, devices) in byRuntime {
                let runtimeName = Self.runtimeName(runtime)
                for d in devices {
                    guard let udid = d["udid"] as? String else { continue }
                    known.insert(udid)
                    let name = d["name"] as? String ?? "Simulator"
                    let dataSize = (d["dataPathSize"] as? NSNumber)?.int64Value ?? 0
                    let logSize = (d["logPathSize"] as? NSNumber)?.int64Value ?? 0
                    var it: CleanItem
                    if d["isAvailable"] as? Bool ?? true {
                        guard dataSize >= 50_000_000 else { continue }
                        it = CleanItem(id: "simdevice:" + udid, category: .simulator, title: "\(name) simulator data",
                                       safety: .rebuildable, action: .command(["/usr/bin/xcrun", "simctl", "erase", udid]))
                        it.bytes = dataSize
                        it.note = "erase: removes installed apps & data, keeps the device"
                        if d["state"] as? String == "Booted" {
                            it.inUse = true
                            it.note = "running now"
                        }
                    } else {
                        it = CleanItem(id: "simdevice:" + udid, category: .simulator, title: "\(name) (unavailable)",
                                       safety: .safe, action: .command(["/usr/bin/xcrun", "simctl", "delete", udid]))
                        it.bytes = dataSize + logSize
                        it.note = "its runtime is no longer installed"
                    }
                    it.project = runtimeName
                    it.sized = true
                    it.displayPath = (d["dataPath"] as? String)?.deletingLastPathComponent
                    if let s = d["lastBootedAt"] as? String, let date = iso.date(from: s) {
                        it.lastUsed = date
                    } else {
                        it.neverUsed = true
                    }
                    items.append(it)
                }
            }
            for c in FS.children(abs("Library/Developer/CoreSimulator/Devices")) where c.name.count == 36 && !known.contains(c.name) {
                var it = item(c.path, "Orphaned simulator folder", .simulator, .safe)
                it.project = c.name
                it.note = "simctl doesn't know this device"
                items.append(it)
            }
        }
        return items
    }

    func docker() -> [CleanItem] {
        guard let docker = Shell.which("docker", extra: ["/Applications/Docker.app/Contents/Resources/bin", abs(".orbstack/bin"), abs(".docker/bin")]) else { return [] }
        let r = Shell.run(docker, ["system", "df", "--format", "{{json .}}"], timeout: 15)
        guard r.ok else { return [] }
        var total: Int64 = 0
        var parts: [String] = []
        for line in r.out.split(separator: "\n") {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = obj["Type"] as? String, type != "Local Volumes",
                  let reclaimable = (obj["Reclaimable"] as? String)?.split(separator: " ").first else { continue }
            let b = Self.parseDockerSize(String(reclaimable))
            if b > 0 {
                total += b
                parts.append("\(type.lowercased()) \(Fmt.bytes(b))")
            }
        }
        guard total > 0 else { return [] }
        var it = CleanItem(id: "docker", category: .docker, title: "Docker unused images & build cache", safety: .caution,
                           action: .command([docker, "system", "prune", "-af"]))
        it.bytes = total
        it.sized = true
        it.note = parts.joined(separator: " · ")
        it.displayPath = "docker system prune -af"
        return [it]
    }

    // MARK: Helpers

    static func plist(_ path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    /// Nearest enclosing repository or worktree of a path.
    static func gitContext(_ path: String) -> GitInfo? {
        var dir = path
        for _ in 0..<8 {
            dir = dir.deletingLastPathComponent
            if dir.count <= 1 { return nil }
            var st = stat()
            if lstat(dir + "/.git", &st) == 0 {
                return Git.info(root: dir, dotGitIsFile: (st.st_mode & S_IFMT) == S_IFREG)
            }
        }
        return nil
    }

    static func versionParts(_ s: String) -> [Int] {
        s.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }

    /// Numeric version compare; a pre-release ("36.0.0-rc4") sorts before its release.
    static func versionLess(_ a: String, _ b: String) -> Bool {
        let (am, ap) = splitPre(a), (bm, bp) = splitPre(b)
        let x = versionParts(am), y = versionParts(bm)
        if x != y { return x.lexicographicallyPrecedes(y) }
        if ap != bp { return ap }   // pre-release < release
        return a < b
    }

    private static func splitPre(_ s: String) -> (String, Bool) {
        guard let dash = s.firstIndex(of: "-") else { return (s, false) }
        let rest = s[s.index(after: dash)...].lowercased()
        let pre = rest.hasPrefix("rc") || rest.hasPrefix("beta") || rest.hasPrefix("alpha") || rest.hasPrefix("preview")
        return (pre ? String(s[..<dash]) : s, pre)
    }

    static func resolveNodeAlias(_ alias: String, _ versions: [String]) -> String? {
        let sorted = versions.sorted(by: versionLess)
        if alias.isEmpty || alias == "node" || alias == "stable" || alias.hasPrefix("lts") { return sorted.last }
        let want = alias.hasPrefix("v") ? alias : "v" + alias
        if versions.contains(want) { return want }
        return sorted.last(where: { $0.hasPrefix(want + ".") })
    }

    static func osName(_ platform: String) -> String {
        if platform.contains("iphone") { return "iOS" }
        if platform.contains("watch") { return "watchOS" }
        if platform.contains("appletv") { return "tvOS" }
        if platform.contains("xr") || platform.contains("vision") { return "visionOS" }
        return "Simulator"
    }

    static func runtimeName(_ id: String) -> String {
        // com.apple.CoreSimulator.SimRuntime.iOS-26-0 → iOS 26.0
        guard let last = id.split(separator: ".").last else { return id }
        let parts = last.split(separator: "-")
        guard let os = parts.first else { return id }
        return os + " " + parts.dropFirst().joined(separator: ".")
    }

    static func decodeClaudeProject(_ slug: String, home: String) -> String {
        var s = slug
        let homeSlug = home.replacingOccurrences(of: "/", with: "-") + "-"
        if s.hasPrefix(homeSlug) { s.removeFirst(homeSlug.count) }
        for container in ProjectDiscovery.containerNames where s.hasPrefix(container + "-") {
            s.removeFirst(container.count + 1)
            break
        }
        return s.isEmpty ? slug : s
    }

    static func parseDockerSize(_ s: String) -> Int64 {
        let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3), ("KB", 1e3), ("B", 1)]
        for (u, m) in units where s.hasSuffix(u) {
            return Int64((Double(s.dropLast(u.count)) ?? 0) * m)
        }
        return 0
    }
}
