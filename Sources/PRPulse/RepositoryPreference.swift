import Foundation

struct RepositoryPreference {
    private let defaults: UserDefaults
    private let key: String

    static var live: RepositoryPreference {
        RepositoryPreference(
            defaults: .standard,
            key: "selectedRepository"
        )
    }

    init(defaults: UserDefaults, key: String = "selectedRepository") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> String? {
        guard let repository = defaults.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !repository.isEmpty
        else {
            return nil
        }
        return repository
    }

    func save(_ repository: String) {
        defaults.set(repository, forKey: key)
    }
}
