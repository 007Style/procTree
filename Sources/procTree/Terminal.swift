#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif os(Windows)
import WinSDK
#endif

public enum Key {
    case char(Character)
    case up
    case down
    case left
    case right
    case pageUp
    case pageDown
    case home
    case end
    case enter
    case space
    case tab
    case backspace
    case escape
    case resize
    case unknown
}

public final class Terminal {
    public static let shared = Terminal()

    #if canImport(Darwin) || canImport(Glibc)
    private var originalTermios = termios()
    // /dev/tty gives us the real controlling TTY regardless of sudo stdin/stdout redirects
    private var ttyFd: Int32 = -1
    #endif
    private var isRaw = false

    public struct Size {
        public var rows: Int
        public var cols: Int

        public init(rows: Int = 24, cols: Int = 80) {
            self.rows = rows
            self.cols = cols
        }
    }

    private init() {
        #if canImport(Darwin) || canImport(Glibc)
        // Open /dev/tty non-blocking so it never hangs when there's no controlling terminal.
        // O_NOCTTY: don't make this process the session leader.
        ttyFd = Darwin.open("/dev/tty", O_RDWR | O_NOCTTY | O_NONBLOCK)
        if ttyFd >= 0 {
            // Restore blocking mode — we control read timeouts via VTIME in termios
            let fl = fcntl(ttyFd, F_GETFL, 0)
            _ = fcntl(ttyFd, F_SETFL, fl & ~O_NONBLOCK)
        } else {
            // Fallback when no controlling terminal (e.g. piped)
            if isatty(STDIN_FILENO) != 0 { ttyFd = STDIN_FILENO }
            else if isatty(STDOUT_FILENO) != 0 { ttyFd = STDOUT_FILENO }
        }
        #endif
    }

    public func enableRawMode() {
        guard !isRaw else { return }
        #if canImport(Darwin) || canImport(Glibc)
        guard ttyFd >= 0 else { return }
        tcgetattr(ttyFd, &originalTermios)
        var raw = originalTermios
        // Disable echo, canonical mode, extended processing, signals
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON | IEXTEN | ISIG)
        // Disable flow control, CR→NL translation, misc input flags
        raw.c_iflag &= ~tcflag_t(IXON | ICRNL | BRKINT | INPCK | ISTRIP)
        // Do NOT disable OPOST — we need output processing for escape sequences
        // to work correctly in all terminal emulators. We write \r\n explicitly.
        raw.c_cflag |= tcflag_t(CS8)
        // VMIN=0, VTIME=1: non-blocking with 0.1s timeout
        func setCC(_ cc: inout (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                                UInt8,UInt8,UInt8,UInt8), idx: Int, val: UInt8) {
            switch idx {
            case 16: cc.16 = val
            case 17: cc.17 = val
            default: break
            }
        }
        setCC(&raw.c_cc, idx: Int(VMIN),  val: 0)
        setCC(&raw.c_cc, idx: Int(VTIME), val: 1)
        tcsetattr(ttyFd, TCSAFLUSH, &raw)
        // Non-blocking reads
        let flags = fcntl(ttyFd, F_GETFL, 0)
        _ = fcntl(ttyFd, F_SETFL, flags | O_NONBLOCK)
        #endif
        isRaw = true

        // Switch to alternate screen, hide cursor, clear screen
        writeRaw("\u{1b}[?1049h\u{1b}[?25l\u{1b}[2J\u{1b}[H")
    }

    public func disableRawMode() {
        guard isRaw else { return }
        // Restore cursor and main screen buffer
        writeRaw("\u{1b}[?25h\u{1b}[?1049l")
        #if canImport(Darwin) || canImport(Glibc)
        if ttyFd >= 0 {
            let flags = fcntl(ttyFd, F_GETFL, 0)
            _ = fcntl(ttyFd, F_SETFL, flags & ~O_NONBLOCK)
            tcsetattr(ttyFd, TCSAFLUSH, &originalTermios)
        }
        #endif
        isRaw = false
    }

    deinit {
        disableRawMode()
        #if canImport(Darwin) || canImport(Glibc)
        // Close /dev/tty if we opened it ourselves
        if ttyFd >= 0 && ttyFd != STDIN_FILENO && ttyFd != STDOUT_FILENO {
            Darwin.close(ttyFd)
        }
        #endif
    }

    public func getWindowSize() -> Size {
        #if canImport(Darwin) || canImport(Glibc)
        var w = winsize()
        let fd = ttyFd >= 0 ? ttyFd : STDOUT_FILENO
        if ioctl(fd, UInt(TIOCGWINSZ), &w) == 0 && w.ws_col > 0 && w.ws_row > 0 {
            return Size(rows: Int(w.ws_row), cols: Int(w.ws_col))
        }
        #endif
        return Size(rows: 24, cols: 80)
    }

    public func writeRaw(_ str: String) {
        var utf8 = Array(str.utf8)
        utf8.withUnsafeMutableBufferPointer { ptr in
            guard let base = ptr.baseAddress, ptr.count > 0 else { return }
            var remaining = ptr.count
            var offset = 0
            while remaining > 0 {
                #if canImport(Darwin) || canImport(Glibc)
                let n = Darwin.write(STDOUT_FILENO, base + offset, remaining)
                #else
                let n = fwrite(base + offset, 1, remaining, stdout)
                #endif
                if n <= 0 { break }
                offset += n
                remaining -= n
            }
        }
    }

    public func readKey() -> Key? {
        var buf = [UInt8](repeating: 0, count: 16)
        guard ttyFd >= 0 else { return nil }
        #if canImport(Darwin) || canImport(Glibc)
        let bytesRead = Darwin.read(ttyFd, &buf, buf.count)
        #else
        let bytesRead = fread(&buf, 1, buf.count, stdin)
        #endif
        guard bytesRead > 0 else { return nil }

        if buf[0] == 27 { // ESC
            if bytesRead == 1 {
                return .escape
            }
            if buf[1] == UInt8(ascii: "[") {
                if bytesRead >= 3 {
                    switch buf[2] {
                    case UInt8(ascii: "A"): return .up
                    case UInt8(ascii: "B"): return .down
                    case UInt8(ascii: "C"): return .right
                    case UInt8(ascii: "D"): return .left
                    case UInt8(ascii: "H"): return .home
                    case UInt8(ascii: "F"): return .end
                    case UInt8(ascii: "5"):
                        if bytesRead >= 4 && buf[3] == UInt8(ascii: "~") { return .pageUp }
                    case UInt8(ascii: "6"):
                        if bytesRead >= 4 && buf[3] == UInt8(ascii: "~") { return .pageDown }
                    case UInt8(ascii: "1"), UInt8(ascii: "7"):
                        if bytesRead >= 4 && buf[3] == UInt8(ascii: "~") { return .home }
                    case UInt8(ascii: "4"), UInt8(ascii: "8"):
                        if bytesRead >= 4 && buf[3] == UInt8(ascii: "~") { return .end }
                    default: break
                    }
                }
            } else if buf[1] == UInt8(ascii: "O") {
                if bytesRead >= 3 {
                    switch buf[2] {
                    case UInt8(ascii: "H"): return .home
                    case UInt8(ascii: "F"): return .end
                    default: break
                    }
                }
            }
            return .escape
        }

        switch buf[0] {
        case 10, 13: return .enter
        case 32: return .space
        case 9: return .tab
        case 127, 8: return .backspace
        case 3: // Ctrl-C
            return .char("q")
        default:
            let scalar = UnicodeScalar(buf[0])
            return .char(Character(scalar))
        }
    }
}

public enum ANSI {
    public static let reset = "\u{1b}[0m"
    public static let bold = "\u{1b}[1m"
    public static let dim = "\u{1b}[2m"
    public static let italic = "\u{1b}[3m"
    public static let underline = "\u{1b}[4m"
    public static let blink = "\u{1b}[5m"
    public static let reverse = "\u{1b}[7m"

    public static let clearScreen = "\u{1b}[2J"
    public static let clearLine = "\u{1b}[2K"
    public static let cursorHome = "\u{1b}[H"

    public static func moveTo(row: Int, col: Int) -> String {
        return "\u{1b}[\(row);\(col)H"
    }

    public static func fgRGB(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> String {
        return "\u{1b}[38;2;\(r);\(g);\(b)m"
    }

    public static func bgRGB(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> String {
        return "\u{1b}[48;2;\(r);\(g);\(b)m"
    }

    public static func fg256(_ code: UInt8) -> String {
        return "\u{1b}[38;5;\(code)m"
    }

    public static func bg256(_ code: UInt8) -> String {
        return "\u{1b}[48;5;\(code)m"
    }

    // Palette colors — use `var` (computed) to avoid dispatch_once in release builds
    public static var cyan:        String { fgRGB(80, 210, 240) }
    public static var brightBlue:  String { fgRGB(100, 160, 255) }
    public static var green:       String { fgRGB(100, 220, 120) }
    public static var yellow:      String { fgRGB(245, 205, 80) }
    public static var orange:      String { fgRGB(255, 140, 50) }
    public static var red:         String { fgRGB(255, 85, 85) }
    public static var magenta:     String { fgRGB(215, 120, 240) }
    public static var purple:      String { fgRGB(160, 120, 230) }
    public static var muted:       String { fgRGB(130, 140, 155) }
    public static var dimMuted:    String { fgRGB(90, 100, 115) }
    public static var darkGray:    String { fgRGB(60, 65, 75) }
    public static var white:       String { fgRGB(240, 242, 245) }
    public static var black:       String { fgRGB(18, 20, 24) }

    // Selection styles
    public static var selectionBg: String { bgRGB(45, 55, 75) }
    public static var headerBg:    String { bgRGB(28, 32, 42) }
    public static var statusBarBg: String { bgRGB(22, 26, 35) }
}
