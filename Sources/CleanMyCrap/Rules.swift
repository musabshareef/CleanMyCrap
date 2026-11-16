import Foundation

/// Every place we go sniffing. Order here is the order shown while scanning.
enum Rules {
    static let all: [Rule] = [
        // MARK: Safe — grows back, preselected
        Rule(id: "caches", name: "App Caches", icon: "archivebox.fill", risk: .safe,
             explanation: "Apps stash temporary files in ~/Library/Caches and rebuild them whenever they feel like it.") {
            let own = Bundle.main.bundleIdentifier ?? "com.cleanmycrap.app"
            return await FS.sizedChildren(of: FS.url("Library/Caches"), exclude: [own]) { .delete($0) }
        },
        Rule(id: "logs", name: "Log Files", icon: "doc.text.fill", risk: .safe,
             explanation: "Diaries your apps keep about their feelings. Nobody reads them. Not even the apps.") {
            async let library = FS.sizedChildren(of: FS.url("Library/Logs")) { .delete($0) }
            async let editors = FS.sizedPaths(Editors.all.map { ("Library/Application Support/\($0)/logs", "\($0) logs") }) { .delete($0) }
            return await library + editors
        },
        Rule(id: "editor-caches", name: "Code Editor Leftovers", icon: "chevron.left.forwardslash.chevron.right", risk: .safe,
             explanation: "VS Code and friends hoard cached data, extension downloads and GPU shaders. All of it regenerates.") {
            var paths: [(String, String)] = []
            for e in Editors.all {
                for sub in ["CachedData", "CachedExtensionVSIXs", "Cache", "Code Cache", "GPUCache", "CachedProfilesData", "Service Worker/CacheStorage"] {
                    paths.append(("Library/Application Support/\(e)/\(sub)", "\(e) › \(sub)"))
                }
            }
            return await FS.sizedPaths(paths) { .delete($0) }
        },
        Rule(id: "derived-data", name: "Xcode DerivedData", icon: "hammer.fill", risk: .safe,
             explanation: "Xcode's build leftovers. Rebuilt the next time you hit ⌘B.") {
            await FS.sizedChildren(of: FS.url("Library/Developer/Xcode/DerivedData")) { .delete($0) }
        },
        Rule(id: "xcode-misc", name: "Xcode & Simulator Caches", icon: "iphone.gen3", risk: .safe,
             explanation: "SwiftUI preview simulators and simulator caches. Xcode makes fresh ones on demand.") {
            await FS.sizedPaths([
                ("Library/Developer/Xcode/UserData/Previews", "SwiftUI Previews"),
                ("Library/Developer/CoreSimulator/Caches", "Simulator caches"),
                ("Library/Developer/Xcode/Products", "Xcode Products"),
            ]) { .delete($0) }
        },
        Rule(id: "docker-cache", name: "Docker Build Cache", icon: "shippingbox.fill", risk: .safe,
             explanation: "Layers Docker keeps around \"just in case\". The case never comes.",
             note: "Docker keeps everything in one big disk file. Restart Docker Desktop afterwards to actually get the space back.") {
            guard let d = await Docker.usage.value, d.buildCache > 0 else { return [] }
            return [Found(name: "Build cache", detail: "docker builder prune -af", size: d.buildCache,
                          removal: .commands([Command(executable: d.exe, arguments: ["builder", "prune", "-af"])]))]
        },

        // MARK: Low risk — comes back, but slower
        Rule(id: "project-junk", name: "Project Build Junk", icon: "folder.fill.badge.gearshape", risk: .low,
             explanation: "node_modules, build folders, .dart_tool, bin/obj and friends in your code folders. Run your build or install again to get them back.") {
            await Projects.junk()
        },
        Rule(id: "package-caches", name: "Package Manager Caches", icon: "cube.box.fill", risk: .low,
             explanation: "Downloaded packages for Gradle, NuGet, pub, npm, Cargo and Maven. They re-download on your next build, which will be slower.") {
            await FS.sizedPaths([
                (".gradle/caches", "Gradle caches"),
                (".gradle/wrapper/dists", "Gradle wrapper downloads"),
                (".nuget/packages", "NuGet packages"),
                (".pub-cache", "Flutter / Dart pub cache"),
                (".npm/_cacache", "npm cache"),
                (".cargo/registry", "Cargo registry"),
                (".m2/repository", "Maven repository"),
                (".cache/pip", "pip cache"),
                (".bun/install/cache", "Bun cache"),
                ("Library/pnpm/store", "pnpm store"),
            ]) { .delete($0) }
        },
        Rule(id: "device-support", name: "iOS Device Support", icon: "cable.connector", risk: .low,
             explanation: "Debug symbols Xcode copies from every iPhone you've ever plugged in. It copies them again (slowly) next time.") {
            async let ios = FS.sizedChildren(of: FS.url("Library/Developer/Xcode/iOS DeviceSupport")) { .delete($0) }
            async let watch = FS.sizedChildren(of: FS.url("Library/Developer/Xcode/watchOS DeviceSupport")) { .delete($0) }
            async let vision = FS.sizedChildren(of: FS.url("Library/Developer/Xcode/visionOS DeviceSupport")) { .delete($0) }
            return await ios + watch + vision
        },
        Rule(id: "simulators", name: "iOS Simulators", icon: "ipad.and.iphone", risk: .low,
             explanation: "Broken simulators for runtimes you no longer have, plus the apps and data inside working ones. Devices stay, contents go.") {
            await Simulators.scan()
        },
        Rule(id: "docker-images", name: "Docker Images & Containers", icon: "shippingbox", risk: .low,
             explanation: "Images and stopped containers nothing is using. Docker pulls them again when you need them.",
             note: "Restart Docker Desktop afterwards to actually get the space back.") {
            guard let d = await Docker.usage.value else { return [] }
            var out: [Found] = []
            if d.images > 0 {
                out.append(Found(name: "Unused images", detail: "docker image prune -af", size: d.images,
                                 removal: .commands([Command(executable: d.exe, arguments: ["image", "prune", "-af"])])))
            }
            if d.containers > 0 {
                out.append(Found(name: "Stopped containers", detail: "docker container prune -f", size: d.containers,
                                 removal: .commands([Command(executable: d.exe, arguments: ["container", "prune", "-f"])])))
            }
            return out
        },
        Rule(id: "installers", name: "Old Installers", icon: "arrow.down.app.fill", risk: .low,
             explanation: "Disk images and installers in Downloads. You installed the thing. The box can go.") {
            let exts: Set<String> = ["dmg", "pkg", "mpkg", "xip", "iso"]
            let files = FS.children(of: FS.url("Downloads")).filter { exts.contains($0.pathExtension.lowercased()) }
            return await FS.sized(files.map { ($0, $0.lastPathComponent, nil) }) { .delete($0) }
        },
        Rule(id: "trash", name: "Trash", icon: "trash.fill", risk: .low,
             explanation: "Stuff you already threw away but never took out. Emptying it is forever.") {
            await FS.sizedChildren(of: FS.url(".Trash"), includeHidden: true, minSize: 1, exclude: [".DS_Store"]) { .delete($0) }
        },

        // MARK: High risk — look before you flush
        Rule(id: "docker-volumes", name: "Docker Volumes", icon: "externaldrive.fill", risk: .high,
             explanation: "Volumes no container is using right now. Some of these might be holding a database you love.",
             note: "This runs docker volume prune. It can't be undone and nothing goes to the Trash.") {
            guard let d = await Docker.usage.value, d.volumes > 0 else { return [] }
            return [Found(name: "Unused volumes", detail: "docker volume prune -af", size: d.volumes,
                          removal: .commands([Command(executable: d.exe, arguments: ["volume", "prune", "-af"])]))]
        },
        Rule(id: "android", name: "Android Emulators", icon: "smartphone", risk: .high,
             explanation: "Android Virtual Devices and their saved state. You'll have to set them up again in Android Studio.") {
            let avds = FS.children(of: FS.url(".android/avd")).filter { $0.pathExtension == "avd" }
            return await FS.sized(avds.map { ($0, $0.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " "), nil) }) { .trash($0) }
        },
        Rule(id: "archives", name: "Xcode Archives", icon: "archivebox", risk: .high,
             explanation: "Builds you've archived for release. You need these to symbolicate crash reports for shipped versions.") {
            await FS.sizedChildren(of: FS.url("Library/Developer/Xcode/Archives")) { .trash($0) }
        },
        Rule(id: "ai-models", name: "AI Models", icon: "brain.fill", risk: .high,
             explanation: "Downloaded models from Hugging Face, Ollama and LM Studio. Big to download again if you still use them.") {
            async let hf = FS.sizedChildren(of: FS.url(".cache/huggingface/hub")) { .trash($0) }
            async let rest = FS.sizedPaths([
                (".ollama/models", "Ollama models"),
                (".lmstudio/models", "LM Studio models"),
                ("Library/Application Support/Diffusion Bee", "Diffusion Bee"),
            ]) { .trash($0) }
            return await hf + rest
        },
        Rule(id: "codex", name: "AI Chat History", icon: "bubble.left.and.text.bubble.right.fill", risk: .high,
             explanation: "Old Codex session logs. Gone means gone. You can't resume those chats.") {
            await FS.sizedPaths([
                (".codex/sessions", "Codex sessions"),
                (".codex/archived_sessions", "Codex archived sessions"),
                (".codex/log", "Codex logs"),
            ]) { .trash($0) }
        },
        Rule(id: "backups", name: "iPhone & iPad Backups", icon: "externaldrive.badge.timemachine", risk: .high,
             explanation: "Local device backups made by Finder. Might be the only copy of something.") {
            await FS.sizedChildren(of: FS.url("Library/Application Support/MobileSync/Backup")) { .trash($0) }
        },
    ]
}

enum Editors {
    static let all = ["Code", "Code - Insiders", "Cursor", "Windsurf", "VSCodium"]
}

// MARK: - Projects

enum Projects {
    static let roots = ["Projects", "Developer", "Code", "code", "src", "dev", "Documents/GitHub",
                        "GitHub", "repos", "workspace", "Sites"]

    static func junk() async -> [Found] {
        var seen = Set<String>()
        var hits: [(url: URL, name: String, detail: String?)] = []
        for r in roots {
            let u = FS.url(r).resolvingSymlinksInPath()
            guard FS.isDir(u), seen.insert(u.path).inserted else { continue }
            walk(u, depth: 0, into: &hits)
        }
        return await FS.sized(hits) { .delete($0) }
    }

    private static let skip: Set<String> = ["Library", "Applications", "Pictures", "Music", "Movies"]

    private static func walk(_ dir: URL, depth: Int, into hits: inout [(url: URL, name: String, detail: String?)]) {
        guard depth <= 7,
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        let siblings = Set(names)
        for name in names {
            let child = dir.appending(path: name)
            guard FS.isRealDir(child) else { continue }
            if let kind = kind(of: name, siblings: siblings) {
                hits.append((child, "\(dir.lastPathComponent) › \(name)", "\(kind) · \(FS.pretty(child))"))
                continue
            }
            if name.hasPrefix(".") || skip.contains(name) || name.hasSuffix(".app") { continue }
            walk(child, depth: depth + 1, into: &hits)
        }
    }

    private static func kind(of name: String, siblings s: Set<String>) -> String? {
        let gradle = ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"].contains(where: s.contains)
        let dotnet = s.contains { $0.hasSuffix(".csproj") || $0.hasSuffix(".fsproj") || $0.hasSuffix(".vbproj") }
        switch name {
        case "node_modules": return "Node packages"
        case ".dart_tool" where s.contains("pubspec.yaml"): return "Dart tooling"
        case "build" where s.contains("pubspec.yaml"): return "Flutter build"
        case "build" where gradle: return "Gradle build"
        case "bin" where dotnet, "obj" where dotnet: return ".NET build output"
        case ".gradle" where gradle: return "Gradle project cache"
        case ".next" where s.contains("package.json"): return "Next.js build"
        case ".nuxt" where s.contains("package.json"): return "Nuxt build"
        case ".svelte-kit" where s.contains("package.json"): return "SvelteKit build"
        case "target" where s.contains("Cargo.toml"): return "Rust build"
        case ".build" where s.contains("Package.swift"): return "SwiftPM build"
        case "Pods" where s.contains("Podfile"): return "CocoaPods"
        default: return nil
        }
    }
}

// MARK: - Docker

struct DockerUsage: Sendable {
    var exe: String
    var buildCache: Int64 = 0
    var images: Int64 = 0
    var containers: Int64 = 0
    var volumes: Int64 = 0
}

enum Docker {
    /// One probe shared by every Docker rule in a scan.
    nonisolated(unsafe) static var usage = Task { await probe() }

    static func reset() { usage = Task { await probe() } }

    static let candidates = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker",
                             "/Applications/Docker.app/Contents/Resources/bin/docker",
                             FS.url(".docker/bin/docker").path, FS.url(".orbstack/bin/docker").path]

    static func probe() async -> DockerUsage? {
        guard let exe = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else { return nil }
        let r = await Shell.run(exe, ["system", "df", "--format", "{{json .}}"], timeout: 20)
        guard r.status == 0 else { return nil }
        var u = DockerUsage(exe: exe)
        for line in r.output.split(separator: "\n") {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = obj["Type"] as? String,
                  let reclaim = obj["Reclaimable"] as? String else { continue }
            let bytes = parseSize(reclaim)
            switch type {
            case "Images": u.images = bytes
            case "Containers": u.containers = bytes
            case "Local Volumes": u.volumes = bytes
            case "Build Cache": u.buildCache = bytes
            default: break
            }
        }
        return u
    }

    /// "20.1GB (100%)" → bytes. Docker uses decimal units.
    static func parseSize(_ s: String) -> Int64 {
        let token = s.split(separator: " ").first.map(String.init) ?? s
        let number = token.prefix { $0.isNumber || $0 == "." }
        let unit = token.dropFirst(number.count).uppercased()
        guard let v = Double(number) else { return 0 }
        let mult: Double = switch unit {
        case "KB": 1e3
        case "MB": 1e6
        case "GB": 1e9
        case "TB": 1e12
        default: 1
        }
        return Int64(v * mult)
    }
}

// MARK: - Simulators

enum Simulators {
    static func scan() async -> [Found] {
        let devicesDir = FS.url("Library/Developer/CoreSimulator/Devices")
        guard FS.isDir(devicesDir) else { return [] }
        let r = await Shell.run("/usr/bin/xcrun", ["simctl", "list", "devices", "-j"], timeout: 60)
        guard r.status == 0,
              let json = try? JSONSerialization.jsonObject(with: Data(r.output.utf8)) as? [String: Any],
              let runtimes = json["devices"] as? [String: [[String: Any]]] else { return [] }

        var broken: [URL] = [], working: [URL] = []
        for devices in runtimes.values {
            for d in devices {
                guard let udid = d["udid"] as? String else { continue }
                let dir = devicesDir.appending(path: udid)
                if (d["isAvailable"] as? Bool) == false { broken.append(dir) }
                else { working.append(dir.appending(path: "data")) }
            }
        }

        let xcrun = "/usr/bin/xcrun"
        let (brokenDirs, workingDirs) = (broken, working)
        async let brokenSize = total(brokenDirs)
        async let workingSize = total(workingDirs)
        var out: [Found] = []
        if case let s = await brokenSize, s > FS.oneMB {
            out.append(Found(name: "Unavailable simulators (\(broken.count))",
                             detail: "Devices for runtimes that aren't installed anymore",
                             size: s, removal: .commands([Command(executable: xcrun, arguments: ["simctl", "delete", "unavailable"])])))
        }
        if case let s = await workingSize, s > FS.oneMB {
            out.append(Found(name: "Apps & data on \(working.count) simulators",
                             detail: "Erases every simulator. Devices stay, installed apps go.",
                             size: s, removal: .commands([
                                Command(executable: xcrun, arguments: ["simctl", "shutdown", "all"], allowFailure: true),
                                Command(executable: xcrun, arguments: ["simctl", "erase", "all"]),
                             ])))
        }
        return out
    }

    private static func total(_ urls: [URL]) async -> Int64 {
        await withTaskGroup(of: Int64.self) { g in
            for u in urls { g.addTask { FS.size(of: u) } }
            return await g.reduce(0, +)
        }
    }
}
