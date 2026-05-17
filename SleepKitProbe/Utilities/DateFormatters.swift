import Foundation

enum DateFormatters {
    static let iso8601: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        return formatter
    }()

    static let display: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()

    static func isoString(_ date: Date?) -> String {
        guard let date else { return "" }
        return iso8601.string(from: date)
    }

    static func displayString(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return display.string(from: date)
    }
}
