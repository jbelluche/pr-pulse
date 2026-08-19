import Foundation

struct SnapshotCache: Sendable {
    let fileURL: URL

    static var live: SnapshotCache {
        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        return SnapshotCache(
            fileURL: supportDirectory
                .appendingPathComponent("PRPulse", isDirectory: true)
                .appendingPathComponent("leaderboard.json")
        )
    }

    func loadCurrentMonth(
        repository: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> LeaderboardSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(
            LeaderboardSnapshot.self,
            from: Data(contentsOf: fileURL)
        )
        guard isCurrentMonth(
            snapshot,
            repository: repository,
            now: now,
            calendar: calendar
        ) else {
            return nil
        }
        return snapshot
    }

    func isCurrentMonth(
        _ snapshot: LeaderboardSnapshot,
        repository: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        snapshot.metricVersion == LeaderboardSnapshot.currentMetricVersion
            && snapshot.repository.caseInsensitiveCompare(repository) == .orderedSame
            && calendar.isDate(snapshot.periodStart, equalTo: now, toGranularity: .month)
    }

    func lastRepository() -> String? {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let cached = try? JSONDecoder().decode(CachedRepository.self, from: data)
        else {
            return nil
        }
        return cached.repository
    }

    func save(_ snapshot: LeaderboardSnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }
}

private struct CachedRepository: Decodable {
    let repository: String
}
