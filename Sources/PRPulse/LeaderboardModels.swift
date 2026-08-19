import Foundation

struct Contributor: Codable, Equatable, Identifiable, Sendable {
    let login: String
    let avatarURL: URL?
    let mergedCount: Int
    let openCount: Int

    var id: String { login.lowercased() }

    init(login: String, avatarURL: URL?, mergedCount: Int, openCount: Int = 0) {
        self.login = login
        self.avatarURL = avatarURL
        self.mergedCount = mergedCount
        self.openCount = openCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        login = try container.decode(String.self, forKey: .login)
        avatarURL = try container.decodeIfPresent(URL.self, forKey: .avatarURL)
        mergedCount = try container.decode(Int.self, forKey: .mergedCount)
        openCount = try container.decodeIfPresent(Int.self, forKey: .openCount) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case login
        case avatarURL
        case mergedCount
        case openCount
    }
}

struct LeaderboardSnapshot: Codable, Equatable, Sendable {
    static let currentMetricVersion = 2

    let metricVersion: Int?
    let repository: String
    let periodStart: Date
    let periodEnd: Date
    let fetchedAt: Date
    let totalCount: Int
    let contributors: [Contributor]
}

struct MonthWindow: Equatable, Sendable {
    let start: Date
    let end: Date

    init(containing date: Date, calendar: Calendar = .current) {
        start = calendar.dateInterval(of: .month, for: date)?.start ?? date
        end = date
    }

    var queryStart: String {
        ISO8601DateFormatter.string(
            from: start,
            timeZone: TimeZone(secondsFromGMT: 0)!,
            formatOptions: [.withInternetDateTime]
        )
    }

    var monthName: String {
        start.formatted(.dateTime.month(.wide))
    }
}

enum GitHubSearchParser {
    enum ParseError: LocalizedError, Equatable {
        case incompleteResults(expected: Int, received: Int)
        case resultsFlaggedIncomplete

        var errorDescription: String? {
            switch self {
            case let .incompleteResults(expected, received):
                "GitHub returned only \(received) of \(expected) matching pull requests."
            case .resultsFlaggedIncomplete:
                "GitHub marked the pull request search results as incomplete."
            }
        }
    }

    static func snapshot(
        from data: Data,
        openPullRequestsData: Data? = nil,
        repository: String,
        window: MonthWindow,
        fetchedAt: Date = Date()
    ) throws -> LeaderboardSnapshot {
        let mergedItems = try completeItems(from: data)
        let openItems: [SearchItem]
        if let openPullRequestsData {
            openItems = try completeItems(from: openPullRequestsData)
        } else {
            openItems = []
        }
        let openCounts = Dictionary(grouping: openItems) { item in
            item.user?.login?.lowercased() ?? "ghost"
        }.mapValues(\.count)
        var byLogin: [String: MutableContributor] = [:]

        for item in mergedItems {
            let displayLogin = item.user?.login.flatMap { $0.isEmpty ? nil : $0 } ?? "ghost"
            let key = displayLogin.lowercased()
            var contributor = byLogin[key] ?? MutableContributor(
                login: displayLogin,
                avatarURL: item.user?.avatarURL,
                mergedCount: 0
            )
            contributor.mergedCount += 1
            byLogin[key] = contributor
        }

        let contributors = byLogin.values
            .map {
                Contributor(
                    login: $0.login,
                    avatarURL: $0.avatarURL,
                    mergedCount: $0.mergedCount,
                    openCount: openCounts[$0.login.lowercased()] ?? 0
                )
            }
            .sorted {
                if $0.mergedCount != $1.mergedCount {
                    return $0.mergedCount > $1.mergedCount
                }
                return $0.login.localizedCaseInsensitiveCompare($1.login) == .orderedAscending
            }

        return LeaderboardSnapshot(
            metricVersion: LeaderboardSnapshot.currentMetricVersion,
            repository: repository,
            periodStart: window.start,
            periodEnd: window.end,
            fetchedAt: fetchedAt,
            totalCount: mergedItems.count,
            contributors: contributors
        )
    }
}

private extension GitHubSearchParser {
    static func completeItems(from data: Data) throws -> [SearchItem] {
        let decoder = JSONDecoder()
        let pages = try decoder.decode([SearchPage].self, from: data)

        guard !pages.contains(where: { $0.incompleteResults == true }) else {
            throw ParseError.resultsFlaggedIncomplete
        }

        var seenNumbers = Set<Int>()
        let items = pages
            .flatMap(\.items)
            .filter { seenNumbers.insert($0.number).inserted }
        let advertisedTotal = pages.first?.totalCount ?? items.count
        guard advertisedTotal <= items.count else {
            throw ParseError.incompleteResults(
                expected: advertisedTotal,
                received: items.count
            )
        }
        return items
    }

    struct SearchPage: Decodable {
        let totalCount: Int
        let incompleteResults: Bool?
        let items: [SearchItem]

        enum CodingKeys: String, CodingKey {
            case totalCount = "total_count"
            case incompleteResults = "incomplete_results"
            case items
        }
    }

    struct SearchItem: Decodable {
        let number: Int
        let user: SearchUser?
    }

    struct SearchUser: Decodable {
        let login: String?
        let avatarURL: URL?

        enum CodingKeys: String, CodingKey {
            case login
            case avatarURL = "avatar_url"
        }
    }

    struct MutableContributor {
        let login: String
        let avatarURL: URL?
        var mergedCount: Int
    }
}
