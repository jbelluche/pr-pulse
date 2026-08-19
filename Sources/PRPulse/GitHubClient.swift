import Darwin
import Dispatch
import Foundation

struct GitHubClient: Sendable {
    enum ClientError: LocalizedError {
        case cliNotFound
        case commandFailed(String)
        case commandTimedOut
        case invalidRepository

        var errorDescription: String? {
            switch self {
            case .cliNotFound:
                "GitHub CLI was not found. Install it with `brew install gh`."
            case let .commandFailed(message):
                message
            case .commandTimedOut:
                "GitHub CLI did not finish within 20 seconds."
            case .invalidRepository:
                "The repository must use the owner/name format."
            }
        }
    }

    func fetchMonthToDate(
        repository: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async throws -> LeaderboardSnapshot {
        guard Self.isValid(repository: repository) else {
            throw ClientError.invalidRepository
        }

        let requestTask = Task.detached(priority: .utility) {
            let executable = try Self.resolveGitHubCLI()
            let window = MonthWindow(containing: now, calendar: calendar)
            let query = Self.monthToDateQuery(
                repository: repository,
                window: window
            )
            let output = try Self.run(
                executable: executable,
                arguments: [
                    "api", "--paginate", "--slurp", "-X", "GET", "search/issues",
                    "-f", "q=\(query)",
                    "-f", "per_page=100",
                ]
            )
            let openOutput = try Self.run(
                executable: executable,
                arguments: [
                    "api", "--paginate", "--slurp", "-X", "GET", "search/issues",
                    "-f", "q=\(Self.openPullRequestsQuery(repository: repository))",
                    "-f", "per_page=100",
                ]
            )

            return try GitHubSearchParser.snapshot(
                from: Data(output.utf8),
                openPullRequestsData: Data(openOutput.utf8),
                repository: repository,
                window: window
            )
        }

        return try await withTaskCancellationHandler {
            try await requestTask.value
        } onCancel: {
            requestTask.cancel()
        }
    }

    func fetchRepositories() async throws -> [RepositoryOption] {
        let requestTask = Task.detached(priority: .utility) {
            let executable = try Self.resolveGitHubCLI()
            let output = try Self.run(
                executable: executable,
                arguments: [
                    "api", "--paginate", "--slurp", "-X", "GET", "user/repos",
                    "-f", "per_page=100",
                    "-f", "sort=updated",
                    "-f", "affiliation=owner,collaborator,organization_member",
                ]
            )
            return try RepositoryListParser.repositories(from: Data(output.utf8))
        }

        return try await withTaskCancellationHandler {
            try await requestTask.value
        } onCancel: {
            requestTask.cancel()
        }
    }

    static func monthToDateQuery(
        repository: String,
        window: MonthWindow
    ) -> String {
        "repo:\(repository) is:pr is:merged merged:>=\(window.queryStart)"
    }

    static func openPullRequestsQuery(repository: String) -> String {
        "repo:\(repository) is:pr is:open"
    }

    static func openPullRequestsURL(repository: String, author: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/\(repository)/pulls"
        components.queryItems = [
            URLQueryItem(name: "q", value: "is:pr is:open author:\(author)"),
        ]
        return components.url
    }
}

struct RepositoryOption: Decodable, Equatable, Identifiable, Sendable {
    let fullName: String
    let isPrivate: Bool
    let isArchived: Bool

    var id: String { fullName.lowercased() }

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case isPrivate = "private"
        case isArchived = "archived"
    }
}

enum RepositoryListParser {
    static func repositories(from data: Data) throws -> [RepositoryOption] {
        let pages = try JSONDecoder().decode([[RepositoryOption]].self, from: data)
        var seen = Set<String>()
        return pages
            .flatMap { $0 }
            .filter { seen.insert($0.id).inserted }
    }
}

private extension GitHubClient {
    static func isValid(repository: String) -> Bool {
        let parts = repository.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ ."))
            .subtracting(CharacterSet(charactersIn: " "))
        return parts.allSatisfy {
            !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains)
        }
    }

    static func resolveGitHubCLI() throws -> URL {
        let fileManager = FileManager.default
        let candidates = [
            ProcessInfo.processInfo.environment["PR_PULSE_GH_BIN"],
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh",
        ].compactMap { $0 }

        if let path = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: path)
        }
        throw ClientError.cliNotFound
    }

    static func run(executable: URL, arguments: [String]) throws -> String {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("PRPulse-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let outputURL = temporaryDirectory.appendingPathComponent("stdout")
        let errorURL = temporaryDirectory.appendingPathComponent("stderr")
        fileManager.createFile(
            atPath: outputURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        )
        fileManager.createFile(
            atPath: errorURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        )
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
        }

        let process = Process()
        let completion = DispatchSemaphore(value: 0)
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = outputHandle
        process.standardError = errorHandle
        process.terminationHandler = { _ in completion.signal() }

        do {
            try process.run()
        } catch {
            throw ClientError.commandFailed(error.localizedDescription)
        }

        let deadline = DispatchTime.now().uptimeNanoseconds + 20_000_000_000
        while completion.wait(timeout: .now() + .milliseconds(100)) == .timedOut {
            if Task.isCancelled {
                stop(process, completion: completion)
                throw CancellationError()
            }
            if DispatchTime.now().uptimeNanoseconds >= deadline {
                stop(process, completion: completion)
                throw ClientError.commandTimedOut
            }
        }

        try outputHandle.synchronize()
        try errorHandle.synchronize()
        let output = try Data(contentsOf: outputURL)
        let errorOutput = try Data(contentsOf: errorURL)

        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorOutput, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ClientError.commandFailed(
                message.isEmpty ? "GitHub CLI exited with status \(process.terminationStatus)." : message
            )
        }
        return String(decoding: output, as: UTF8.self)
    }

    static func stop(_ process: Process, completion: DispatchSemaphore) {
        guard process.isRunning else { return }
        process.terminate()
        if completion.wait(timeout: .now() + .seconds(1)) == .timedOut {
            kill(process.processIdentifier, SIGKILL)
            _ = completion.wait(timeout: .now() + .seconds(1))
        }
    }
}
