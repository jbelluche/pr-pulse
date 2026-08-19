import Foundation

struct DemoLeaderboardConfiguration: Sendable {
    let selectedRepository: String
    let repositories: [RepositoryOption]
    let snapshots: [LeaderboardSnapshot]

    func snapshot(for repository: String) -> LeaderboardSnapshot? {
        snapshots.first {
            $0.repository.caseInsensitiveCompare(repository) == .orderedSame
        }
    }
}

enum DemoData {
    enum DemoError: LocalizedError, Equatable {
        case missingFeaturedLogin
        case invalidFeaturedLogin

        var errorDescription: String? {
            switch self {
            case .missingFeaturedLogin:
                "Pass a GitHub login after --demo-user."
            case .invalidFeaturedLogin:
                "The demo user must be a valid GitHub login."
            }
        }
    }

    nonisolated static let launchArgument = "--demo-data"
    nonisolated static let userArgument = "--demo-user"

    nonisolated static func configuration(
        arguments: [String],
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> DemoLeaderboardConfiguration? {
        guard arguments.contains(launchArgument) else { return nil }
        guard let userIndex = arguments.firstIndex(of: userArgument) else {
            throw DemoError.missingFeaturedLogin
        }
        let loginIndex = arguments.index(after: userIndex)
        guard arguments.indices.contains(loginIndex),
              !arguments[loginIndex].hasPrefix("--")
        else {
            throw DemoError.missingFeaturedLogin
        }
        let featuredLogin = arguments[loginIndex]
        guard isValidGitHubLogin(featuredLogin) else {
            throw DemoError.invalidFeaturedLogin
        }
        return configuration(
            featuredLogin: featuredLogin,
            now: now,
            calendar: calendar
        )
    }

    nonisolated static func configuration(
        featuredLogin: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DemoLeaderboardConfiguration {
        let repositories = [
            RepositoryOption(fullName: "example/project", isPrivate: false, isArchived: false),
            RepositoryOption(fullName: "example/mobile-app", isPrivate: true, isArchived: false),
            RepositoryOption(fullName: "example/api-service", isPrivate: false, isArchived: false),
        ]
        let contributorSets = [
            [
                Contributor(login: featuredLogin, avatarURL: nil, mergedCount: 42, openCount: 2),
                Contributor(login: "contributor-02", avatarURL: nil, mergedCount: 31, openCount: 1),
                Contributor(login: "contributor-03", avatarURL: nil, mergedCount: 24, openCount: 4),
                Contributor(login: "contributor-04", avatarURL: nil, mergedCount: 18),
                Contributor(login: "contributor-05", avatarURL: nil, mergedCount: 12, openCount: 2),
                Contributor(login: "contributor-06", avatarURL: nil, mergedCount: 7, openCount: 1),
            ],
            [
                Contributor(login: "contributor-02", avatarURL: nil, mergedCount: 28, openCount: 3),
                Contributor(login: featuredLogin, avatarURL: nil, mergedCount: 24, openCount: 1),
                Contributor(login: "contributor-03", avatarURL: nil, mergedCount: 16, openCount: 2),
                Contributor(login: "contributor-04", avatarURL: nil, mergedCount: 9),
                Contributor(login: "contributor-05", avatarURL: nil, mergedCount: 5, openCount: 1),
            ],
            [
                Contributor(login: featuredLogin, avatarURL: nil, mergedCount: 21, openCount: 2),
                Contributor(login: "contributor-02", avatarURL: nil, mergedCount: 18),
                Contributor(login: "contributor-03", avatarURL: nil, mergedCount: 13, openCount: 1),
                Contributor(login: "contributor-04", avatarURL: nil, mergedCount: 9, openCount: 2),
            ],
        ]
        let window = MonthWindow(containing: now, calendar: calendar)
        let snapshots = zip(repositories, contributorSets).map { repository, contributors in
            LeaderboardSnapshot(
                metricVersion: LeaderboardSnapshot.currentMetricVersion,
                repository: repository.fullName,
                periodStart: window.start,
                periodEnd: window.end,
                fetchedAt: now,
                totalCount: contributors.reduce(0) { $0 + $1.mergedCount },
                contributors: contributors
            )
        }
        return DemoLeaderboardConfiguration(
            selectedRepository: repositories[0].fullName,
            repositories: repositories,
            snapshots: snapshots
        )
    }

    nonisolated static func isValidGitHubLogin(_ login: String) -> Bool {
        guard !login.isEmpty, login.count <= 39,
              login.first != "-", login.last != "-",
              !login.contains("--")
        else {
            return false
        }
        return login.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
}
