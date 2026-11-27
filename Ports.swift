import Darwin
import Foundation

#if compiler(<6.4.3)
#error("Install the Swift 6.4.3 release toolchain and relaunch Xcode if it was open during installation.")
#endif

struct DeskError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct Identity: Equatable {
    let uid: uid_t
    let seconds: UInt64
    let micros: UInt64
}

func processInfo(_ pid: Int32) -> proc_bsdinfo? {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout.size(ofValue: info))
    return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
}

func identity(_ info: proc_bsdinfo?) -> Identity? {
    info.map { Identity(uid: $0.pbi_uid, seconds: $0.pbi_start_tvsec, micros: $0.pbi_start_tvusec) }
}

func workingDirectory(_ pid: Int32) -> String? {
    var info = proc_vnodepathinfo()
    let size = Int32(MemoryLayout.size(ofValue: info))
    guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
    return withUnsafeBytes(of: &info.pvi_cdir.vip_path) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
}

// Read only argv. KERN_PROCARGS2 also contains the environment after the last argument.
func arguments(_ pid: Int32) -> [String] {
    var mib = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = 0
    guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return [] }
    var bytes = [UInt8](repeating: 0, count: size)
    guard sysctl(&mib, 3, &bytes, &size, nil, 0) == 0 else { return [] }
    let count = Int(bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
    guard count > 0, count < 4096, let end = bytes[4..<size].firstIndex(of: 0) else { return [] }
    var cursor = end
    while cursor < size && bytes[cursor] == 0 { cursor += 1 }
    var result = [String]()
    for _ in 0..<count {
        guard cursor < size, let end = bytes[cursor..<size].firstIndex(of: 0) else { return [] }
        result.append(String(decoding: bytes[cursor..<end], as: UTF8.self))
        cursor = end + 1
    }
    return result
}

func quote(_ s: String) -> String {
    if !s.isEmpty && s.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "/._-=:".contains($0)) }) { return s }
    return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

struct Endpoint: Hashable {
    let address: String
    let family: String
    let port: Int

    init?(_ name: String, family: String) {
        guard let colon = name.lastIndex(of: ":"),
              let port = Int(name[name.index(after: colon)...]), (1...65535).contains(port) else { return nil }
        self.port = port
        self.family = family
        address = String(name[..<colon]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    }

    var displayAddress: String {
        if address == "*" { return "*:\(port) (\(family))" }
        let host = address.contains(":") ? "[\(address)]" : address
        return "\(host):\(port)"
    }

    var browserHost: String {
        switch address {
        case "*": return family == "IPv6" ? "::1" : "127.0.0.1"
        case "::": return "::1"
        case "0.0.0.0": return "127.0.0.1"
        default: return address
        }
    }

    func url(https: Bool, sharedPort: Bool = false) -> URL? {
        let wildcard = address == "*" || address == "0.0.0.0" || address == "::"
        let host = wildcard && !sharedPort ? "localhost" : browserHost
        var parts = URLComponents()
        parts.scheme = https ? "https" : "http"
        parts.host = host.contains(":") ? "[" + host + "]" : host
        parts.port = port
        return parts.url
    }

    // Prefer a loopback binding, and make the choice stable across lsof scans.
    var preference: Int {
        if browserHost.hasPrefix("127.") { return 0 }
        if browserHost == "::1" { return 1 }
        return 2
    }
}

func hasHTTPSFlag(_ args: [String]) -> Bool {
    args.contains("--experimental-https") || args.contains("--https") || args.contains("--ssl")
        || (args.contains("http.server") && args.contains("--tls-cert"))
}

struct Listener: Identifiable {
    let id: Int32
    var name = ""
    var uid: uid_t?
    var endpoints = Set<Endpoint>()
    var ports: Set<Int> { Set(endpoints.map(\.port)) }
    var sharedPorts = Set<Int>()
    var usesHTTPS = false

    var previewEndpoints: [Endpoint] {
        var seen = Set<Int>()
        return endpoints.sorted {
            ($0.port, $0.preference, $0.browserHost) < ($1.port, $1.preference, $1.browserHost)
        }.filter { seen.insert($0.port).inserted }
    }

    var fingerprint: Identity?
    var directory: String?
    var executable: String?
    var project: String { directory.map { URL(fileURLWithPath: $0).lastPathComponent } ?? name }
    var sortedPorts: [Int] { ports.sorted() }
    var portText: String { sortedPorts.map(String.init).joined(separator: ", ") }
    var manageable: Bool {
        guard let fingerprint, uid == getuid(), fingerprint.uid == uid, id > 1,
              let directory, !directory.isEmpty, directory != "/",
              !directory.contains(".app/Contents/") else { return false }
        let runtime = name.lowercased()
        return ["node", "bun", "deno", "ruby", "php", "go", "java", "dotnet", "caddy", "uvicorn"]
            .contains(runtime) || runtime.hasPrefix("python") || runtime.hasPrefix("next-server")
            || executable?.hasPrefix(directory + "/") == true
    }
}

func parseListeners(_ data: Data) -> [Listener] {
    var rows = [Listener]()
    var row: Listener?
    var family = ""
    for field in data.split(separator: 0) {
        let field = field.drop(while: { $0 == 10 })
        guard let key = field.first else { continue }
        let value = String(decoding: field.dropFirst(), as: UTF8.self)
        switch key {
        case 112:
            if let row, !row.ports.isEmpty { rows.append(row) }
            row = Int32(value).map { Listener(id: $0) }
        case 99: row?.name = value
        case 117: row?.uid = uid_t(value)
        case 102: family = "" // f starts a new file descriptor.
        case 116: family = value
        case 110:
            if let endpoint = Endpoint(value, family: family) { row?.endpoints.insert(endpoint) }
        default: break
        }
    }
    if let row, !row.ports.isEmpty { rows.append(row) }
    // Separate IPv4 and IPv6 servers can own the same port. localhost might resolve to either.
    var seen = Set<Int>(), shared = Set<Int>()
    for row in rows {
        shared.formUnion(seen.intersection(row.ports))
        seen.formUnion(row.ports)
    }
    for index in rows.indices { rows[index].sharedPorts = rows[index].ports.intersection(shared) }
    return rows
}

func scan(previewSchemes: Bool = false) throws -> [Listener] {
    let data = try ListenerDiscovery().read()
    return try parseListeners(data).map { listener in
        try Task.checkCancellation()
        var row = listener
        let info = processInfo(row.id)
        row.fingerprint = identity(info)
        row.directory = workingDirectory(row.id)
        var path = [CChar](repeating: 0, count: 4096)
        if proc_pidpath(row.id, &path, UInt32(path.count)) > 0 {
            row.executable = String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        if previewSchemes, row.manageable, let info {
            let args = arguments(row.id)
            let parent = arguments(Int32(info.pbi_ppid))
            let nextDev = parent.count >= 3 && parent[1].hasSuffix("/next/dist/bin/next") && parent[2] == "dev"
            row.usesHTTPS = hasHTTPSFlag(args) || (nextDev && hasHTTPSFlag(parent))
        }
        return row
    }.sorted { ($0.sortedPorts[0], $0.id) < ($1.sortedPorts[0], $1.id) }
}

func restartSuggestion(_ row: Listener) -> String {
    guard let cwd = row.directory, let info = processInfo(row.id) else { return "" }
    let args = arguments(row.id)
    let parent = arguments(Int32(info.pbi_ppid))
    let port = String(row.sortedPorts[0])
    let manifest = URL(fileURLWithPath: cwd).appendingPathComponent("package.json")
    if parent.count >= 3, parent[1].hasSuffix("/next/dist/bin/next"), parent[2] == "dev",
       let data = try? Data(contentsOf: manifest),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let devScript = (json["scripts"] as? [String: String])?["dev"] {
        // Keep the listener’s actual port and its bind/transport flags when relaunching via the project script.
        var flags = ["--port", port]
        var options = Array(parent.dropFirst(3))[...]
        while let flag = options.popFirst() {
            switch flag {
            case "-p", "--port":
                guard options.popFirst() != nil else { return "" }
            case "-H", "--hostname":
                guard let host = options.popFirst() else { return "" }
                flags += [flag, host]
            case "--turbo", "--turbopack", "--webpack", "--experimental-https":
                if !devScript.split(whereSeparator: { $0.isWhitespace }).contains(Substring(flag)) { flags.append(flag) }
            default: return ""
            }
        }
        return "npm run dev -- " + flags.map(quote).joined(separator: " ")
    }
    // Only prefill recognizable launches with simple network flags. Other launches get an editable blank.
    guard args.count >= 2, let first = args.first else { return "" }
    let isPython = row.name.lowercased().hasPrefix("python") && Array(args.dropFirst().prefix(2)) == ["-m", "http.server"]
    let isNode = row.name == "node" && ["js", "mjs", "cjs"].contains(URL(fileURLWithPath: args[1]).pathExtension)
    guard isPython || isNode else { return "" }
    let extra = args.dropFirst(isPython ? 3 : 2)
    let known = ["--bind", "--port", "--host", "-p", "localhost", "127.0.0.1", "0.0.0.0", "::1", "::"]
    guard extra.allSatisfy({ known.contains($0) || UInt16($0) != nil }) else { return "" }
    var command = [first] + args.dropFirst()
    if isPython, command.count > 3, command[3] == "0" { command[3] = port }
    return command.map(quote).joined(separator: " ")
}
