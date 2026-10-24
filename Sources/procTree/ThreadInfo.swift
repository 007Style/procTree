#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum ThreadState: Int {
    case running = 1
    case stopped = 2
    case waiting = 3
    case uninterruptible = 4
    case halted = 5
    case idle = 6
    case unknown = 0

    // Pure Swift label — avoids String rawValue dispatch_once in release
    public var label: String {
        switch self {
        case .running:        return "RUN"
        case .stopped:        return "STOP"
        case .waiting:        return "WAIT"
        case .uninterruptible:return "UNINT"
        case .halted:         return "HALT"
        case .idle:           return "IDLE"
        case .unknown:        return "???"
        }
    }

    public var colorPrefix: String {
        switch self {
        case .running:         return ANSI.green + ANSI.bold
        case .waiting:         return ANSI.cyan
        case .idle:            return ANSI.muted
        case .stopped:         return ANSI.yellow
        case .uninterruptible: return ANSI.red
        case .halted:          return ANSI.darkGray
        case .unknown:         return ANSI.muted
        }
    }
}

public struct ThreadData {
    public let tid: UInt64
    public let name: String
    public let state: ThreadState
    public let userTimeNs: UInt64
    public let systemTimeNs: UInt64
    public let cpuUsage: Int32
    public let priority: Int32

    public init(
        tid: UInt64,
        name: String = "",
        state: ThreadState = .unknown,
        userTimeNs: UInt64 = 0,
        systemTimeNs: UInt64 = 0,
        cpuUsage: Int32 = 0,
        priority: Int32 = 0
    ) {
        self.tid = tid
        self.name = name
        self.state = state
        self.userTimeNs = userTimeNs
        self.systemTimeNs = systemTimeNs
        self.cpuUsage = cpuUsage
        self.priority = priority
    }

    public var totalTimeSeconds: Double {
        return Double(userTimeNs + systemTimeNs) / 1_000_000_000.0
    }

    public var formattedTime: String {
        let total = totalTimeSeconds
        if total < 60.0 {
            // "N.NNs" — two decimal places, no Foundation
            let sInt = Int(total)
            let sFrac = Int((total - Double(sInt)) * 100.0 + 0.5)
            let (s2, f2): (Int, Int) = sFrac >= 100 ? (sInt + 1, 0) : (sInt, sFrac)
            let fStr = f2 < 10 ? "0\(f2)" : "\(f2)"
            return "\(s2).\(fStr)s"
        } else if total < 3600.0 {
            let mins = Int(total) / 60
            let secs = total - Double(mins * 60)
            let sInt = Int(secs)
            let sFrac = Int((secs - Double(sInt)) * 10.0 + 0.5)
            let (s2, f2): (Int, Int) = sFrac >= 10 ? (sInt + 1, 0) : (sInt, sFrac)
            return "\(mins)m\(s2).\(f2)s"
        } else {
            let hours = Int(total) / 3600
            let mins = (Int(total) % 3600) / 60
            return "\(hours)h\(mins)m"
        }
    }
}

public protocol ThreadDataProvider {
    func collectThreads(for pid: pid_t) -> [ThreadData]
}

public final class ThreadCollector: ThreadDataProvider {
    public static let shared = ThreadCollector()

    private init() {}

    public func collectThreads(for pid: pid_t) -> [ThreadData] {
        #if canImport(Darwin)
        let numThreads = proc_pidinfo(pid, PROC_PIDLISTTHREADS, 0, nil, 0)
        guard numThreads > 0 else { return [] }

        var tids = [UInt64](repeating: 0, count: Int(numThreads) / MemoryLayout<UInt64>.size + 16)
        let actualBytes = proc_pidinfo(pid, PROC_PIDLISTTHREADS, 0, &tids, Int32(tids.count * MemoryLayout<UInt64>.size))
        guard actualBytes > 0 else { return [] }

        let count = Int(actualBytes) / MemoryLayout<UInt64>.size
        var results: [ThreadData] = []
        results.reserveCapacity(count)

        for i in 0..<count {
            let tid = tids[i]
            var threadInfo = proc_threadinfo()
            let size = proc_pidinfo(pid, PROC_PIDTHREADINFO, tid, &threadInfo, Int32(MemoryLayout<proc_threadinfo>.size))

            if size == MemoryLayout<proc_threadinfo>.size {
                var state: ThreadState
                switch threadInfo.pth_run_state {
                case 1: state = .running
                case 2: state = .stopped
                case 3: state = .waiting
                case 4: state = .uninterruptible
                case 5: state = .halted
                default: state = .idle
                }

                var threadName = ""
                withUnsafePointer(to: threadInfo.pth_name) { ptr in
                    ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) { cStr in
                        threadName = String(cString: cStr)
                    }
                }

                results.append(ThreadData(
                    tid: tid,
                    name: threadName,
                    state: state,
                    userTimeNs: threadInfo.pth_user_time,
                    systemTimeNs: threadInfo.pth_system_time,
                    cpuUsage: threadInfo.pth_cpu_usage,
                    priority: threadInfo.pth_priority
                ))
            } else {
                results.append(ThreadData(
                    tid: tid,
                    name: "",
                    state: .unknown,
                    userTimeNs: 0,
                    systemTimeNs: 0,
                    cpuUsage: 0,
                    priority: 0
                ))
            }
        }

        return results
        #else
        return []
        #endif
    }
}
