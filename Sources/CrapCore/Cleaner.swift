import Foundation

public enum Cleaner {
    public struct Result: Sendable { public var freed: Int64; public var error: String? }

    public static func remove(_ removal: Removal, size: Int64) async -> Result {
        await Task.detached(priority: .userInitiated) {
            switch removal {
            case .delete, .trash, .trashAll:
                let urls = removal.urls
                guard urls.allSatisfy(isSafeTarget) else { return Result(freed: 0, error: "Refused: outside your home folder") }
                var failure: String?
                for url in urls {
                    do {
                        if removal.isTrash {
                            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                        } else {
                            try FileManager.default.removeItem(at: url)
                        }
                    } catch {
                        failure = "Some files were locked or protected, so part of it stayed."
                    }
                }
                let left = urls.reduce(Int64(0)) { $0 + (FS.exists($1) ? FS.size(of: $1) : 0) }
                return Result(freed: max(size - left, 0), error: failure)

            case .commands(let commands):
                for c in commands {
                    let r = await Shell.run(c.executable, c.arguments)
                    if r.status != 0 && !c.allowFailure {
                        let line = r.output.split(separator: "\n").last.map(String.init) ?? "exit \(r.status)"
                        return Result(freed: 0, error: line)
                    }
                }
                return Result(freed: size, error: nil)
            }
        }.value
    }

    /// Never touch anything outside the home folder, or the home folder's top level itself.
    private static func isSafeTarget(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let home = FS.home.standardizedFileURL.path
        guard path.hasPrefix(home + "/") else { return false }
        let depth = path.dropFirst(home.count).split(separator: "/").count
        return depth >= 2
    }
}
