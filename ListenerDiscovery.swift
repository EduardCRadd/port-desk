import Darwin
import Foundation

/// Captures one lsof invocation. Only this call owns and reaps its child.
struct ListenerDiscovery {
    var executable = "/usr/sbin/lsof"
    var arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-F0pcuftn"]
    var timeout: Duration = .seconds(5)

    func read() throws -> Data {
        try Task.checkCancellation()
        let deadline = ContinuousClock.now + timeout
        let output = Pipe(), diagnostics = Pipe()
        defer { withExtendedLifetime((output, diagnostics)) {} }
        let pid = try spawn(stdout: output, stderr: diagnostics)
        var reaped = false
        defer {
            if !reaped {
                // An unreaped direct child's PID cannot be reused. Never signal a listener here.
                kill(pid, SIGKILL)
                // A kernel I/O wait can delay even SIGKILL. Reap without holding up the caller.
                DispatchQueue.global(qos: .utility).async {
                    while waitpid(pid, nil, 0) == -1 && errno == EINTR {}
                }
            }
        }
        try output.fileHandleForWriting.close()
        try diagnostics.fileHandleForWriting.close()
        var readers = [output.fileHandleForReading, diagnostics.fileHandleForReading].map {
            pollfd(fd: $0.fileDescriptor, events: Int16(POLLIN), revents: 0)
        }
        var bytes = [UInt8](repeating: 0, count: 32 * 1024)
        var data = Data(), diagnostic = Data()
        var status: Int32 = 0

        while true {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else {
                throw DeskError("Listening port scan timed out.")
            }
            if readers.allSatisfy({ $0.fd == -1 }) {
                let result = waitpid(pid, &status, WNOHANG)
                if result == pid {
                    reaped = true
                    break
                }
                if result == -1 {
                    guard errno != EINTR else { continue }
                    // ECHILD means another reaper consumed the status; the PID is no longer ours.
                    reaped = errno == ECHILD
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
            }
            // A short bounded wait observes cancellation even when the child stays silent.
            let ready = poll(&readers, nfds_t(readers.count), 25)
            if ready < 0 {
                guard errno != EINTR else { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            for index in readers.indices where readers[index].revents != 0 {
                let count = Darwin.read(readers[index].fd, &bytes, bytes.count)
                if count < 0 {
                    guard errno != EINTR else { continue }
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                if count == 0 {
                    readers[index].fd = -1
                } else if index == 0 {
                    guard data.count + count <= 16 * 1024 * 1024 else {
                        throw DeskError("Listening port scan exceeded the output limit.")
                    }
                    data.append(contentsOf: bytes.prefix(count))
                } else {
                    diagnostic.append(contentsOf: bytes.prefix(min(count, 8192 - diagnostic.count)))
                }
            }
        }
        // Darwin wait status for a normal exit with code 1: lsof found no matching files.
        if status == 0 || (status == 1 << 8 && data.isEmpty && diagnostic.isEmpty) { return data }
        let detail = String(decoding: diagnostic, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        throw DeskError(detail.isEmpty ? "Listening port scan failed." : "Listening port scan failed: " + detail)
    }

    private func spawn(stdout: Pipe, stderr: Pipe) throws -> pid_t {
        func check(_ code: Int32) throws {
            if code != 0 { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
        }
        var actions: posix_spawn_file_actions_t?
        try check(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        try check(posix_spawn_file_actions_adddup2(&actions, stdout.fileHandleForWriting.fileDescriptor, STDOUT_FILENO))
        try check(posix_spawn_file_actions_adddup2(&actions, stderr.fileHandleForWriting.fileDescriptor, STDERR_FILENO))
        var attributes: posix_spawnattr_t?
        try check(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        try check(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT)))

        var argv = ([executable] + arguments).map { strdup($0) }
        defer { argv.forEach { free($0) } }
        guard argv.allSatisfy({ $0 != nil }) else { throw POSIXError(.ENOMEM) }
        argv.append(nil)
        var pid: pid_t = 0
        // lsof has an absolute path and needs no environment or input from the dashboard.
        var environment: [UnsafeMutablePointer<CChar>?] = [nil]
        try check(posix_spawn(&pid, executable, &actions, &attributes, &argv, &environment))
        return pid
    }
}
