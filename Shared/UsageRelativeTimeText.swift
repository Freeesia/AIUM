import Foundation

enum UsageRelativeTimeText {
    static func reset(at resetAt: Date, relativeTo referenceDate: Date, locale: Locale = .autoupdatingCurrent) -> String {
        let interval = resetAt.timeIntervalSince(referenceDate)
        let roundedMinutes = interval >= 0
            ? ceil(interval / 60)
            : floor(interval / 60)
        let roundedDate = referenceDate.addingTimeInterval(roundedMinutes * 60)
        return format(roundedDate, relativeTo: referenceDate, locale: locale)
    }

    static func fetched(at fetchedAt: Date, relativeTo referenceDate: Date, locale: Locale = .autoupdatingCurrent) -> String {
        let elapsedMinutes = max(0, floor(referenceDate.timeIntervalSince(fetchedAt) / 60))
        let roundedDate = referenceDate.addingTimeInterval(-elapsedMinutes * 60)
        return format(roundedDate, relativeTo: referenceDate, locale: locale)
    }

    private static func format(_ date: Date, relativeTo referenceDate: Date, locale: Locale) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .abbreviated
        formatter.dateTimeStyle = date == referenceDate ? .named : .numeric
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }
}
