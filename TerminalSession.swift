import Darwin
import Foundation

/// A controlling terminal plus Terminal.app in the ancestry identifies an Apple Terminal session.
func terminalTTY(for row: Listener) -> String? {
    guard let expected = row.fingerprint, let info = processInfo(row.id), identity(info) == expected,
          info.e_tdev != UInt32.max, info.e_tdev != 0 else { return nil }
    var name = [CChar](repeating: 0, count: 128)
    guard devname_r(dev_t(bitPattern: info.e_tdev), mode_t(S_IFCHR), &name, Int32(name.count)) != nil else { return nil }
    let device = "/dev/" + String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    var parent = Int32(info.pbi_ppid)
    var visited = Set<Int32>()
    while parent > 1 && visited.insert(parent).inserted && visited.count <= 64 {
        var path = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(parent, &path, UInt32(path.count)) > 0 else { break }
        let executable = String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        if executable == "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal" {
            return device
        }
        guard let ancestor = processInfo(parent) else { break }
        parent = Int32(ancestor.pbi_ppid)
    }
    return nil
}

@concurrent func revealTerminal(_ row: Listener) async throws {
    guard let device = row.terminal, terminalTTY(for: row) == device else {
        throw DeskError("The Terminal session changed. Refresh and select it again.")
    }
    let script = """
        on run argv
            set targetTTY to item 1 of argv
            if application id "com.apple.Terminal" is not running then error "Terminal is closed."
            with timeout of 5 seconds
                tell application id "com.apple.Terminal"
                    repeat with w in windows
                        repeat with t in tabs of w
                            if tty of t is targetTTY then
                                set selected of t to true
                                set index of w to 1
                                activate
                                return
                            end if
                        end repeat
                    end repeat
                end tell
            end timeout
            error "The original Terminal tab is no longer open."
        end run
        """
    let command = Process()
    let errors = Pipe()
    command.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    command.arguments = ["-e", script, device]
    command.standardOutput = FileHandle.nullDevice
    command.standardError = errors
    try command.run()
    let data = errors.fileHandleForReading.readDataToEndOfFile()
    command.waitUntilExit()
    guard command.terminationStatus == 0 else {
        let detail = String(decoding: data, as: UTF8.self)
        if detail.contains("-1743") { throw DeskError("Terminal access was denied. Review Automation in Privacy & Security.") }
        throw DeskError(detail.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
