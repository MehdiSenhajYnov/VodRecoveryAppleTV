import Foundation

enum Format {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEE d MMM · HH:mm"
        return f
    }()

    private static let longDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d MMMM yyyy 'à' HH:mm"
        return f
    }()

    static func date(_ date: Date) -> String {
        dateFormatter.string(from: date).capitalizedFirst
    }

    static func longDate(_ date: Date) -> String {
        longDateFormatter.string(from: date).capitalizedFirst
    }

    static func duration(_ seconds: TimeInterval?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        return h > 0 ? "\(h) h \(String(format: "%02d", m))" : "\(m) min"
    }

    static func relative(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        switch days {
        case ..<1: return "Aujourd'hui"
        case 1: return "Hier"
        default: return "Il y a \(days) jours"
        }
    }

    static func number(_ value: Int) -> String {
        value.formatted(.number.locale(Locale(identifier: "fr_FR")))
    }
}

extension String {
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }

    /// "https://twitch.tv/Name", "@Name", " name " → "name"
    var normalizedChannel: String {
        var value = trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let range = value.range(of: "twitch.tv/") { value = String(value[range.upperBound...]) }
        value = value.split(separator: "/").first.map(String.init) ?? value
        value = value.replacingOccurrences(of: "@", with: "").replacingOccurrences(of: " ", with: "")
        return value.filter { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}
