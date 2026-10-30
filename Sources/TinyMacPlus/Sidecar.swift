import Foundation

/// Per-recording settings stored next to a .rec file as "<name>.rec.tinymac" (JSON).
/// TinyTask ignores the file, so the .rec itself stays a plain TinyTask recording.
struct Sidecar: Codable {
    var version = 1
    var speed: Int?
    var loops: Int?
    var continuous: Bool?
    var screenWidth: Double?    // main display size, in points, when recorded
    var screenHeight: Double?

    static func url(for recording: String) -> URL {
        URL(fileURLWithPath: recording + ".tinymac")
    }

    static func load(for recording: String) -> Sidecar? {
        guard let data = try? Data(contentsOf: url(for: recording)) else { return nil }
        return try? JSONDecoder().decode(Sidecar.self, from: data)
    }

    func save(for recording: String) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(self).write(to: Self.url(for: recording))
    }

    var screenSize: CGSize? {
        guard let w = screenWidth, let h = screenHeight, w > 0, h > 0 else { return nil }
        return CGSize(width: w, height: h)
    }
}
