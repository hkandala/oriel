// What an app and the processes it is responsible for (WebKit's, its herdr runs) use over some seconds: their count,
// footprint at the end, CPU, threads and interrupt wake-ups a second, for the app, WebKit's processes and all of them.
// A process started meanwhile counts no CPU or wake-ups.
// Usage: usage <pid> <seconds>   (the e2e helper's `usage`)
import Darwin
import Foundation

let args = CommandLine.arguments
guard args.count == 3, let app = pid_t(args[1]), let seconds = Double(args[2]) else {
    fatalError("usage: usage <pid> <seconds>")
}

let responsible = unsafeBitCast(
    dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid"),
    to: (@convention(c) (pid_t) -> pid_t).self,
)
var timebase = mach_timebase_info_data_t()
mach_timebase_info(&timebase)

struct Sample {
    let name: String, cpu: Double, footprint: UInt64, threads: Int, wakeups: UInt64
}

func parent(_ pid: pid_t) -> pid_t {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? pid_t(info.pbi_ppid) : 0
}

/// The app and every process it started or is responsible for, by pid.
func sample() -> [pid_t: Sample] {
    var pids = [pid_t](repeating: 0, count: 8192)
    let count = Int(max(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)), 0))
    var samples: [pid_t: Sample] = [:]
    for pid in pids.prefix(count) where pid == app || parent(pid) == app || responsible(pid) == app {
        var usage = rusage_info_v6()
        let status = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
        }
        guard status == 0 else { continue }
        var task = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let threads = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, size) == size ? Int(task.pti_threadnum) : 0
        var name = [CChar](repeating: 0, count: 256)
        proc_name(pid, &name, UInt32(name.count))
        let nanoseconds = (usage.ri_user_time + usage.ri_system_time) * UInt64(timebase.numer) / UInt64(timebase.denom)
        samples[pid] = Sample(name: String(cString: name), cpu: Double(nanoseconds) / 1e9,
                              footprint: usage.ri_phys_footprint, threads: threads, wakeups: usage.ri_interrupt_wkups)
    }
    return samples
}

let before = sample(), start = Date()
Thread.sleep(forTimeInterval: seconds)
let after = sample(), wall = Date().timeIntervalSince(start)

func line(_ group: String, _ pids: [pid_t]) -> String {
    let cpu = pids.reduce(0.0) { $0 + after[$1]!.cpu - (before[$1]?.cpu ?? after[$1]!.cpu) }
    let wakeups = pids.reduce(0.0) { $0 + Double(after[$1]!.wakeups - (before[$1]?.wakeups ?? after[$1]!.wakeups)) }
    let footprint = pids.reduce(0) { $0 + after[$1]!.footprint } >> 20
    let threads = pids.reduce(0) { $0 + after[$1]!.threads }
    return "\(group) \(pids.count) footprint \(footprint) MB cpu \(String(format: "%.1f", 100 * cpu / wall))% threads "
        + "\(threads) wakeups \(Int(wakeups / wall))/s"
}

let all = Array(after.keys)
print(line("app", all.filter { $0 == app }))
print(line("webkit", all.filter { after[$0]!.name.contains("WebKit") }))
print(line("all", all))
