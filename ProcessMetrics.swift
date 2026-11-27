import Darwin
import Foundation

struct ResourceSample {
    let identity: Identity
    let timestamp: UInt64
    let cpuTicks: UInt64
    let wakeups: UInt64
    let footprint: UInt64

    static func read(_ listener: Listener) -> Self? {
        guard let expected = listener.fingerprint else { return nil }
        var usage = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(listener.id, RUSAGE_INFO_V2, $0)
            }
        }
        guard result == 0, identityForPID(listener.id) == expected else { return nil }
        return Self(identity: expected, timestamp: mach_absolute_time(),
                    cpuTicks: usage.ri_user_time + usage.ri_system_time,
                    wakeups: usage.ri_interrupt_wkups, footprint: usage.ri_phys_footprint)
    }
}

private func identityForPID(_ pid: Int32) -> Identity? { identity(processInfo(pid)) }

struct ProcessMetrics {
    var memory: UInt64?
    var cpu: Double?
    var energy: String?
    var memoryText: String { memory.map { "\(Int((Double($0) / 1_000_000).rounded())) MB" } ?? "—" }
    var cpuText: String { cpu.map { "\(Int($0.rounded()))%" } ?? "—" }

    init() {}

    init(_ sample: ResourceSample, previous: ResourceSample?, secondsPerTick: Double) {
        memory = sample.footprint
        guard let previous, previous.identity == sample.identity, previous.timestamp < sample.timestamp,
              previous.cpuTicks <= sample.cpuTicks, previous.wakeups <= sample.wakeups else { return }
        let elapsed = Double(sample.timestamp - previous.timestamp)
        let percent = 100 * Double(sample.cpuTicks - previous.cpuTicks) / elapsed
        let wakeRate = Double(sample.wakeups - previous.wakeups) / (elapsed * secondsPerTick)
        cpu = percent
        if percent >= 50 || wakeRate >= 100 { energy = "High" }
        else if percent >= 10 || wakeRate >= 20 { energy = "Medium" }
        else { energy = "Low" }
    }

    static let secondsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1e9
    }()
}

struct PollSchedule {
    let visible: Bool
    let interval: Int
    var delay: Duration { .seconds(visible ? min(10, max(1, interval)) : 30) }
}
