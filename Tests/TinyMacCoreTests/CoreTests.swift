import XCTest
@testable import TinyMacCore

final class CoreTests: XCTestCase {
    /// A .rec is a bare array of 20-byte little-endian EVENTMSG records.
    func testRecordingBytesMatchTinyTaskLayout() {
        let c = TinyMacController()
        c.replaceRecording([
            EventMsg(message: 0x200, paramL: 640, paramH: 400, time: 1000, hwnd: 7),
            EventMsg(message: 0x100, paramL: 0x1E41, paramH: 0x1E, time: 1010, hwnd: 7),
        ])
        let expected: [UInt8] = [
            0x00, 0x02, 0, 0, 0x80, 0x02, 0, 0, 0x90, 0x01, 0, 0, 0xE8, 0x03, 0, 0, 7, 0, 0, 0,
            0x00, 0x01, 0, 0, 0x41, 0x1E, 0, 0, 0x1E, 0, 0, 0, 0xF2, 0x03, 0, 0, 7, 0, 0, 0,
        ]
        XCTAssertEqual([UInt8](c.recordingData()), expected)
        XCTAssertEqual(c.records.count, 2)
    }

    func testRecordsStopAtFirstZeroRecord() {
        let c = TinyMacController()
        c.replaceRecording([EventMsg(message: 0x200, time: 1), EventMsg(), EventMsg(message: 0x200, time: 2)])
        XCTAssertEqual(c.records.count, 1)
    }

    func testAppendRecordOnlyWhileRecording() {
        let c = TinyMacController()
        c.appendRecord(EventMsg(message: 0x20A))
        XCTAssertNil(c.buffer)
        c.state = TinyMacController.cmdRecord
        c.appendRecord(EventMsg(message: 0x20A, time: 5))
        XCTAssertEqual(c.index, 1)
        XCTAssertEqual(c.records.first?.message, 0x20A)
    }

    func testAtoiLikeMatchesC() {
        XCTAssertEqual(atoiLike("  42abc"), 42)
        XCTAssertEqual(atoiLike("-7"), -7)
        XCTAssertEqual(atoiLike("x1"), 0)
        XCTAssertEqual(atoiLike("99999999999"), Int(Int32.max))
    }

    func testIniKeepsOtherSectionsAndUsesCRLF() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ini")
        defer { try? FileManager.default.removeItem(at: url) }
        let ini = IniFile(url: url)
        ini.write("TinyTask", "speed", 2)
        ini.write("TinyMacPlus", "show_hud", 1)
        ini.write("TinyTask", "topmost", 1)
        ini.write("TinyTask", "speed", 100)
        XCTAssertEqual(ini.int("TinyTask", "speed", default: 0), 100)
        XCTAssertEqual(ini.int("TinyMacPlus", "show_hud", default: 0), 1)
        XCTAssertEqual(ini.int("TinyTask", "missing", default: 8), 8)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(text, "[TinyTask]\r\nspeed=100\r\ntopmost=1\r\n[TinyMacPlus]\r\nshow_hud=1\r\n")
    }

    func testEveryLetterAndDigitHasAMacKey() {
        for vk in Array(0x30...0x39) + Array(0x41...0x5A) {
            XCTAssertNotNil(VK.toMac[vk]?.first, String(format: "VK 0x%02X", vk))
            XCTAssertNotEqual(VK.mapVirtualKey(vk), 0)
        }
    }
}
