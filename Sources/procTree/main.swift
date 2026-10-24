#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private func monoClock() -> Double {
    var ts = timespec()
    clock_gettime(CLOCK_MONOTONIC, &ts)
    return Double(ts.tv_sec) + Double(ts.tv_nsec) / 1_000_000_000.0
}

// ── Shared state updated by background collector ──────────────────────────────
private var sharedRoots: [ProcessData] = []
private var sharedStats = SystemStats()
private var sharedProcessCount = 0
private var dataReady = false
private var dataLock = pthread_mutex_t()

// ── Signal flags ──────────────────────────────────────────────────────────────
private var isRunning = true
signal(SIGPIPE, SIG_IGN)
signal(SIGINT)  { _ in isRunning = false }
signal(SIGTERM) { _ in isRunning = false }
signal(SIGWINCH) { _ in }

// ── Background data collection thread ────────────────────────────────────────
private func collectorThread(_: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
    let collector = ProcessCollector.shared
    let state     = AppState.shared          // read sortOrder only — write via lock

    while isRunning {
        let processes = collector.collectProcesses()
        let (roots, totalThreads) = collector.buildProcessTree(from: processes)
        let stats = collector.getSystemStats(processCount: processes.count,
                                             threadCount: totalThreads)

        // Record CPU history (guarded by lock)
        pthread_mutex_lock(&dataLock)
        var activePids = Set<pid_t>()
        for (pid, proc) in processes {
            activePids.insert(pid)
            state.recordCpuSample(pid: pid, cpu: proc.cpuPercent)
        }
        state.cleanDeadPids(currentPids: activePids)
        sharedRoots        = roots
        sharedStats        = stats
        sharedProcessCount = processes.count
        dataReady          = true
        pthread_mutex_unlock(&dataLock)

        // Sleep 1.5s in small chunks so we can exit promptly
        var slept = 0
        while isRunning && slept < 1_500_000 {
            usleep(50_000)
            slept += 50_000
        }
    }
    return nil
}

// ── Main ──────────────────────────────────────────────────────────────────────
func main() {
    pthread_mutex_init(&dataLock, nil)
    defer { pthread_mutex_destroy(&dataLock) }

    // Start background collector
    var tid: pthread_t?
    var dummy: Int = 0
    withUnsafeMutablePointer(to: &dummy) { ptr in
        pthread_create(&tid, nil, collectorThread, ptr)
    }

    let terminal = Terminal.shared
    terminal.enableRawMode()
    defer { terminal.disableRawMode() }

    let state    = AppState.shared
    let renderer = TreeRenderer.shared

    // Frame rate: ~20 FPS for smooth animation
    let frameInterval: UInt32 = 50_000  // 50 ms

    while isRunning {
        // Pull latest data from collector (non-blocking) — skip when paused
        pthread_mutex_lock(&dataLock)
        if dataReady && !state.isPaused {
            _ = state.buildVisibleRows(from: sharedRoots)
        }
        let stats = sharedStats
        pthread_mutex_unlock(&dataLock)

        // Render frame
        let size  = terminal.getWindowSize()
        let frame = renderer.render(state: state, stats: stats, size: size)
        terminal.writeRaw(frame)
        state.tick &+= 1

        // Poll keyboard (non-blocking read from /dev/tty)
        if let key = terminal.readKey() {
            switch key {
            case .char(let ch):
                switch ch {
                case "q", "Q": isRunning = false
                case "p", "P": state.isPaused.toggle()
                case "u", "U":
                    state.selectedIndex = 0; state.clampSelection()
                case "d", "D":
                    state.selectedIndex = state.cachedVisibleRows.count - 1; state.clampSelection()
                case "s", "S": state.sortOrder = state.sortOrder.next
                case "e", "E": state.toggleExpandCollapse()
                case "t", "T": state.toggleThreads()
                case "r", "R":
                    // force re-collect on next cycle (nothing to do — collector loops)
                    break
                case "j", "J":
                    state.selectedIndex += 1; state.clampSelection()
                case "k", "K":
                    state.selectedIndex -= 1; state.clampSelection()
                default: break
                }
            case .up:    state.selectedIndex -= 1; state.clampSelection()
            case .down:  state.selectedIndex += 1; state.clampSelection()
            case .left:  state.collapseSelected()
            case .right: state.expandSelected()
            case .pageUp:
                state.selectedIndex -= max(1, size.rows - 5); state.clampSelection()
            case .pageDown:
                state.selectedIndex += max(1, size.rows - 5); state.clampSelection()
            case .home:
                state.selectedIndex = 0; state.clampSelection()
            case .end:
                state.selectedIndex = state.cachedVisibleRows.count - 1
                state.clampSelection()
            case .enter:  state.toggleExpandCollapse()
            case .space:  state.toggleThreads()
            default: break
            }
        }

        usleep(frameInterval)
    }

    // Signal collector to stop and wait (it checks isRunning each loop)
    if let t = tid { pthread_join(t, nil) }
}

main()
