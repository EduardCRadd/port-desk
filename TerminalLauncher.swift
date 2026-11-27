import Foundation

func terminalLaunch(directory: String, command: String) throws {
    guard FileManager.default.fileExists(atPath: directory) else { throw DeskError("The working folder no longer exists.") }
    let script = FileManager.default.temporaryDirectory.appendingPathComponent("Port Desk \(UUID().uuidString).command")
    let body = "#!/bin/zsh\n/bin/rm -f -- \"$0\"\nexec /bin/zsh -lic " + quote("cd -- " + quote(directory) + " && " + command) + "\n"
    try Data(body.utf8).write(to: script, options: .withoutOverwriting)
    do {
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-a", "Terminal", script.path]
        try open.run()
        open.waitUntilExit()
        guard open.terminationStatus == 0 else { throw DeskError("Terminal could not open the restart command.") }
    } catch {
        try? FileManager.default.removeItem(at: script)
        throw error
    }
}
