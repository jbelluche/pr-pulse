import Foundation
import Testing
@testable import PRPulse

@Suite
struct LeaderboardTests {
    @Test
    func monthWindowStartsOnFirstDayOfConfiguredMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: -6 * 60 * 60))
        let date = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 18, hour: 14))
        )

        let window = MonthWindow(containing: date, calendar: calendar)

        #expect(window.queryStart == "2026-08-01T06:00:00Z")
        #expect(calendar.component(.day, from: window.start) == 1)
        #expect(window.end == date)
    }

    @Test
    func monthWindowPreservesPositiveOffsetBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 9 * 60 * 60))
        let date = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 18, hour: 14))
        )

        let window = MonthWindow(containing: date, calendar: calendar)

        #expect(window.queryStart == "2026-07-31T15:00:00Z")
        #expect(calendar.component(.day, from: window.start) == 1)
    }

    @Test
    func parserGroupsDeduplicatesAndSortsContributors() throws {
        let data = Data(
            #"""
            [
              {
                "total_count": 3,
                "items": [
                  {"number": 11, "user": {"login": "alice", "avatar_url": "https://example.com/a.png"}},
                  {"number": 12, "user": {"login": "bob", "avatar_url": "https://example.com/b.png"}}
                ]
              },
              {
                "total_count": 3,
                "items": [
                  {"number": 12, "user": {"login": "bob", "avatar_url": "https://example.com/b.png"}},
                  {"number": 13, "user": {"login": "alice", "avatar_url": "https://example.com/a.png"}}
                ]
              }
            ]
            """#.utf8
        )
        let now = Date(timeIntervalSince1970: 1_776_000_000)
        let openData = Data(
            #"""
            [
              {
                "total_count": 3,
                "items": [
                  {"number": 101, "user": {"login": "alice"}},
                  {"number": 102, "user": {"login": "alice"}},
                  {"number": 103, "user": {"login": "bob"}}
                ]
              }
            ]
            """#.utf8
        )

        let snapshot = try GitHubSearchParser.snapshot(
            from: data,
            openPullRequestsData: openData,
            repository: "ExampleOrg/example-repo",
            window: MonthWindow(containing: now),
            fetchedAt: now
        )

        #expect(snapshot.totalCount == 3)
        #expect(snapshot.contributors.map(\.login) == ["alice", "bob"])
        #expect(snapshot.contributors.map(\.mergedCount) == [2, 1])
        #expect(snapshot.contributors.map(\.openCount) == [2, 1])
        #expect(snapshot.contributors.first?.avatarURL?.absoluteString == "https://example.com/a.png")
    }

    @Test
    func contributorCacheDecodesBeforeOpenCountsExisted() throws {
        let data = Data(
            #"""
            {"login":"alice","mergedCount":2}
            """#.utf8
        )

        let contributor = try JSONDecoder().decode(Contributor.self, from: data)

        #expect(contributor.openCount == 0)
    }

    @Test
    func repositoryListParserPreservesUpdatedOrderAndDeduplicates() throws {
        let data = Data(
            #"""
            [
              [
                {"full_name":"ExampleOrg/newest","private":true,"archived":false},
                {"full_name":"SampleOrg/public-repo","private":false,"archived":false}
              ],
              [
                {"full_name":"exampleorg/NEWEST","private":true,"archived":false},
                {"full_name":"ExampleOrg/legacy","private":true,"archived":true}
              ]
            ]
            """#.utf8
        )

        let repositories = try RepositoryListParser.repositories(from: data)

        #expect(repositories.map(\.fullName) == [
            "ExampleOrg/newest",
            "SampleOrg/public-repo",
            "ExampleOrg/legacy",
        ])
        #expect(repositories[0].isPrivate)
        #expect(repositories[2].isArchived)
    }

    @MainActor
    @Test
    func repositorySelectionPersistsWithoutACompiledDefault() throws {
        let suiteName = "PRPulseTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preference = RepositoryPreference(defaults: defaults)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = SnapshotCache(fileURL: directory.appendingPathComponent("cache.json"))
        let store = LeaderboardStore(
            repository: nil,
            cache: cache,
            preference: preference
        )

        #expect(store.repository == nil)
        #expect(store.selectRepository("ExampleOrg/example-repo"))
        #expect(store.repository == "ExampleOrg/example-repo")
        #expect(preference.load() == "ExampleOrg/example-repo")
        #expect(!store.selectRepository("exampleorg/EXAMPLE-REPO"))
    }

    @Test
    func parserRejectsIncompletePagination() {
        let data = Data(
            #"""
            [{"total_count": 2, "items": [{"number": 11, "user": {"login": "alice"}}]}]
            """#.utf8
        )

        #expect(
            throws: GitHubSearchParser.ParseError.incompleteResults(expected: 2, received: 1)
        ) {
            try GitHubSearchParser.snapshot(
                from: data,
                repository: "ExampleOrg/example-repo",
                window: MonthWindow(containing: Date())
            )
        }
    }

    @Test
    func parserRejectsResultsFlaggedIncomplete() {
        let data = Data(
            #"""
            [{"total_count": 1, "incomplete_results": true, "items": [{"number": 11}]}]
            """#.utf8
        )

        #expect(throws: GitHubSearchParser.ParseError.resultsFlaggedIncomplete) {
            try GitHubSearchParser.snapshot(
                from: data,
                repository: "ExampleOrg/example-repo",
                window: MonthWindow(containing: Date())
            )
        }
    }

    @Test
    func cacheOnlyLoadsCurrentMonth() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = SnapshotCache(fileURL: directory.appendingPathComponent("cache.json"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let august = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 18))
        )
        let snapshot = LeaderboardSnapshot(
            metricVersion: LeaderboardSnapshot.currentMetricVersion,
            repository: "ExampleOrg/example-repo",
            periodStart: MonthWindow(containing: august, calendar: calendar).start,
            periodEnd: august,
            fetchedAt: august,
            totalCount: 1,
            contributors: [Contributor(login: "alice", avatarURL: nil, mergedCount: 1)]
        )
        try cache.save(snapshot)

        #expect(cache.lastRepository() == "ExampleOrg/example-repo")

        #expect(
            try cache.loadCurrentMonth(
                repository: "ExampleOrg/example-repo",
                now: august,
                calendar: calendar
            ) == snapshot
        )
        #expect(
            try cache.loadCurrentMonth(
                repository: "another/repository",
                now: august,
                calendar: calendar
            ) == nil
        )
        let september = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))
        )
        #expect(
            try cache.loadCurrentMonth(
                repository: "ExampleOrg/example-repo",
                now: september,
                calendar: calendar
            ) == nil
        )
    }

    @MainActor
    @Test
    func repositorySelectionRejectsAnExpiredInMemorySnapshot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = SnapshotCache(fileURL: directory.appendingPathComponent("cache.json"))
        let suiteName = "PRPulseTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let august = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 18))
        )
        let september = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))
        )
        let snapshot = LeaderboardSnapshot(
            metricVersion: LeaderboardSnapshot.currentMetricVersion,
            repository: "ExampleOrg/example-repo",
            periodStart: MonthWindow(containing: august, calendar: calendar).start,
            periodEnd: august,
            fetchedAt: august,
            totalCount: 1,
            contributors: [Contributor(login: "alice", avatarURL: nil, mergedCount: 1)]
        )
        try cache.save(snapshot)
        var currentDate = august
        let store = LeaderboardStore(
            repository: "ExampleOrg/example-repo",
            cache: cache,
            preference: RepositoryPreference(defaults: defaults),
            now: { currentDate },
            calendar: calendar
        )
        #expect(store.snapshot == snapshot)

        #expect(store.selectRepository("ExampleOrg/another-repo"))
        currentDate = september
        #expect(store.selectRepository("ExampleOrg/example-repo"))
        #expect(store.snapshot == nil)
    }

    @Test
    func cacheRejectsLegacyDefaultBranchMetric() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let fileURL = directory.appendingPathComponent("cache.json")
        let cache = SnapshotCache(fileURL: fileURL)
        let legacyData = Data(
            #"""
            {
              "repository": "ExampleOrg/example-repo",
              "defaultBranch": "main",
              "periodStart": "2026-08-01T00:00:00Z",
              "periodEnd": "2026-08-18T00:00:00Z",
              "fetchedAt": "2026-08-18T00:00:00Z",
              "totalCount": 54,
              "contributors": []
            }
            """#.utf8
        )
        try legacyData.write(to: fileURL)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let august = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 18))
        )

        #expect(
            try cache.loadCurrentMonth(
                repository: "ExampleOrg/example-repo",
                now: august,
                calendar: calendar
            ) == nil
        )
    }

    @Test
    func monthToDateQueryIncludesEveryBaseBranch() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 18))
        )

        let query = GitHubClient.monthToDateQuery(
            repository: "ExampleOrg/example-repo",
            window: MonthWindow(containing: date, calendar: calendar)
        )

        #expect(
            query == "repo:ExampleOrg/example-repo is:pr is:merged merged:>=2026-08-01T00:00:00Z"
        )
    }

    @Test
    func openPullRequestQueryAndURLStayInsideRepository() throws {
        #expect(
            GitHubClient.openPullRequestsQuery(repository: "ExampleOrg/example-repo")
                == "repo:ExampleOrg/example-repo is:pr is:open"
        )
        let url = try #require(
            GitHubClient.openPullRequestsURL(
                repository: "ExampleOrg/example-repo",
                author: "sample-contributor"
            )
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/ExampleOrg/example-repo/pulls")
        #expect(components.queryItems?.first?.value == "is:pr is:open author:sample-contributor")
    }

    @Test
    func popoverHeightFitsRowsAndCapsForScrolling() {
        #expect(LeaderboardView.preferredHeight(contributorCount: 6) == 367)
        #expect(LeaderboardView.preferredHeight(contributorCount: 6, hasError: true) == 410)
        #expect(LeaderboardView.preferredHeight(contributorCount: 0) == 280)
        #expect(LeaderboardView.preferredHeight(contributorCount: 8) == 440)
    }

    @Test
    func automaticRefreshRunsEveryThirtySeconds() {
        #expect(AppDelegate.refreshInterval == 30)
    }

    @Test
    func statusItemClickRoutesRightClickToQuitMenu() {
        #expect(AppDelegate.interaction(for: .leftMouseUp) == .togglePopover)
        #expect(AppDelegate.interaction(for: .rightMouseUp) == .showQuitMenu)
        #expect(
            AppDelegate.interaction(for: .leftMouseUp, modifierFlags: .control)
                == .showQuitMenu
        )
        #expect(AppDelegate.quitMenuTitle == "Quit PR Pulse")
    }

    @Test
    func readmeScreenshotRequestRequiresAnExplicitSafeUser() throws {
        let parsedRequest = try ReadmeScreenshot.request(arguments: [
            "PRPulse",
            "--generate-readme-screenshot",
            "/tmp/pr-pulse.png",
            "--demo-user",
            "sample-user",
        ])
        let request = try #require(parsedRequest)

        #expect(request.outputURL.path == "/tmp/pr-pulse.png")
        #expect(request.featuredLogin == "sample-user")
        #expect(
            throws: ReadmeScreenshot.ScreenshotError.invalidFeaturedLogin
        ) {
            try ReadmeScreenshot.request(arguments: [
                "PRPulse",
                "--generate-readme-screenshot",
                "/tmp/pr-pulse.png",
                "--demo-user",
                "not a login",
            ])
        }
    }

    @Test
    func readmeScreenshotFixtureContainsNoRepositoryOrContributorIdentity() throws {
        let snapshot = ReadmeScreenshot.fixture(featuredLogin: "sample-user")

        #expect(snapshot.repository == "example/project")
        #expect(snapshot.contributors.first?.login == "sample-user")
        #expect(
            snapshot.contributors.dropFirst().allSatisfy {
                $0.login.hasPrefix("contributor-")
            }
        )
        #expect(snapshot.contributors.allSatisfy { $0.avatarURL == nil })
        #expect(
            snapshot.totalCount == snapshot.contributors.reduce(0) {
                $0 + $1.mergedCount
            }
        )
    }

    @Test
    func canceledRefreshCannotClearItsReplacementTask() {
        var ownership = RefreshTaskGeneration()
        let canceledGeneration = ownership.begin()
        ownership.invalidate()
        let replacementGeneration = ownership.begin()

        #expect(!ownership.owns(canceledGeneration))
        #expect(ownership.owns(replacementGeneration))
    }
}
