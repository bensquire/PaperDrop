import Foundation

/// Where a saved document lands: a safe file name, never overwriting.
public enum Archive {
    /// Title for an unnamed document, in the macOS screenshot style
    /// ("Scan 2026-10-04 at 08.45.12"): sortable, and free of the colon
    /// Finder would show as a slash.
    public static func defaultTitle(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Scan " + f.string(from: date)
    }

    /// A title made safe as a file name: "/" and ":" (the path separators
    /// of POSIX and Finder) become "-", and leading dots, which would hide
    /// the file, are dropped.
    public static func fileName(for title: String) -> String {
        var name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        while name.hasPrefix(".") {
            name.removeFirst()
        }
        return name
    }

    /// The first of "title.pdf", "title 2.pdf", … not already in `dir`.
    /// A title that is empty once made safe is named for `untitledDate`.
    public static func destination(for title: String, in dir: URL, untitledDate: Date) -> URL {
        let name = fileName(for: title)
        let base = name.isEmpty ? defaultTitle(for: untitledDate) : name
        var candidate = dir.appendingPathComponent(base + ".pdf")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base) \(n).pdf")
            n += 1
        }
        return candidate
    }
}
