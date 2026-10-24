import Darwin

// MARK: - Pure Swift formatting helpers (no Foundation/ObjC, safe in release)

/// Pure Swift string padding helpers — replaces Foundation's padding(toLength:withPad:startingAt:)
private extension String {
    /// Left-pad (right-align) a string to `width` chars with spaces.
    func rpadded(to width: Int) -> String {
        if self.count >= width { return String(self.suffix(width)) }
        return String(repeating: " ", count: width - self.count) + self
    }
    /// Right-pad (left-align) a string to `width` chars with spaces.
    func lpadded(to width: Int) -> String {
        if self.count >= width { return String(self.prefix(width)) }
        return self + String(repeating: " ", count: width - self.count)
    }
}

/// Format a Double as "NNN.N" right-aligned to `width` chars (no Foundation).
private func fmtF1(_ value: Double, width: Int) -> String {
    let abs = value < 0 ? -value : value
    let intPart = Int(abs)
    let frac = Int((abs - Double(intPart)) * 10.0 + 0.5)
    let (i2, f2): (Int, Int) = frac >= 10 ? (intPart + 1, 0) : (intPart, frac)
    let s = "\(i2).\(f2)"
    if s.count >= width { return s }
    return String(repeating: " ", count: width - s.count) + s
}

public final class TreeRenderer {
    public static let shared = TreeRenderer()

    // Sparkline levels: 0 to 7
    private let sparkChars: [Character] = [" ", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
    private let pulseFrames: [String] = ["◉", "●", "⦿", "◎"]
    private let spinnerFrames: [String] = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    private init() {}

    public func sparkline(history: [Double], width: Int = 8, maxVal: Double = 100.0) -> String {
        guard !history.isEmpty else {
            return String(repeating: " ", count: width)
        }
        var padded = history
        if padded.count < width {
            padded = Array(repeating: 0.0, count: width - padded.count) + padded
        } else if padded.count > width {
            padded = Array(padded.suffix(width))
        }

        var result = ""
        for val in padded {
            let clamped = min(max(val, 0.0), maxVal)
            let ratio = clamped / maxVal
            let index = Int(ratio * Double(sparkChars.count - 1))
            let char = sparkChars[min(max(index, 0), sparkChars.count - 1)]

            // Colorize sparkline points
            if val > 50.0 {
                result += ANSI.red + String(char)
            } else if val > 15.0 {
                result += ANSI.yellow + String(char)
            } else if val > 2.0 {
                result += ANSI.green + String(char)
            } else {
                result += ANSI.dimMuted + String(char)
            }
        }
        result += ANSI.reset
        return result
    }

    public func miniBar(ratio: Double, width: Int = 6, fgColor: String = ANSI.cyan) -> String {
        let clamped = min(max(ratio, 0.0), 1.0)
        let filledCount = Int(round(clamped * Double(width)))
        let emptyCount = max(0, width - filledCount)

        let filled = String(repeating: "█", count: filledCount)
        let empty = String(repeating: "░", count: emptyCount)
        return fgColor + filled + ANSI.dimMuted + empty + ANSI.reset
    }

    public func cpuColor(_ cpu: Double) -> String {
        if cpu > 40.0 {
            return ANSI.red + ANSI.bold
        } else if cpu > 10.0 {
            return ANSI.yellow + ANSI.bold
        } else if cpu > 1.0 {
            return ANSI.green
        } else {
            return ANSI.muted
        }
    }

    public func padString(_ str: String, to width: Int, alignRight: Bool = false) -> String {
        let visibleLen = visibleWidth(str)
        if visibleLen >= width {
            return String(str.prefix(width))
        }
        let pad = String(repeating: " ", count: width - visibleLen)
        return alignRight ? (pad + str) : (str + pad)
    }

    public func visibleWidth(_ str: String) -> Int {
        var count = 0
        var insideAnsi = false
        for ch in str {
            if ch == "\u{1b}" {
                insideAnsi = true
                continue
            }
            if insideAnsi {
                // ANSI sequences end on any ASCII letter
                let ascii = ch.asciiValue ?? 0
                if (ascii >= 65 && ascii <= 90) || (ascii >= 97 && ascii <= 122) {
                    insideAnsi = false
                }
                continue
            }
            count += 1
        }
        return count
    }

    public func truncateWithEllipsis(_ str: String, maxLen: Int) -> String {
        if str.count <= maxLen { return str }
        guard maxLen > 1 else { return String(str.prefix(maxLen)) }
        return String(str.prefix(maxLen - 1)) + "…"
    }

    public func render(state: AppState, stats: SystemStats, size: Terminal.Size) -> String {
        var output = ""
        output.reserveCapacity(size.rows * size.cols * 4)

        // Move cursor to top-left; do NOT clear the whole screen every frame
        // (causes flicker) — instead we overwrite every line to exact column width
        output += "\u{1b}[H" + ANSI.reset

        let totalRows = size.rows
        let cols = max(size.cols, 60)

        // 1. Header (Title + Sort + Spinner)
        let spinner = spinnerFrames[Int(state.tick) % spinnerFrames.count]
        let pulseIcon = pulseFrames[Int(state.tick / 2) % pulseFrames.count]

        let titleLeft = " \(ANSI.cyan)\(ANSI.bold)⬡ procTree\(ANSI.reset) \(ANSI.dimMuted)│\(ANSI.reset) \(ANSI.white)Process & Thread Tree\(ANSI.reset)"
        let sortStr = "\(ANSI.muted)Sort: [\(ANSI.yellow)\(ANSI.bold)\(state.sortOrder.label)\(ANSI.reset)\(ANSI.muted)] (press 's')\(ANSI.reset)"
        let liveStr = state.isPaused
            ? "\(ANSI.yellow)\(ANSI.bold)⏸ PAUSED\(ANSI.reset) "
            : "\(ANSI.green)\(ANSI.bold)\(pulseIcon) LIVE\(ANSI.reset) \(ANSI.cyan)\(spinner)\(ANSI.reset) "

        let headerVisible = visibleWidth(titleLeft) + visibleWidth(sortStr) + visibleWidth(liveStr)
        let headerSpace = max(1, cols - headerVisible)
        let headerLine = "\(ANSI.headerBg)\(titleLeft)\(String(repeating: " ", count: headerSpace / 2))\(sortStr)\(String(repeating: " ", count: (headerSpace + 1) / 2))\(liveStr)\(ANSI.reset)"
        output += headerLine + "\r\n"

        // 2. System Stats Dashboard
        let cpuRatio = stats.systemCpuPercent / 100.0
        let memRatio = stats.ramPercent / 100.0
        let cpuBar = miniBar(ratio: cpuRatio, width: 8, fgColor: stats.systemCpuPercent > 50 ? ANSI.red : ANSI.green)
        let memBar = miniBar(ratio: memRatio, width: 8, fgColor: stats.ramPercent > 80 ? ANSI.red : ANSI.brightBlue)

        let cpuStat = "\(ANSI.muted)CPU:\(ANSI.reset) [\(cpuBar)] \(ANSI.bold)\(fmtF1(stats.systemCpuPercent, width: 5))%\(ANSI.reset)"
        let memStat = "\(ANSI.muted)RAM:\(ANSI.reset) [\(memBar)] \(ANSI.bold)\(fmtF1(stats.usedRamGB, width: 4))/\(fmtF1(stats.totalRamGB, width: 4)) GB (\(Int(stats.ramPercent))%)\(ANSI.reset)"
        let procStat = "\(ANSI.muted)PROCS:\(ANSI.reset) \(ANSI.bold)\(ANSI.cyan)\(stats.totalProcesses)\(ANSI.reset)"
        let thStat = "\(ANSI.muted)THREADS:\(ANSI.reset) \(ANSI.bold)\(ANSI.magenta)\(stats.totalThreads)\(ANSI.reset)"

        let statsContent = "  \(cpuStat)  \(ANSI.dimMuted)│\(ANSI.reset)  \(memStat)  \(ANSI.dimMuted)│\(ANSI.reset)  \(procStat)  \(ANSI.dimMuted)│\(ANSI.reset)  \(thStat)"
        let statsPad = max(0, cols - visibleWidth(statsContent))
        output += "\(ANSI.headerBg)\(statsContent)\(String(repeating: " ", count: statsPad))\(ANSI.reset)\r\n"

        // 3. Table Column Header
        let colPid  = "PID".lpadded(to: 7)
        let colCpu  = "  CPU% ".lpadded(to: 8)
        let colHist = " HISTORY ".lpadded(to: 9)
        let colMem  = " MEM (RSS) ".lpadded(to: 11)
        let colBar  = "  BAR  ".lpadded(to: 8)
        let colTh   = " THREADS / STATE ".lpadded(to: 17)

        let fixedColsWidth = 7 + 8 + 9 + 11 + 8 + 17
        let nameWidth = max(12, cols - fixedColsWidth - 4)

        let colName = "PROCESS / THREAD TREE".lpadded(to: nameWidth)
        let tableHeader = " \(ANSI.bold)\(ANSI.muted)\(colPid) \(colName) \(colCpu) \(colHist) \(colMem) \(colBar) \(colTh)\(ANSI.reset)"
        let thPad = max(0, cols - visibleWidth(tableHeader))
        output += "\(tableHeader)\(String(repeating: " ", count: thPad))\r\n"

        // Separator line
        let sep = String(repeating: "─", count: cols)
        output += "\(ANSI.dimMuted)\(sep)\(ANSI.reset)\r\n"

        // 4. Viewport & Tree Rows
        // Reserved rows: 1 (Header), 2 (Stats), 3 (ColHeader), 4 (Sep), Last (Status) -> total 5 rows
        let viewportHeight = max(1, totalRows - 5)
        state.adjustScroll(viewportHeight: viewportHeight)

        let visibleRows = state.cachedVisibleRows
        let startIndex = state.scrollOffset

        for lineIndex in 0..<viewportHeight {
            let rowIndex = startIndex + lineIndex
            if rowIndex < visibleRows.count {
                let row = visibleRows[rowIndex]
                let isSelected = (rowIndex == state.selectedIndex)
                output += renderRow(row: row, isSelected: isSelected, nameWidth: nameWidth, cols: cols, state: state, totalRamBytes: stats.totalRamBytes)
            } else {
                // Blank row — write spaces to cols so stale content is overwritten
                output += String(repeating: " ", count: cols)
            }
            output += "\r\n"
        }

        // 5. Status Bar Footer
        let navHelp = " \(ANSI.yellow)[↑/↓]\(ANSI.reset)\(ANSI.muted)Nav \(ANSI.yellow)[u]\(ANSI.reset)\(ANSI.muted)Top \(ANSI.yellow)[d]\(ANSI.reset)\(ANSI.muted)Bottom \(ANSI.yellow)[e]\(ANSI.reset)\(ANSI.muted)Expand \(ANSI.yellow)[t]\(ANSI.reset)\(ANSI.muted)Threads \(ANSI.yellow)[s]\(ANSI.reset)\(ANSI.muted)Sort \(ANSI.yellow)[p]\(ANSI.reset)\(ANSI.muted)Pause \(ANSI.yellow)[q]\(ANSI.reset)\(ANSI.muted)Quit\(ANSI.reset)"
        let selInfo: String
        if !visibleRows.isEmpty && state.selectedIndex < visibleRows.count {
            let row = visibleRows[state.selectedIndex]
            switch row.kind {
            case .process(let proc):
                let childCount = proc.children.count
                let thCount = proc.threads.count
                selInfo = "\(ANSI.cyan)PID \(proc.pid): \(proc.name)\(ANSI.reset) \(ANSI.dimMuted)(\(childCount) children, \(thCount) threads)\(ANSI.reset)"
            case .thread(let th, let ppid):
                let thName = th.name.isEmpty ? "(unnamed)" : th.name
                selInfo = "\(ANSI.magenta)Thread \(th.tid) of PID \(ppid): \(thName) [\(th.state.label)]\(ANSI.reset)"
            }
        } else {
            selInfo = ""
        }

        let scrollInfo = visibleRows.isEmpty ? "" : "\(ANSI.dimMuted)[\(state.selectedIndex + 1)/\(visibleRows.count)]\(ANSI.reset) "
        let leftStatus = "\(navHelp)  \(ANSI.dimMuted)│\(ANSI.reset)  \(selInfo)"
        let rightStatus = "\(scrollInfo)"

        let statusVisible = visibleWidth(leftStatus) + visibleWidth(rightStatus)
        let statusSpace = max(0, cols - statusVisible)
        let footerLine = "\(ANSI.statusBarBg)\(leftStatus)\(String(repeating: " ", count: statusSpace))\(rightStatus)\(ANSI.reset)"
        output += footerLine

        return output
    }

    private func renderRow(
        row: VisibleRow,
        isSelected: Bool,
        nameWidth: Int,
        cols: Int,
        state: AppState,
        totalRamBytes: UInt64
    ) -> String {
        var rowOutput = ""
        let bg = isSelected ? ANSI.selectionBg : ""
        let selIndicator = isSelected ? "\(ANSI.yellow)\(ANSI.bold)▶\(ANSI.reset)" : " "

        switch row.kind {
        case .process(let proc):
            // Active pulse indicator
            let isActive = proc.cpuPercent > 0.5
            let pulseChar: String
            if isActive {
                let idx = Int((state.tick + UInt64(proc.pid)) % 4)
                let pulseColors = [ANSI.green, ANSI.yellow, ANSI.orange, ANSI.green]
                pulseChar = "\(pulseColors[idx])●\(ANSI.reset)"
            } else {
                pulseChar = "\(ANSI.dimMuted)⬡\(ANSI.reset)"
            }

            // Expand/collapse icon
            let foldIcon: String
            if !proc.children.isEmpty || !proc.threads.isEmpty {
                if !row.isExpanded {
                    foldIcon = "\(ANSI.yellow)▶\(ANSI.reset) "
                } else if row.areThreadsExpanded {
                    foldIcon = "\(ANSI.magenta)▼\(ANSI.reset) "
                } else {
                    foldIcon = "\(ANSI.cyan)▼\(ANSI.reset) "
                }
            } else {
                foldIcon = "  "
            }

            // PID
            let pidStr = String(proc.pid).rpadded(to: 6)
            let pidFormatted = "\(ANSI.dimMuted)\(pidStr)\(ANSI.reset)"

            // Tree prefix + name
            let prefixColored = "\(ANSI.darkGray)\(row.prefix)\(ANSI.reset)"
            let procName = proc.name
            let rawTreeAndName = row.prefix + (foldIcon.isEmpty ? "" : "  ") + procName
            let maxTreeNameWidth = nameWidth
            let truncatedName: String
            if rawTreeAndName.count > maxTreeNameWidth {
                let availableForName = max(4, maxTreeNameWidth - row.prefix.count - 2)
                truncatedName = truncateWithEllipsis(procName, maxLen: availableForName)
            } else {
                truncatedName = procName
            }

            let nameColored = "\(ANSI.bold)\(ANSI.white)\(truncatedName)\(ANSI.reset)"
            let treeCol = "\(prefixColored)\(pulseChar) \(foldIcon)\(nameColored)"
            let treeVisible = visibleWidth(row.prefix) + 1 + 1 + 2 + truncatedName.count
            let treePad = max(0, nameWidth - treeVisible)
            let treeSection = treeCol + String(repeating: " ", count: treePad)

            // CPU %
            let cpuVal = proc.cpuPercent
            let cpuColored = "\(cpuColor(cpuVal))\(fmtF1(cpuVal, width: 6))%\(ANSI.reset)"

            // Sparkline history
            let history = state.cpuHistory[proc.pid] ?? [cpuVal]
            let spark = sparkline(history: history, width: 8, maxVal: max(50.0, history.max() ?? 10.0))

            // Memory RSS
            let memVal = proc.rssMB
            let memStr: String
            if memVal >= 1024.0 {
                memStr = "\(fmtF1(memVal / 1024.0, width: 6)) GB"
            } else {
                memStr = "\(fmtF1(memVal, width: 6)) MB"
            }
            let memColored = "\(ANSI.brightBlue)\(memStr)\(ANSI.reset)"

            // Memory Bar
            let memRatio = totalRamBytes > 0 ? (Double(proc.rssBytes) / Double(totalRamBytes)) * 20.0 : 0.0 // scaled
            let mBar = miniBar(ratio: memRatio, width: 6, fgColor: ANSI.brightBlue)

            // Threads count & children info
            let thCount = proc.threads.count
            let thStr = thCount > 0 ? "\(ANSI.magenta)\(thCount) th\(ANSI.reset)" : "\(ANSI.dimMuted)-   \(ANSI.reset)"
            let childInfo = !proc.children.isEmpty ? "\(ANSI.dimMuted)(\(proc.children.count) ch)\(ANSI.reset)" : ""
            let thSection = "\(thStr) \(childInfo)".lpadded(to: 17)

            let fullLine = "\(selIndicator)\(pidFormatted) \(treeSection) \(cpuColored) \(spark) \(memColored) [\(mBar)] \(thSection)"
            let linePad = max(0, cols - visibleWidth(fullLine))
            rowOutput = "\(bg)\(fullLine)\(String(repeating: " ", count: linePad))\(ANSI.reset)"

        case .thread(let th, _):
            // Thread row (indented, dimmer, thread-specific fields)
            let tidStr = String(th.tid % 1_000_000).rpadded(to: 6)
            let pidFormatted = "\(ANSI.darkGray)\(tidStr)\(ANSI.reset)"

            let prefixColored = "\(ANSI.darkGray)\(row.prefix)\(ANSI.reset)"
            let thIcon = "\(ANSI.magenta)⤷\(ANSI.reset)"
            let thName = th.name.isEmpty ? "Thread \(th.tid)" : th.name
            let maxThWidth = max(4, nameWidth - row.prefix.count - 3)
            let truncatedThName = truncateWithEllipsis(thName, maxLen: maxThWidth)
            let thNameColored = "\(ANSI.dim)\(ANSI.muted)\(truncatedThName)\(ANSI.reset)"

            let treeCol = "\(prefixColored)\(thIcon) \(thNameColored)"
            let treeVisible = visibleWidth(row.prefix) + 2 + truncatedThName.count
            let treePad = max(0, nameWidth - treeVisible)
            let treeSection = treeCol + String(repeating: " ", count: treePad)

            // Thread CPU & stats
            let cpuColored = "\(ANSI.dimMuted)   ---  \(ANSI.reset)"
            let spark = "        "
            let timeStr = th.formattedTime.lpadded(to: 10)
            let memColored = "\(ANSI.dimMuted)\(timeStr)\(ANSI.reset)"
            let mBar = "      "

            // State badge
            let stateBadge = "\(th.state.colorPrefix)[\(th.state.label)]\(ANSI.reset)"
            let thSection = stateBadge.lpadded(to: 17)

            let fullLine = "\(selIndicator)\(pidFormatted) \(treeSection) \(cpuColored) \(spark) \(memColored)  \(mBar)   \(thSection)"
            let linePad = max(0, cols - visibleWidth(fullLine))
            rowOutput = "\(bg)\(fullLine)\(String(repeating: " ", count: linePad))\(ANSI.reset)"
        }

        return rowOutput
    }
}
