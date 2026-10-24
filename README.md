# ⬡ procTree

> **From the minds of Bob & Daneyand**

A live, animated terminal UI for macOS that visualizes every running process and its child threads as a fully interactive, color-coded tree. Built entirely in Swift with zero external dependencies — just raw Darwin APIs, ANSI escape codes, and a lot of love for the command line.

---

## What is procTree?

Most process monitors show you a flat list. `procTree` shows you the **shape** of your system — which processes spawned which children, which threads are alive inside each process, how much CPU each one is consuming over time, and how much RAM it holds. All of it rendered live in your terminal, updating every 1.5 seconds, with smooth animations that make it genuinely satisfying to watch.

It is the kind of tool you open when you want to actually *understand* what your Mac is doing, not just kill a runaway process. You can drill into a process, expand its thread list, pause the whole view to study a snapshot in detail, sort by any metric, and navigate the entire tree with simple single-key commands.

---

## Features

### 🌳 Full Process Hierarchy
The process tree is rooted at PID 1 (`launchd`) when run with `sudo`, showing every parent-child relationship on the system. Without `sudo`, all visible processes are grouped under a synthetic `(system / orphans)` root. Either way, the full shape of the tree is preserved using box-drawing characters:

```
  ⬡ launchd
  ├── WindowServer
  │   ├── Quartz Compositor
  │   └── CGXServer
  ├── Google Chrome
  │   ├── Chrome Helper (GPU)
  │   ├── Chrome Helper (Renderer)
  │   └── Chrome Helper (Renderer)
  └── Terminal
```

### ◎ Thread Inspection
Press `t` on any process to expand its thread list. Each thread shows:
- Thread ID (TID)
- Thread name (if set by the application)
- Execution state: `RUN`, `WAIT`, `STOP`, `UNINT`, `HALT`, `IDLE`
- Cumulative CPU time (user + system)

Threads are visually distinct from processes — dimmer, indented differently, and prefixed with `⤷` instead of the process hexagon `⬡`.

### 📊 Sparkline CPU History
Every process carries a rolling 10-sample sparkline showing its recent CPU activity:

```
▁▂▃▄▅▆▇█
```

The sparkline colors shift from muted (idle) through green (light load), yellow (moderate), and red (heavy). This gives you an instant visual sense of which processes are trending up in CPU versus which just had a momentary spike.

### 🧱 Memory Bars
Each process shows its RSS (Resident Set Size) memory usage as both a human-readable number (`124.3 MB` or `1.2 GB`) and a proportional mini bar:

```
[████░░░░]
```

The bar is scaled relative to total physical RAM, so a process that has filled half your RAM will show four full blocks.

### 💓 Live Activity Pulse
Processes that are actively consuming CPU pulse with an animated indicator that cycles through `◉ → ● → ⦿ → ◎`. Idle processes show a static dim hexagon `⬡`. This makes it immediately obvious at a glance which parts of the tree are hot.

### 🖥 System Dashboard
The second line of the display is a live system-wide dashboard:

```
CPU: [████░░░░]  24.5%  │  RAM: [██████░░]  33.9/64.0 GB (52%)  │  PROCS: 742  │  THREADS: 4821
```

All values update in real time from Darwin host statistics APIs.

### ⏸ Pause & Explore
Press `p` to freeze the display at the current snapshot. The header badge switches from `● LIVE` to `⏸ PAUSED` and all data updates stop — but navigation remains fully active. You can scroll through the frozen tree, expand and collapse subtrees, inspect threads, and study the exact state of the system at that moment. Press `p` again to resume live updates.

### 🎨 Color Coding
Colors throughout the UI carry meaning:

| Color | Meaning |
|-------|---------|
| 🟢 Green | Idle / low CPU |
| 🟡 Yellow | Moderate CPU or paused state |
| 🔴 Red | High CPU load |
| 🔵 Cyan / Blue | Process names, memory values |
| 🟣 Magenta | Threads, thread counts |
| ⬜ Muted gray | Inactive processes, tree lines |

### ⚡ Non-Blocking Architecture
Data collection runs on a dedicated background `pthread`. The render loop runs at 20 FPS on the main thread, pulling the latest snapshot atomically via a mutex. This means the UI is always responsive — even when the system has 1,000+ processes and collecting their stats takes a full second.

---

## Installation

### Requirements
- macOS 12.0 (Monterey) or later
- Apple Silicon (arm64) or Intel (x86_64)
- Swift 5.9+ / Xcode Command Line Tools (to build from source)

### Option 1: From the Distributable Package

```bash
unzip procTree-1.0.0-macos-arm64.zip
cd procTree-1.0.0-macos-arm64
./install.sh
```

The install script copies the binary to `/usr/local/bin/procTree`. You may be prompted for your password.

### Option 2: Build from Source

```bash
git clone <repo-url>
cd procTree
swift build -c release
cp .build/release/procTree /usr/local/bin/procTree
```

---

## Running

```bash
# Basic — shows your own processes and accessible system processes
procTree

# Full tree — shows all processes including launchd hierarchy and thread details
sudo procTree
```

Running with `sudo` is strongly recommended. Without it, `proc_pidinfo` will be denied access to many system processes (including PID 1 `launchd` itself), and the tree will be shown as a flat list under a synthetic `(system / orphans)` root rather than the full parent-child hierarchy.

---

## Keybindings

| Key | Action |
|-----|--------|
| `↑` / `k` | Move selection up one row |
| `↓` / `j` | Move selection down one row |
| `u` | **Jump to the top** of the list instantly |
| `d` | **Jump to the bottom** of the list instantly |
| `PageUp` | Scroll up one full page |
| `PageDown` | Scroll down one full page |
| `e` / `Enter` | Expand or collapse the selected process subtree |
| `←` | Collapse the selected process (or its thread list) |
| `→` | Expand the selected process (or its thread list) |
| `t` / `Space` | Toggle thread list for the selected process |
| `s` | Cycle sort order: **CPU%** → **MEM** → **PID** → **NAME** |
| `p` | **Pause** / resume live data updates |
| `q` / `Ctrl+C` | Quit and restore the terminal |

---

## Sort Orders

Press `s` to cycle through four sort modes. The sort applies at every level of the tree — children are sorted relative to their siblings.

| Mode | Description |
|------|-------------|
| `CPU%` | Highest CPU consumers first (default) |
| `MEM` | Highest RSS memory consumers first |
| `PID` | Ascending process ID — stable, predictable order |
| `NAME` | Alphabetical by process name |

---

## Understanding the Display

### Process Row

```
▶  26244  ● ▼ Google Chrome    12.8%  ▃▄▅▇█     1.2 GB  [██░░░░]  14 th (6 ch)
```

| Field | Description |
|-------|-------------|
| `▶` | Selection cursor |
| `26244` | Process ID (PID) |
| `●` | Activity pulse (animated when CPU > 0.5%) |
| `▼` / `▶` | Expand/collapse indicator for children or threads |
| `Google Chrome` | Process name |
| `12.8%` | Current CPU percentage |
| `▃▄▅▇█` | 10-sample sparkline CPU history |
| `1.2 GB` | RSS memory (resident set size) |
| `[██░░░░]` | Memory bar proportional to total RAM |
| `14 th` | Number of threads |
| `(6 ch)` | Number of child processes |

### Thread Row

```
     │   ⤷ Chrome_IOThread       ---               4.21s    [WAIT]
```

| Field | Description |
|-------|-------------|
| `⤷` | Thread indicator |
| `Chrome_IOThread` | Thread name (if set) |
| `---` | No per-thread CPU% (OS does not expose this via proc APIs) |
| `4.21s` | Cumulative CPU time used by this thread |
| `[WAIT]` | Thread run state |

### Thread States

| State | Meaning |
|-------|---------|
| `RUN` | Currently executing on a CPU core |
| `WAIT` | Sleeping, waiting for I/O or a lock |
| `STOP` | Suspended by a signal (e.g. `SIGSTOP`) |
| `UNINT` | Uninterruptible wait (deep kernel wait) |
| `HALT` | Halted |
| `IDLE` | Idle / not scheduled |

---

## Architecture

procTree is written entirely in Swift targeting Darwin (macOS). It has **zero Swift Package dependencies** — everything is built on top of the system frameworks that ship with macOS.

### Data Collection (`ProcessInfo.swift`, `ThreadInfo.swift`)
- **Process enumeration**: `proc_listpids(PROC_ALL_PIDS)` to get all PIDs, then `proc_pidinfo(PROC_PIDTASKALLINFO)` for each one to retrieve the process name, parent PID, RSS memory, and cumulative CPU time.
- **CPU% calculation**: Computed as the delta in cumulative CPU nanoseconds divided by the wall-clock delta between samples. Accurate to within one collection interval.
- **Thread enumeration**: `proc_pidinfo(PROC_PIDLISTTHREADS)` to get thread IDs, then `proc_pidinfo(PROC_PIDTHREADINFO)` for each thread to get its name, run state, priority, and CPU time.
- **System stats**: `host_statistics64(HOST_VM_INFO64)` for RAM breakdown (active + wired + compressed + speculative pages), `host_statistics(HOST_CPU_LOAD_INFO)` for system-wide CPU tick deltas, and `sysctl(HW_MEMSIZE)` for total physical RAM.

### Tree Building (`ProcessInfo.swift`)
The flat list of processes is assembled into a tree by building a `childrenMap: [pid_t: [pid_t]]` in a single pass, then recursively assembling nodes starting from PID 1. Processes whose parents are not visible (e.g. kernel tasks, or processes inaccessible without `sudo`) are collected as orphans under a synthetic PID 0 root node.

### Rendering (`TreeRenderer.swift`)
The renderer is a pure string-building function — it takes the current `AppState` and `SystemStats` and produces a single UTF-8 string containing the complete frame with all ANSI escape codes embedded. This string is written to `STDOUT_FILENO` in one `write()` call per frame to minimize flicker. Each line is padded to exactly `cols` characters wide so stale content from a previous frame is always overwritten.

All ANSI color values are computed as `static var` (not `static let`) to avoid Swift's `dispatch_once` lazy initializer, which would deadlock in a release binary that hasn't loaded the Objective-C runtime.

### Terminal Handling (`Terminal.swift`)
The terminal is controlled by opening `/dev/tty` directly with `O_RDWR | O_NOCTTY | O_NONBLOCK`. This ensures correct operation under `sudo`, where `stdin` and `stdout` may be redirected. Raw mode is set via `tcsetattr` — disabling canonical mode, echo, and signal generation, while leaving `OPOST` enabled so that escape sequences are processed correctly by the terminal emulator. The alternate screen buffer (`\e[?1049h`) is used so the terminal is fully restored on exit.

### Concurrency (`main.swift`)
A single background `pthread` runs the data collection loop. It collects, builds the tree, and writes results into shared variables protected by a `pthread_mutex_t`. The main thread renders frames at ~20 FPS, acquiring the lock briefly to snapshot the latest data. The collector sleeps in 50ms increments between passes so it can respond promptly to the `isRunning = false` signal on quit.

---

## Packaging

The included `package.sh` script builds a release binary, strips debug symbols, and produces a versioned zip archive ready for distribution:

```bash
./package.sh           # auto-version from git tag, or 1.0.0 fallback
./package.sh 1.2.0     # explicit version override
```

Output:
```
dist/
└── procTree-1.0.0-macos-arm64.zip
    ├── procTree       ← stripped release binary
    ├── README.md
    └── install.sh     ← one-command installer
```

Tag a release and the version is picked up automatically:
```bash
git tag v1.1.0
./package.sh
# → dist/procTree-1.1.0-macos-arm64.zip
```

---

## Known Limitations

- **Thread CPU%** is not shown per-thread. The Darwin `proc_pidinfo(PROC_PIDTHREADINFO)` API exposes cumulative CPU time but not a live percentage. Per-thread CPU% would require two samples with a time delta, which is not currently implemented.
- **Process arguments** (the full command line, e.g. `python3 myscript.py`) are not shown — only the process name from `pbi_name`. Full argv retrieval via `PROC_PIDPATHINFO` is possible but adds significant overhead.
- **Linux is not supported.** The data collection layer has stub stubs for `#elseif os(Linux)` but they return placeholder data. A real Linux backend would use `/proc/<pid>/stat` and `/proc/<pid>/task/` instead of the Darwin APIs.
- **Intel (x86_64) builds** require building from source on an Intel Mac or using a Universal binary. The distributed package targets `arm64` (Apple Silicon) only.

---

## License

MIT License. Do whatever you like with it.

---

*From the minds of **Bob & Daneyand***.
