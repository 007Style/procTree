import Darwin

public enum SortOrder: Int, CaseIterable {
    case cpu = 0
    case mem = 1
    case pid = 2
    case name = 3

    // Pure Swift display label — no String rawValue to avoid dispatch_once in release
    public var label: String {
        switch self {
        case .cpu:  return "CPU%"
        case .mem:  return "MEM"
        case .pid:  return "PID"
        case .name: return "NAME"
        }
    }

    public var next: SortOrder {
        return SortOrder(rawValue: (self.rawValue + 1) % SortOrder.allCases.count) ?? .cpu
    }
}

public enum VisibleRowKind {
    case process(ProcessData)
    case thread(ThreadData, parentPid: pid_t)

    public var id: String {
        switch self {
        case .process(let proc):
            return "p_\(proc.pid)"
        case .thread(let th, let ppid):
            return "t_\(ppid)_\(th.tid)"
        }
    }
}

public struct VisibleRow {
    public let kind: VisibleRowKind
    public let depth: Int
    public let prefix: String
    public let isLastChild: Bool
    public let hasChildren: Bool
    public let isExpanded: Bool
    public let areThreadsExpanded: Bool
}

public final class AppState {
    public static let shared = AppState()

    public var sortOrder: SortOrder = .cpu
    public var selectedIndex: Int = 0
    public var scrollOffset: Int = 0

    // Set of collapsed process PIDs (where child processes are hidden)
    public var collapsedProcesses: Set<pid_t> = []
    // Set of process PIDs where threads are expanded
    public var expandedThreads: Set<pid_t> = []

    // Rolling CPU history (10 samples per PID)
    public var cpuHistory: [pid_t: [Double]] = [:]

    // Pause flag — freezes data updates while still allowing navigation
    public var isPaused: Bool = false

    // Animation tick
    public var tick: UInt64 = 0

    public var cachedVisibleRows: [VisibleRow] = []

    public init() {}

    public func recordCpuSample(pid: pid_t, cpu: Double) {
        var history = cpuHistory[pid] ?? []
        history.append(cpu)
        if history.count > 10 {
            history.removeFirst(history.count - 10)
        }
        cpuHistory[pid] = history
    }

    public func cleanDeadPids(currentPids: Set<pid_t>) {
        for pid in cpuHistory.keys where !currentPids.contains(pid) {
            cpuHistory.removeValue(forKey: pid)
            collapsedProcesses.remove(pid)
            expandedThreads.remove(pid)
        }
    }

    public func sortChildren(_ children: [ProcessData]) -> [ProcessData] {
        return children.sorted { (a, b) -> Bool in
            switch sortOrder {
            case .cpu:
                if a.cpuPercent != b.cpuPercent {
                    return a.cpuPercent > b.cpuPercent
                }
                return a.rssBytes > b.rssBytes
            case .mem:
                if a.rssBytes != b.rssBytes {
                    return a.rssBytes > b.rssBytes
                }
                return a.cpuPercent > b.cpuPercent
            case .pid:
                return a.pid < b.pid
            case .name:
                return a.name.lowercased() < b.name.lowercased()
            }
        }
    }

    public func buildVisibleRows(from roots: [ProcessData]) -> [VisibleRow] {
        var rows: [VisibleRow] = []

        func traverse(node: ProcessData, depth: Int, ancestorsAreLast: [Bool]) {
            let isCollapsed = collapsedProcesses.contains(node.pid)
            let threadsOpen = expandedThreads.contains(node.pid)
            let sortedChildren = sortChildren(node.children)
            let hasChildNodes = !sortedChildren.isEmpty || !node.threads.isEmpty

            // Build box-drawing prefix string based on ancestor positions
            var prefix = ""
            for (idx, isLast) in ancestorsAreLast.enumerated() {
                if idx < ancestorsAreLast.count - 1 {
                    prefix += isLast ? "    " : "│   "
                } else {
                    prefix += isLast ? "└── " : "├── "
                }
            }

            rows.append(VisibleRow(
                kind: .process(node),
                depth: depth,
                prefix: prefix,
                isLastChild: ancestorsAreLast.last ?? true,
                hasChildren: hasChildNodes,
                isExpanded: !isCollapsed,
                areThreadsExpanded: threadsOpen
            ))

            // If threads are expanded for this process, add thread rows
            if threadsOpen && !node.threads.isEmpty {
                let threadPrefixBase = ancestorsAreLast.map { $0 ? "    " : "│   " }.joined()
                for (tIdx, th) in node.threads.enumerated() {
                    let isLast = (tIdx == node.threads.count - 1) && (isCollapsed || sortedChildren.isEmpty)
                    let thPrefix = threadPrefixBase + (isLast ? "└── " : "├── ")
                    rows.append(VisibleRow(
                        kind: .thread(th, parentPid: node.pid),
                        depth: depth + 1,
                        prefix: thPrefix,
                        isLastChild: isLast,
                        hasChildren: false,
                        isExpanded: false,
                        areThreadsExpanded: false
                    ))
                }
            }

            // Recurse into children if not collapsed
            if !isCollapsed {
                for (index, child) in sortedChildren.enumerated() {
                    let isLast = (index == sortedChildren.count - 1)
                    traverse(node: child, depth: depth + 1, ancestorsAreLast: ancestorsAreLast + [isLast])
                }
            }
        }

        let sortedRoots = sortChildren(roots)
        for (index, root) in sortedRoots.enumerated() {
            let isLast = (index == sortedRoots.count - 1)
            traverse(node: root, depth: 0, ancestorsAreLast: [isLast])
        }

        cachedVisibleRows = rows
        clampSelection()
        return rows
    }

    public func clampSelection() {
        if cachedVisibleRows.isEmpty {
            selectedIndex = 0
            scrollOffset = 0
            return
        }
        if selectedIndex < 0 {
            selectedIndex = 0
        }
        if selectedIndex >= cachedVisibleRows.count {
            selectedIndex = cachedVisibleRows.count - 1
        }
    }

    public func adjustScroll(viewportHeight: Int) {
        guard viewportHeight > 0 else { return }
        if selectedIndex < scrollOffset {
            scrollOffset = selectedIndex
        } else if selectedIndex >= scrollOffset + viewportHeight {
            scrollOffset = selectedIndex - viewportHeight + 1
        }
        if scrollOffset < 0 {
            scrollOffset = 0
        }
        let maxOffset = max(0, cachedVisibleRows.count - viewportHeight)
        if scrollOffset > maxOffset {
            scrollOffset = maxOffset
        }
    }

    public func toggleExpandCollapse() {
        guard selectedIndex >= 0 && selectedIndex < cachedVisibleRows.count else { return }
        let row = cachedVisibleRows[selectedIndex]
        switch row.kind {
        case .process(let proc):
            if !proc.children.isEmpty {
                if collapsedProcesses.contains(proc.pid) {
                    collapsedProcesses.remove(proc.pid)
                } else {
                    collapsedProcesses.insert(proc.pid)
                }
            } else if !proc.threads.isEmpty {
                toggleThreads()
            }
        case .thread:
            break
        }
    }

    public func toggleThreads() {
        guard selectedIndex >= 0 && selectedIndex < cachedVisibleRows.count else { return }
        let row = cachedVisibleRows[selectedIndex]
        switch row.kind {
        case .process(let proc):
            if expandedThreads.contains(proc.pid) {
                expandedThreads.remove(proc.pid)
            } else {
                expandedThreads.insert(proc.pid)
            }
        case .thread(_, let parentPid):
            expandedThreads.remove(parentPid)
        }
    }

    public func expandSelected() {
        guard selectedIndex >= 0 && selectedIndex < cachedVisibleRows.count else { return }
        let row = cachedVisibleRows[selectedIndex]
        if case .process(let proc) = row.kind {
            if collapsedProcesses.contains(proc.pid) {
                collapsedProcesses.remove(proc.pid)
            } else if !expandedThreads.contains(proc.pid) && !proc.threads.isEmpty {
                expandedThreads.insert(proc.pid)
            }
        }
    }

    public func collapseSelected() {
        guard selectedIndex >= 0 && selectedIndex < cachedVisibleRows.count else { return }
        let row = cachedVisibleRows[selectedIndex]
        if case .process(let proc) = row.kind {
            if expandedThreads.contains(proc.pid) {
                expandedThreads.remove(proc.pid)
            } else if !collapsedProcesses.contains(proc.pid) && !proc.children.isEmpty {
                collapsedProcesses.insert(proc.pid)
            }
        } else if case .thread(_, let parentPid) = row.kind {
            expandedThreads.remove(parentPid)
        }
    }
}
