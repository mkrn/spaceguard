import Darwin
import Foundation

// Attribute bits from <sys/attr.h>. Spelled out because the imported macros have mixed integer types.
private let kCmnName: UInt32 = 0x0000_0001
private let kCmnObjType: UInt32 = 0x0000_0008
private let kCmnModTime: UInt32 = 0x0000_0400
private let kCmnFileID: UInt32 = 0x0200_0000
private let kCmnError: UInt32 = 0x2000_0000
private let kCmnReturnedAttrs: UInt32 = 0x8000_0000
private let kFileLinkCount: UInt32 = 0x0000_0001
private let kFileAllocSize: UInt32 = 0x0000_0004

struct DirEntry {
    var name: UnsafePointer<CChar>
    var type: UInt32      // vtype: 1 = regular file, 2 = directory, 5 = symlink
    var mtime: Int
    var fileID: UInt64
    var links: UInt32
    var alloc: Int64      // bytes allocated on disk, all forks

    var isDir: Bool { type == 2 }
    var isFile: Bool { type == 1 }
    var nameString: String { String(cString: name) }
}

/// Reads whole directories with getattrlistbulk(2): one syscall returns names, types, mtimes and
/// allocated sizes for hundreds of entries, instead of a readdir + lstat per file.
final class DirReader {
    private let size: Int
    private let buffer: UnsafeMutableRawPointer
    private var request = attrlist()

    init(sizes: Bool, bufferSize: Int = 256 * 1024) {
        size = bufferSize
        buffer = .allocate(byteCount: bufferSize, alignment: 16)
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = kCmnReturnedAttrs | kCmnName | kCmnError | kCmnObjType | kCmnModTime | (sizes ? kCmnFileID : 0)
        request.fileattr = sizes ? (kFileLinkCount | kFileAllocSize) : 0
    }

    deinit { buffer.deallocate() }

    /// Calls `body` for every entry of an open directory. Returns false if reading failed.
    @discardableResult
    func forEach(fd: Int32, _ body: (DirEntry) -> Void) -> Bool {
        while true {
            let count = getattrlistbulk(fd, &request, buffer, size, 0)
            if count < 0 {
                if errno == EINTR { continue }
                return false
            }
            if count == 0 { return true }
            var entry = UnsafeRawPointer(buffer)
            for _ in 0..<count {
                let length = Int(entry.loadUnaligned(as: UInt32.self))
                // attribute_set_t: commonattr, volattr, dirattr, fileattr, forkattr
                let common = entry.loadUnaligned(fromByteOffset: 4, as: UInt32.self)
                let file = entry.loadUnaligned(fromByteOffset: 16, as: UInt32.self)
                var field = entry + 24
                var error: UInt32 = 0
                var name: UnsafePointer<CChar>?
                var type: UInt32 = 0, mtime = 0, fileID: UInt64 = 0, links: UInt32 = 1, alloc: Int64 = 0
                if common & kCmnError != 0 {
                    error = field.loadUnaligned(as: UInt32.self)
                    field += 4
                }
                if common & kCmnName != 0 {
                    let offset = Int(field.loadUnaligned(as: Int32.self))
                    name = (field + offset).assumingMemoryBound(to: CChar.self)
                    field += 8
                }
                if common & kCmnObjType != 0 {
                    type = field.loadUnaligned(as: UInt32.self)
                    field += 4
                }
                if common & kCmnModTime != 0 {
                    mtime = field.loadUnaligned(as: Int.self)
                    field += 16
                }
                if common & kCmnFileID != 0 {
                    fileID = field.loadUnaligned(as: UInt64.self)
                    field += 8
                }
                if file & kFileLinkCount != 0 {
                    links = field.loadUnaligned(as: UInt32.self)
                    field += 4
                }
                if file & kFileAllocSize != 0 {
                    alloc = field.loadUnaligned(as: Int64.self)
                    field += 8
                }
                if error == 0, let name {
                    body(DirEntry(name: name, type: type, mtime: mtime, fileID: fileID, links: links, alloc: alloc))
                }
                entry += length
            }
        }
    }

    @discardableResult
    func list(_ path: String, _ body: (DirEntry) -> Void) -> Bool {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        return forEach(fd: fd, body)
    }
}

/// A LIFO work pool: jobs can emit child jobs; `run` returns once everything is drained.
final class ParallelQueue<Job>: @unchecked Sendable {
    private let cond = NSCondition()
    private var stack: [Job] = []
    private var active = 0

    func run(_ initial: [Job], threads: Int, qos: QualityOfService, sizes: Bool,
             process: @escaping (Job, DirReader, inout [Job]) -> Void) {
        guard !initial.isEmpty else { return }
        stack = initial
        let group = DispatchGroup()
        for _ in 0..<max(1, threads) {
            group.enter()
            let thread = Thread { [self] in
                let reader = DirReader(sizes: sizes)
                var children: [Job] = []
                while let job = next() {
                    children.removeAll(keepingCapacity: true)
                    process(job, reader, &children)
                    finish(children)
                }
                group.leave()
            }
            thread.qualityOfService = qos
            thread.stackSize = 1 << 20
            thread.start()
        }
        group.wait()
    }

    private func next() -> Job? {
        cond.lock()
        defer { cond.unlock() }
        while stack.isEmpty {
            if active == 0 {
                cond.broadcast()
                return nil
            }
            cond.wait()
        }
        active += 1
        return stack.removeLast()
    }

    private func finish(_ children: [Job]) {
        cond.lock()
        stack.append(contentsOf: children)
        active -= 1
        if !children.isEmpty || active == 0 { cond.broadcast() }
        cond.unlock()
    }
}

struct SizeResult: Sendable {
    /// Bytes freed if the tree is deleted: hard-linked files count only when every link lives inside it.
    var bytes: Int64 = 0
    /// Allocated bytes, each inode once.
    var total: Int64 = 0
    var files: Int = 0
    /// Newest mtime in the tree (unix seconds).
    var newest: Int = 0

    mutating func add(_ o: SizeResult) {
        bytes += o.bytes
        total += o.total
        files += o.files
        newest = max(newest, o.newest)
    }
}

/// Measures many trees at once on a shared thread pool. Roots nested inside other roots are walked
/// only once; their totals are folded into the enclosing roots at the end.
final class Sizer: @unchecked Sendable {
    private struct Job {
        let path: String
        let root: Int32
    }

    private struct Link {
        var need: UInt32
        var seen: UInt32
        let size: Int64
    }

    let roots: [String]
    private let rootIndex: [String: Int]
    private let reuse: [Int: SizeResult]
    private let lock = NSLock()
    private var results: [SizeResult]
    private var pending: [Int]
    private var devs: [dev_t]
    private var links: [[UInt64: Link]]
    /// Each root's own result (nested roots excluded), before folding. Valid after `run`.
    private(set) var raw: [SizeResult] = []
    /// mtime of each root folder when the walk started (0 if it wasn't a folder).
    private(set) var rootMtimes: [Int]
    private(set) var progressFiles = 0
    private(set) var progressBytes: Int64 = 0
    var cancelled = false

    /// `reuse`: results known from a previous scan; those roots are not walked.
    init(roots: [String], reuse: [Int: SizeResult] = [:]) {
        self.roots = roots
        self.reuse = reuse
        rootMtimes = Array(repeating: 0, count: roots.count)
        var index: [String: Int] = [:]
        for (i, r) in roots.enumerated() where index[r] == nil { index[r] = i }
        rootIndex = index
        results = Array(repeating: SizeResult(), count: roots.count)
        pending = Array(repeating: 0, count: roots.count)
        devs = Array(repeating: 0, count: roots.count)
        links = Array(repeating: [:], count: roots.count)
    }

    /// Blocks until done. `onRoot` fires (on a worker thread) when a root's own walk completes, before
    /// nested roots are folded in. The returned array has the final, nested-inclusive results.
    func run(threads: Int, qos: QualityOfService, onRoot: ((Int, SizeResult) -> Void)? = nil) -> [SizeResult] {
        var initial: [Job] = []
        for (i, path) in roots.enumerated() {
            var st = stat()
            guard rootIndex[path] == i, lstat(path, &st) == 0 else {
                onRoot?(i, SizeResult())
                continue
            }
            switch st.st_mode & S_IFMT {
            case S_IFDIR:
                rootMtimes[i] = st.st_mtimespec.tv_sec
                if let known = reuse[i] {
                    results[i] = known
                    onRoot?(i, known)
                    continue
                }
                devs[i] = st.st_dev
                pending[i] = 1
                initial.append(Job(path: path, root: Int32(i)))
            case S_IFREG:
                let b = Int64(st.st_blocks) * 512
                results[i] = SizeResult(bytes: st.st_nlink > 1 ? 0 : b, total: b, files: 1, newest: st.st_mtimespec.tv_sec)
                onRoot?(i, results[i])
            default:
                onRoot?(i, SizeResult())
            }
        }
        let queue = ParallelQueue<Job>()
        queue.run(initial, threads: threads, qos: qos, sizes: true) { job, reader, children in
            self.process(job, reader, &children, onRoot)
        }
        return foldNested()
    }

    private func process(_ job: Job, _ reader: DirReader, _ children: inout [Job], _ onRoot: ((Int, SizeResult) -> Void)?) {
        let r = Int(job.root)
        var local = SizeResult()
        var hard: [(UInt64, UInt32, Int64)] = []
        if !cancelled {
            let fd = open(job.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if fd >= 0 {
                var st = stat()
                if fstat(fd, &st) == 0, st.st_dev == devs[r] {
                    let own = Int64(st.st_blocks) * 512
                    local.bytes = own
                    local.total = own
                    local.newest = st.st_mtimespec.tv_sec
                    let base = job.path
                    reader.forEach(fd: fd) { e in
                        if e.isDir {
                            let child = base + "/" + e.nameString
                            if rootIndex[child] == nil {   // nested roots are measured on their own
                                children.append(Job(path: child, root: job.root))
                            }
                        } else {
                            local.files += 1
                            if e.mtime > local.newest { local.newest = e.mtime }
                            if e.links > 1 {
                                hard.append((e.fileID, e.links, e.alloc))
                            } else {
                                local.bytes += e.alloc
                                local.total += e.alloc
                            }
                        }
                    }
                }
                close(fd)
            }
        }

        lock.lock()
        var res = results[r]
        res.add(local)
        for (id, need, size) in hard {
            if var l = links[r][id] {
                l.seen += 1
                links[r][id] = l
            } else {
                links[r][id] = Link(need: need, seen: 1, size: size)
                res.total += size
            }
        }
        pending[r] += children.count - 1
        let done = pending[r] == 0
        if done {
            for l in links[r].values where l.seen >= l.need { res.bytes += l.size }
            links[r] = [:]
        }
        results[r] = res
        progressFiles += local.files
        progressBytes += local.total
        lock.unlock()
        if done { onRoot?(r, res) }
    }

    private func foldNested() -> [SizeResult] {
        raw = results
        var out = results
        let parents = Sizer.nestingParents(roots)
        let order = roots.indices.sorted { Sizer.pathLess(roots[$0], roots[$1]) }
        for i in order.reversed() {
            guard rootIndex[roots[i]] == i, let p = parents[i] else { continue }
            out[p].add(out[i])
        }
        return out
    }

    /// Orders paths so that every directory sorts directly before its descendants.
    static func pathLess(_ a: String, _ b: String) -> Bool {
        var ai = a.utf8.makeIterator(), bi = b.utf8.makeIterator()
        while true {
            switch (ai.next(), bi.next()) {
            case (nil, nil): return false
            case (nil, _): return true
            case (_, nil): return false
            case let (x?, y?):
                if x == y { continue }
                if x == UInt8(ascii: "/") { return true }
                if y == UInt8(ascii: "/") { return false }
                return x < y
            }
        }
    }

    /// For each path, the index of the nearest other path that contains it.
    static func nestingParents(_ paths: [String]) -> [Int?] {
        let order = paths.indices.sorted { pathLess(paths[$0], paths[$1]) }
        var parents = [Int?](repeating: nil, count: paths.count)
        var stack: [Int] = []
        for i in order {
            let p = paths[i]
            while let top = stack.last, !(p.hasPrefix(paths[top] + "/")) { stack.removeLast() }
            parents[i] = stack.last
            stack.append(i)
        }
        return parents
    }
}

// MARK: - Small filesystem helpers

enum FS {
    static func isDir(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
    }

    static func exists(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0
    }

    static func mtime(_ path: String) -> Int {
        var st = stat()
        return lstat(path, &st) == 0 ? st.st_mtimespec.tv_sec : 0
    }

    static func date(_ unix: Int) -> Date? {
        unix > 0 ? Date(timeIntervalSince1970: TimeInterval(unix)) : nil
    }

    static func readSmall(_ path: String, limit: Int = 8192) -> String? {
        let fd = open(path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var buf = [UInt8](repeating: 0, count: limit)
        let n = read(fd, &buf, limit)
        guard n > 0 else { return nil }
        return String(decoding: buf[0..<n], as: UTF8.self)
    }

    static func readLink(_ path: String) -> String? {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        let n = readlink(path, &buf, buf.count - 1)
        guard n > 0 else { return nil }
        return String(decoding: buf[0..<n].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    struct Child {
        let name: String
        let path: String
        let isDir: Bool
        let mtime: Int
    }

    /// Immediate children, skipping ".DS_Store"-style noise.
    static func children(_ path: String, dirsOnly: Bool = true) -> [Child] {
        let reader = DirReader(sizes: false, bufferSize: 32 * 1024)
        var out: [Child] = []
        reader.list(path) { e in
            guard !dirsOnly || e.isDir else { return }
            let name = e.nameString
            if name == ".DS_Store" { return }
            out.append(Child(name: name, path: path + "/" + name, isDir: e.isDir, mtime: e.mtime))
        }
        return out.sorted { $0.name < $1.name }
    }
}

/// Runs a tool with a timeout and captures its output.
enum Shell {
    struct Result {
        let code: Int32
        let out: String
        let err: String
        var ok: Bool { code == 0 }
    }

    static let searchPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    static func which(_ tool: String, extra: [String] = []) -> String? {
        for dir in extra + searchPath.split(separator: ":").map(String.init) {
            let p = dir + "/" + tool
            if access(p, X_OK) == 0 { return p }
        }
        return nil
    }

    @discardableResult
    static func run(_ exe: String, _ args: [String], cwd: String? = nil, timeout: TimeInterval = 60) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPath + ":" + (env["PATH"] ?? "")
        env["GIT_OPTIONAL_LOCKS"] = "0"
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        p.environment = env
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        p.standardInput = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in exited.signal() }
        do { try p.run() } catch { return Result(code: -1, out: "", err: "\(error)") }

        var outData = Data(), errData = Data()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            readers.leave()
        }
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            _ = exited.wait(timeout: .now() + 3)
        }
        _ = readers.wait(timeout: .now() + 5)
        let code = p.isRunning ? -2 : p.terminationStatus
        return Result(code: code, out: String(decoding: outData, as: UTF8.self), err: String(decoding: errData, as: UTF8.self))
    }
}
