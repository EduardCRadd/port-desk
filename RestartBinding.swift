import Foundation
import Network

/// A socket may be shared safely only when both addresses are concrete and distinct.
/// IPv4-mapped IPv6 and wildcard sockets can overlap across address families.
extension Endpoint {
    private var concreteAddress: Data? {
        guard !address.contains("%") else { return nil }
        switch family {
        case "IPv4":
            guard let bytes = IPv4Address(address)?.rawValue, bytes.contains(where: { $0 != 0 }) else { return nil }
            return bytes
        case "IPv6":
            guard let bytes = IPv6Address(address)?.rawValue, bytes.contains(where: { $0 != 0 }),
                  !bytes.starts(with: Array(repeating: UInt8(0), count: 10) + [255, 255]) else { return nil }
            return bytes
        default: return nil
        }
    }

    func couldConflict(with other: Endpoint) -> Bool {
        guard port == other.port else { return false }
        guard let lhs = concreteAddress, let rhs = other.concreteAddress else { return true }
        return lhs == rhs
    }

    func matchesExplicitHost(_ host: String) -> Bool {
        guard let expected = concreteAddress else { return false }
        let raw = family == "IPv6" ? IPv6Address(host)?.rawValue : IPv4Address(host)?.rawValue
        return raw == expected
    }
}

enum RestartBinding {
    // Recognize literal command forms whose bind and port options have defined semantics.
    // An arbitrary shell program (including an arbitrary Node script) has no such contract.
    static func matches(_ command: String, selected: Listener) -> Bool {
        guard selected.endpoints.count == 1, let endpoint = selected.endpoints.first,
              let words = literalWords(command), let executable = words.first else { return false }
        let runtime = URL(fileURLWithPath: executable).lastPathComponent.lowercased()
        if runtime.wholeMatch(of: /python(3(\.[0-9]+)?)?/) != nil {
            guard selected.name.lowercased().hasPrefix("python"),
                  words.dropFirst().starts(with: ["-m", "http.server"]) else { return false }
            if executable.contains("/") {
                guard executable.hasPrefix("/"), let observed = selected.executable,
                      isObservedPython(executable, observed: observed) else { return false }
            }
            return optionsMatch(words.dropFirst(3), endpoint: endpoint, python: true)
        }
        guard selected.name.hasPrefix("next-server") || selected.name == "node" else { return false }
        if words.starts(with: ["next", "dev"]) {
            return optionsMatch(words.dropFirst(2), endpoint: endpoint, python: false)
        }
        guard words.starts(with: ["npm", "run", "dev", "--"]), let directory = selected.directory,
              let data = try? Data(contentsOf: URL(fileURLWithPath: directory).appendingPathComponent("package.json")),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = manifest["scripts"] as? [String: String],
              scripts["predev"] == nil, scripts["postdev"] == nil,
              let dev = scripts["dev"].flatMap(literalWords), dev.starts(with: ["next", "dev"]),
              dev.dropFirst(2).allSatisfy({ nextModeFlags.contains($0) }) else { return false }
        return optionsMatch(words.dropFirst(4), endpoint: endpoint, python: false)
    }

    private static func isObservedPython(_ command: String, observed: String) -> Bool {
        let launcher = URL(fileURLWithPath: command).resolvingSymlinksInPath()
        let runtime = URL(fileURLWithPath: observed).resolvingSymlinksInPath()
        if launcher == runtime { return true }
        // Python.org's bin/python3 execs Python.app inside the same versioned framework.
        let bin = launcher.deletingLastPathComponent()
        let version = bin.deletingLastPathComponent()
        guard bin.lastPathComponent == "bin", version.deletingLastPathComponent().lastPathComponent == "Versions",
              version.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Python.framework" else { return false }
        return version.appendingPathComponent("Resources/Python.app/Contents/MacOS/Python").path == runtime.path
    }

    private static let nextModeFlags: Set<String> = ["--webpack", "--turbo", "--turbopack", "--experimental-https"]

    private static func optionsMatch(_ options: ArraySlice<String>, endpoint: Endpoint, python: Bool) -> Bool {
        var args = options
        var port: Int?
        var host: String?
        while let word = args.popFirst() {
            let pair = word.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(pair[0])
            let inlineValue = pair.count == 2 ? String(pair[1]) : nil
            if (python ? ["-b", "--bind"] : ["-H", "--hostname"]).contains(key) {
                guard host == nil, let value = inlineValue ?? args.popFirst() else { return false }
                host = value
            } else if !python && ["-p", "--port"].contains(key) {
                guard port == nil, let value = inlineValue ?? args.popFirst(), let number = Int(value) else { return false }
                port = number
            } else if python, port == nil, let number = Int(word) {
                port = number
            } else if python || !nextModeFlags.contains(word) { return false }
        }
        guard let host, (port ?? (python ? 8000 : -1)) == endpoint.port else { return false }
        return endpoint.matchesExplicitHost(host)
    }

    private static func literalWords(_ command: String) -> [String]? {
        // Include quoted literal paths containing spaces. Reject shell operators,
        // substitutions, expansions, control characters, and concatenated shell words.
        var input = command[...]
        var words: [String] = []
        while !input.isEmpty {
            if input.first == " " { input.removeFirst(); continue }
            let quote: Character? = input.first == "'" || input.first == "\"" ? input.removeFirst() : nil
            let word = input.prefix { character in
                character.isASCII && (character.isLetter || character.isNumber ||
                    "/._-:=@".contains(character) || (quote != nil && character == " "))
            }
            guard !word.isEmpty else { return nil }
            input = input.dropFirst(word.count)
            if let quote {
                guard input.popFirst() == quote else { return nil }
            }
            guard input.isEmpty || input.first == " " else { return nil }
            words.append(String(word))
        }
        return words
    }
}
