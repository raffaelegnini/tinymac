import Foundation

/// Minimal GetPrivateProfileInt / GetPrivateProfileString / WritePrivateProfileString.
///
/// The original keeps its settings in "<exe name>.ini" next to the executable,
/// section [TinyTask]. An .app bundle must not be written to, so the port keeps
/// the identical file in ~/Library/Application Support/TinyMac/TinyMac.ini.
final class IniFile {
    let url: URL

    init(url: URL) { self.url = url }

    static var standard: IniFile {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TinyMac", isDirectory: true)
        return IniFile(url: dir.appendingPathComponent("TinyMac.ini"))
    }

    private func readLines() -> [String] {
        guard let s = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else { return [] }
        return s.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    func string(_ section: String, _ key: String, default def: String) -> String {
        var inSection = false
        for raw in readLines() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") && line.hasSuffix("]") {
                inSection = line.dropFirst().dropLast().caseInsensitiveCompare(section) == .orderedSame
                continue
            }
            guard inSection, let eq = line.firstIndex(of: "=") else { continue }
            if line[..<eq].trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(key) == .orderedSame {
                return line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            }
        }
        return def
    }

    func int(_ section: String, _ key: String, default def: Int) -> Int {
        let s = string(section, key, default: "\u{0}")
        if s == "\u{0}" { return def }
        return atoiLike(s)
    }

    func write(_ section: String, _ key: String, _ value: String?) {
        var lines = readLines()
        while lines.last == "" { lines.removeLast() }
        var sectionStart: Int?
        var sectionEnd = lines.count
        for (i, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") && line.hasSuffix("]") {
                if sectionStart != nil { sectionEnd = i; break }
                if line.dropFirst().dropLast().caseInsensitiveCompare(section) == .orderedSame { sectionStart = i }
            }
        }
        if sectionStart == nil {
            if value == nil { return }
            lines.append("[\(section)]")
            sectionStart = lines.count - 1
            sectionEnd = lines.count
        }
        var replaced = false
        var i = sectionStart! + 1
        while i < sectionEnd {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if let eq = line.firstIndex(of: "="),
               line[..<eq].trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(key) == .orderedSame {
                if let value { lines[i] = "\(key)=\(value)"; replaced = true; i += 1 } else { lines.remove(at: i); sectionEnd -= 1 }
                continue
            }
            i += 1
        }
        if !replaced, let value { lines.insert("\(key)=\(value)", at: sectionEnd) }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? (lines.joined(separator: "\r\n") + "\r\n").write(to: url, atomically: true, encoding: .utf8)
    }

    func write(_ section: String, _ key: String, _ value: Int) { write(section, key, String(value)) }
}

/// C atoi(): optional whitespace, optional sign, leading digits, 0 if none.
func atoiLike(_ s: String) -> Int {
    var it = s.drop(while: { $0 == " " || $0 == "\t" })
    var sign = 1
    if let f = it.first, f == "-" || f == "+" { sign = f == "-" ? -1 : 1; it = it.dropFirst() }
    var v = 0
    for c in it {
        guard let d = c.wholeNumberValue, c.isASCII else { break }
        v = v &* 10 &+ d
        if v > Int(Int32.max) { v = Int(Int32.max); break }
    }
    return sign * v
}
