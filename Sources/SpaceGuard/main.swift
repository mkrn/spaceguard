import AppKit

let args = CommandLine.arguments

if args.contains("--scan") {
    CLI.scan(json: args.contains("--json"), incremental: args.contains("--incremental"))
    exit(0)
}
if let i = args.firstIndex(of: "--size") {
    CLI.size(Array(args.dropFirst(i + 1)))
    exit(0)
}
if let i = args.firstIndex(of: "--self-test"), i + 1 < args.count {
    exit(SelfTest.run(in: args[i + 1]))
}
if let i = args.firstIndex(of: "--make-icon"), i + 1 < args.count {
    MainActor.assumeIsolated { CLI.makeIcon(dir: args[i + 1]) }
    exit(0)
}
if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
    MainActor.assumeIsolated {
        CLI.snapshot(path: args[i + 1], dark: args.contains("--dark"), cached: args.contains("--cached"),
                     settings: args.contains("--settings"), demo: args.contains("--demo"))
    }
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
