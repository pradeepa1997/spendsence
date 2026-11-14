import Foundation

enum DateParsing {
    /// Parses a template-captured date. Never returns nil: falls back to `receivedAt` when parsing fails or the
    /// result is implausible (more than a day in the future or over ~13 months in the past, which usually means
    /// a dd/MM vs MM/dd mix-up).
    ///
    /// Date-only formats get the time of day from `receivedAt`, so two purchases on the same day are not both
    /// stamped at midnight (which would break the ±3 minute dedup window).
    static func parse(_ string: String, format: String, receivedAt: Date, timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        let input = format.contains("MMM") ? capitalizeWords(string) : string
        guard let parsed = formatter.date(from: input) else { return receivedAt }

        var result = parsed
        if !format.contains("H"), !format.contains("h") {
            let time = calendar.dateComponents([.hour, .minute, .second], from: receivedAt)
            result = calendar.date(
                bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: parsed
            ) ?? parsed
        }

        let earliest = receivedAt.addingTimeInterval(-400 * 86_400)
        let latest = receivedAt.addingTimeInterval(86_400)
        guard result >= earliest, result <= latest else { return receivedAt }
        return result
    }

    private static let monthWord = CompiledRegex("[A-Za-z]{3,}")

    /// `14/NOV/2026` → `14/Nov/2026`, so month names parse whatever case the bank uses. AM/PM is left alone.
    static func capitalizeWords(_ string: String) -> String {
        var result = string
        for match in monthWord.matches(in: string).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: String(result[range]).capitalized)
        }
        return result
    }
}
