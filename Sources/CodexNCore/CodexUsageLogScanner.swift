import Foundation

struct CodexUsageLogScanner {
    func scanUsageFile(_ file: URL, date: Date, calendar: Calendar) throws -> CodexUsageTotals {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        var totals = CodexUsageTotals()
        var previousCumulative: CodexUsageTotals?

        var pending = Data()
        while let chunk = try handle.read(upToCount: Self.scanChunkSize), !chunk.isEmpty {
            pending.append(chunk)
            var lineStart = pending.startIndex
            while let newlineIndex = pending[lineStart...].firstIndex(of: UInt8(ascii: "\n")) {
                scanUsageLine(
                    Data(pending[lineStart..<newlineIndex]),
                    date: date,
                    calendar: calendar,
                    totals: &totals,
                    previousCumulative: &previousCumulative
                )
                lineStart = pending.index(after: newlineIndex)
            }
            pending.removeSubrange(pending.startIndex..<lineStart)
        }

        if !pending.isEmpty {
            scanUsageLine(
                pending,
                date: date,
                calendar: calendar,
                totals: &totals,
                previousCumulative: &previousCumulative
            )
        }

        return totals
    }

    private func scanUsageLine(
        _ line: Data,
        date: Date,
        calendar: Calendar,
        totals: inout CodexUsageTotals,
        previousCumulative: inout CodexUsageTotals?
    ) {
        guard line.range(of: Self.tokenCountNeedle) != nil else { return }
        guard let event = Self.parseTokenEvent(line) else { return }
        if let cumulative = event.cumulative {
            defer { previousCumulative = cumulative }
            guard calendar.isDate(event.timestamp, inSameDayAs: date) else { return }
            totals.add(event.delta ?? cumulative.subtracting(previousCumulative))
        } else if let delta = event.delta, calendar.isDate(event.timestamp, inSameDayAs: date) {
            totals.add(delta)
        }
    }

    private static func parseTokenEvent(_ data: Data) -> CodexUsageEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "event_msg",
              let timestamp = parseTimestamp(object["timestamp"]),
              let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any]
        else {
            return nil
        }

        let delta = (info["last_token_usage"] as? [String: Any]).map(CodexUsageTotals.init(raw:))
        let cumulative = (info["total_token_usage"] as? [String: Any]).map(CodexUsageTotals.init(raw:))
        guard delta != nil || cumulative != nil else { return nil }
        return CodexUsageEvent(timestamp: timestamp, delta: delta, cumulative: cumulative)
    }

    private static func parseTimestamp(_ value: Any?) -> Date? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let date = CodexUsageDateParser.date(from: trimmed, fractionalSeconds: true) {
                return date
            }
            return CodexUsageDateParser.date(from: trimmed, fractionalSeconds: false)
        }
        if let number = value as? NSNumber {
            let raw = number.doubleValue
            let seconds = raw > 1_000_000_000_000 ? raw / 1_000 : raw
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }

    private static let tokenCountNeedle = Data(#""token_count""#.utf8)
    private static let scanChunkSize = 64 * 1024
}

private struct CodexUsageEvent {
    let timestamp: Date
    let delta: CodexUsageTotals?
    let cumulative: CodexUsageTotals?
}

private enum CodexUsageDateParser {
    static func date(from string: String, fractionalSeconds: Bool) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
