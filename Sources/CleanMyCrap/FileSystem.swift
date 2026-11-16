import Foundation

/// Blocking file-system helpers. Call them from background tasks, never the main actor.
enum FS {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let oneMB: Int64 = 1 << 20

    static func url(_ relative: String) -> URL { home.appending(path: relative) }

    static func isDir(_ url: URL) -> Bool {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &d) && d.boolValue
    }

    static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    /// A real directory, not a symlink pointing at one.
    static func isRealDir(_ url: URL) -> Bool {
        let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return v?.isDirectory == true && v?.isSymbolicLink != true
    }

    static func children(of dir: URL, includeHidden: Bool = false) -> [URL] {
        let opts: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        return (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil,
                                                             options: opts)) ?? []
    }

    static func canList(_ dir: URL) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) != nil
    }

    /// Bytes actually used on disk.
    static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
                                         .isRegularFileKey, .isSymbolicLinkKey]
        guard let top = try? url.resourceValues(forKeys: keys.union([.isDirectoryKey])) else { return 0 }
        if top.isSymbolicLink == true { return 0 }
        if top.isDirectory != true {
            return Int64(top.totalFileAllocatedSize ?? top.fileAllocatedSize ?? 0)
        }
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys),
                                                     options: [], errorHandler: { _, _ in true })
        else { return 0 }
        var total: Int64 = 0
        while let f = e.nextObject() as? URL {
            guard let v = try? f.resourceValues(forKeys: keys), v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// "~/Library/Caches/foo" style path for display.
    static func pretty(_ url: URL) -> String {
        let p = url.path
        return p.hasPrefix(home.path) ? "~" + p.dropFirst(home.path.count) : p
    }

    /// Sizes many URLs concurrently and returns the ones above `minSize`.
    static func sized(_ entries: [(url: URL, name: String, detail: String?)],
                      minSize: Int64 = oneMB,
                      removal: @escaping @Sendable (URL) -> Removal) async -> [Found] {
        await withTaskGroup(of: Found?.self) { group in
            for entry in entries {
                group.addTask {
                    let s = FS.size(of: entry.url)
                    guard s >= minSize else { return nil }
                    return Found(name: entry.name, detail: entry.detail ?? FS.pretty(entry.url),
                                 size: s, removal: removal(entry.url))
                }
            }
            var out: [Found] = []
            for await f in group { if let f { out.append(f) } }
            return out
        }
    }

    /// Each child of `dir` becomes its own item.
    static func sizedChildren(of dir: URL, includeHidden: Bool = false, minSize: Int64 = oneMB,
                              exclude: Set<String> = [],
                              removal: @escaping @Sendable (URL) -> Removal) async -> [Found] {
        let kids = children(of: dir, includeHidden: includeHidden)
            .filter { !exclude.contains($0.lastPathComponent) }
        return await sized(kids.map { ($0, $0.lastPathComponent, nil) }, minSize: minSize, removal: removal)
    }

    /// The listed paths that exist, each as one item.
    static func sizedPaths(_ paths: [(String, String)], minSize: Int64 = oneMB,
                           removal: @escaping @Sendable (URL) -> Removal) async -> [Found] {
        let entries = paths.map { (url($0.0), $0.1) }.filter { exists($0.0) }
        return await sized(entries.map { ($0.0, $0.1, nil) }, minSize: minSize, removal: removal)
    }
}

enum Shell {
    struct Result: Sendable { var status: Int32; var output: String }

    static func run(_ exe: String, _ args: [String], timeout: TimeInterval = 300) async -> Result {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: exe)
                p.arguments = args
                var env = ProcessInfo.processInfo.environment
                let extra = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Docker.app/Contents/Resources/bin"
                env["PATH"] = extra + (env["PATH"].map { ":" + $0 } ?? "")
                p.environment = env
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                p.standardInput = FileHandle.nullDevice
                do { try p.run() } catch {
                    cont.resume(returning: Result(status: -1, output: error.localizedDescription))
                    return
                }
                let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                killer.cancel()
                cont.resume(returning: Result(status: p.terminationStatus,
                                              output: String(decoding: data, as: UTF8.self)))
            }
        }
    }
}
