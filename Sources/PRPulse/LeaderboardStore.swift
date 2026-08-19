import Foundation
import Observation

@MainActor
@Observable
final class LeaderboardStore {
    private(set) var repository: String?
    private(set) var repositories: [RepositoryOption] = []
    private(set) var snapshot: LeaderboardSnapshot?
    private(set) var isRefreshing = false
    private(set) var isLoadingRepositories = false
    private(set) var lastError: String?
    private(set) var repositoryError: String?
    var isDemoMode: Bool { demoConfiguration != nil }

    @ObservationIgnored private let client: GitHubClient
    @ObservationIgnored private let cache: SnapshotCache
    @ObservationIgnored private let preference: RepositoryPreference
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let onPresentationChange: (LeaderboardSnapshot?, Bool) -> Void
    @ObservationIgnored private let demoConfiguration: DemoLeaderboardConfiguration?
    @ObservationIgnored private var snapshotsByRepository: [String: LeaderboardSnapshot] = [:]
    @ObservationIgnored private var repositoryGeneration = 0

    init(
        repository: String?,
        client: GitHubClient = GitHubClient(),
        cache: SnapshotCache = .live,
        preference: RepositoryPreference = .live,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current,
        demoConfiguration: DemoLeaderboardConfiguration? = nil,
        onPresentationChange: @escaping (LeaderboardSnapshot?, Bool) -> Void = { _, _ in }
    ) {
        self.client = client
        self.cache = cache
        self.preference = preference
        self.now = now
        self.calendar = calendar
        self.demoConfiguration = demoConfiguration
        self.onPresentationChange = onPresentationChange

        if let demoConfiguration {
            self.repository = demoConfiguration.selectedRepository
            repositories = demoConfiguration.repositories
            snapshot = demoConfiguration.snapshot(for: demoConfiguration.selectedRepository)
            snapshotsByRepository = Dictionary(
                uniqueKeysWithValues: demoConfiguration.snapshots.map {
                    ($0.repository.lowercased(), $0)
                }
            )
            return
        }

        let selectedRepository = repository?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.repository = selectedRepository?.isEmpty == false ? selectedRepository : nil
        if let selectedRepository = self.repository {
            snapshot = try? cache.loadCurrentMonth(
                repository: selectedRepository,
                now: now(),
                calendar: calendar
            )
            if let snapshot {
                snapshotsByRepository[selectedRepository.lowercased()] = snapshot
            }
            preference.save(selectedRepository)
        }
    }

    func loadRepositories() async {
        if let demoConfiguration {
            repositories = demoConfiguration.repositories
            repositoryError = nil
            return
        }
        guard !isLoadingRepositories else { return }
        isLoadingRepositories = true
        defer { isLoadingRepositories = false }

        do {
            repositories = try await client.fetchRepositories()
            repositoryError = nil
        } catch {
            repositoryError = error.localizedDescription
        }
    }

    @discardableResult
    func selectRepository(_ selectedRepository: String) -> Bool {
        let selectedRepository = selectedRepository.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedRepository.isEmpty,
              repository?.caseInsensitiveCompare(selectedRepository) != .orderedSame
        else {
            return false
        }

        repositoryGeneration += 1
        if let demoConfiguration {
            guard let demoSnapshot = demoConfiguration.snapshot(for: selectedRepository) else {
                return false
            }
            repository = demoSnapshot.repository
            snapshot = demoSnapshot
            lastError = nil
            repositoryError = nil
            onPresentationChange(demoSnapshot, false)
            return true
        }

        repository = selectedRepository
        preference.save(selectedRepository)
        let repositoryKey = selectedRepository.lowercased()
        let currentDate = now()
        if let memorySnapshot = snapshotsByRepository[repositoryKey],
           cache.isCurrentMonth(
               memorySnapshot,
               repository: selectedRepository,
               now: currentDate,
               calendar: calendar
           ) {
            snapshot = memorySnapshot
        } else {
            snapshotsByRepository.removeValue(forKey: repositoryKey)
            snapshot = try? cache.loadCurrentMonth(
                repository: selectedRepository,
                now: currentDate,
                calendar: calendar
            )
        }
        if let snapshot {
            snapshotsByRepository[repositoryKey] = snapshot
        }
        lastError = nil
        onPresentationChange(snapshot, false)
        return true
    }

    func refresh() async {
        guard let requestedRepository = repository else { return }
        if let demoConfiguration {
            snapshot = demoConfiguration.snapshot(for: requestedRepository)
            lastError = nil
            onPresentationChange(snapshot, false)
            return
        }
        let requestedGeneration = repositoryGeneration
        isRefreshing = true
        defer {
            if requestedGeneration == repositoryGeneration {
                isRefreshing = false
            }
        }

        do {
            let freshSnapshot = try await client.fetchMonthToDate(repository: requestedRepository)
            guard requestedGeneration == repositoryGeneration,
                  repository?.caseInsensitiveCompare(requestedRepository) == .orderedSame
            else {
                return
            }
            snapshot = freshSnapshot
            snapshotsByRepository[requestedRepository.lowercased()] = freshSnapshot
            lastError = nil

            do {
                try cache.save(freshSnapshot)
            } catch {
                lastError = "Updated, but could not save the local cache."
            }
            onPresentationChange(freshSnapshot, lastError != nil)
        } catch {
            guard requestedGeneration == repositoryGeneration else { return }
            lastError = error.localizedDescription
            onPresentationChange(snapshot, true)
        }
    }
}
