import AppKit
import TinyMacCore

/// Listen-only event tap used by the Plus extras.
///
/// TinyTask's recorder polls key and button states, which cannot see the scroll
/// wheel; this tap adds scroll events to the recording. It also notices real
/// (not synthesised) mouse movement and Esc presses during playback, to stop it.
final class InputWatcher {
    var onScroll: ((_ dy: Int32, _ dx: Int32) -> Void)?
    var onUserMouseMove: ((_ distance: Double) -> Void)?
    var onUserKeyDown: ((_ keyCode: Int64) -> Void)?

    private var tap: CFMachPort?
    private let ownPID = Int64(getpid())

    /// Starts the tap. Fails without the Input Monitoring permission.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.scrollWheel, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .keyDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                           eventsOfInterest: mask, callback: { _, type, event, refcon in
            if let refcon {
                Unmanaged<InputWatcher>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: refcon) else { return false }
        tap = port
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        // Events TinyMac posts itself carry its process id; hardware events carry 0.
        guard event.getIntegerValueField(.eventSourceUnixProcessID) != ownPID else { return }
        if type == .keyDown {
            onUserKeyDown?(event.getIntegerValueField(.keyboardEventKeycode))
        } else if type == .scrollWheel {
            let dy = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            let dx = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
            if dy != 0 || dx != 0 { onScroll?(Int32(clamping: dy), Int32(clamping: dx)) }
        } else {
            let dx = Double(event.getIntegerValueField(.mouseEventDeltaX))
            let dy = Double(event.getIntegerValueField(.mouseEventDeltaY))
            onUserMouseMove?((dx * dx + dy * dy).squareRoot())
        }
    }
}

/// Replays scroll records (WM_MOUSEWHEEL, 0x20A) written by TinyMac Plus.
enum ScrollRecord {
    static let message: UInt32 = 0x20A
    private static let source = CGEventSource(stateID: .hidSystemState)

    /// paramL = cursor x, paramH = vertical delta in the high word, horizontal in the low word (pixels).
    static func make(dy: Int32, dx: Int32, at p: CGPoint, time: UInt32, hwnd: UInt32) -> EventMsg {
        let hi = UInt32(UInt16(bitPattern: Int16(clamping: dy))) << 16
        let lo = UInt32(UInt16(bitPattern: Int16(clamping: dx)))
        return EventMsg(message: message, paramL: UInt32(bitPattern: Int32(clamping: Int(p.x))),
                        paramH: hi | lo, time: time, hwnd: hwnd)
    }

    static func deltas(_ r: EventMsg) -> (dy: Int32, dx: Int32) {
        (Int32(Int16(bitPattern: UInt16(r.paramH >> 16))), Int32(Int16(bitPattern: UInt16(r.paramH & 0xFFFF))))
    }

    static func play(_ r: EventMsg) {
        let (dy, dx) = deltas(r)
        CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)?
            .post(tap: .cghidEventTap)
    }
}
