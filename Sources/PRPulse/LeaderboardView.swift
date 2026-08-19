import AppKit
import Observation
import SwiftUI

struct LeaderboardView: View {
    @Bindable var store: LeaderboardStore
    let onRepositoryPickerVisibilityChange: (Bool) -> Void
    let onSelectRepository: (RepositoryOption) -> Void
    let onDismiss: () -> Void

    @State private var isChoosingRepository = false
    @State private var repositoryFilter = ""

    nonisolated static let repositoryPickerHeight: CGFloat = 440

    nonisolated static func preferredHeight(
        contributorCount: Int?,
        hasError: Bool = false
    ) -> CGFloat {
        let rowCount = contributorCount ?? 6
        let rowHeight = CGFloat(rowCount * 39)
        let rowSpacing = CGFloat(max(rowCount - 1, 0) * 3)
        let chromeHeight: CGFloat = 52 + 44 + 2
        let contentPadding: CGFloat = 20
        let errorHeight: CGFloat = hasError ? 43 : 0
        return min(
            max(chromeHeight + contentPadding + rowHeight + rowSpacing + errorHeight, 280),
            440
        )
    }

    var body: some View {
        Group {
            if isChoosingRepository {
                repositoryPicker
            } else {
                leaderboardScreen
            }
        }
        .frame(
            width: 560,
            height: isChoosingRepository
                ? Self.repositoryPickerHeight
                : Self.preferredHeight(
                    contributorCount: store.snapshot?.contributors.count,
                    hasError: store.lastError != nil
                )
        )
        .background(.thinMaterial)
    }
}

private extension LeaderboardView {
    var leaderboardScreen: some View {
        VStack(spacing: 0) {
            header
            PRPulseDivider()

            if let error = store.lastError {
                ErrorBanner(message: error)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }

            content
            PRPulseDivider()
            footer
        }
    }

    var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PRPulsePalette.accent)

            Text("By author")
                .font(.system(size: 13, weight: .semibold))

            Text("merged in \(monthName)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()

            if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .help("Refreshing in the background")
            }

            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.pull")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(PRPulsePalette.accent)
                Text("\(store.snapshot?.totalCount ?? 0)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                PRPulsePalette.accent.opacity(0.11),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(PRPulsePalette.accent.opacity(0.22), lineWidth: 1)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .background(PRPulsePalette.chrome)
    }

    @ViewBuilder
    var content: some View {
        if store.repository == nil {
            ContentUnavailableView(
                "Choose a repository",
                systemImage: "shippingbox",
                description: Text("Select a GitHub repository to see its month-to-date leaderboard.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let snapshot = store.snapshot {
            if snapshot.contributors.isEmpty {
                ContentUnavailableView(
                    "No pull requests yet",
                    systemImage: "arrow.triangle.pull",
                    description: Text("Nothing has merged in this repository this month.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                leaderboard(snapshot)
            }
        } else if let lastError = store.lastError, !store.isRefreshing {
            ContentUnavailableView(
                "Unable to load pull requests",
                systemImage: "exclamationmark.triangle",
                description: Text(lastError)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            LoadingLeaderboard()
        }
    }

    func leaderboard(_ snapshot: LeaderboardSnapshot) -> some View {
        let maxCount = max(snapshot.contributors.first?.mergedCount ?? 1, 1)

        return ScrollView {
            LazyVStack(spacing: 3) {
                ForEach(Array(snapshot.contributors.enumerated()), id: \.element.id) { index, contributor in
                    ContributorRow(
                        rank: index + 1,
                        contributor: contributor,
                        repository: snapshot.repository,
                        maxCount: maxCount,
                        allowsExternalLinks: !store.isDemoMode,
                        onDismiss: onDismiss
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    var footer: some View {
        HStack(spacing: 10) {
            Button {
                showRepositoryPicker()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "shippingbox")
                    Text(store.repository ?? "Choose repository")
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Choose a GitHub repository")

            Spacer()
        }
        .font(.system(size: 11))
        .padding(.horizontal, 18)
        .frame(height: 44)
        .background(PRPulsePalette.chrome)
    }

    var monthName: String {
        if let start = store.snapshot?.periodStart {
            return start.formatted(.dateTime.month(.wide))
        }
        return MonthWindow(containing: Date()).monthName
    }

    func showRepositoryPicker() {
        repositoryFilter = ""
        isChoosingRepository = true
        onRepositoryPickerVisibilityChange(true)
        if store.repositories.isEmpty {
            Task { await store.loadRepositories() }
        }
    }
}

private extension LeaderboardView {
    var repositoryPicker: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    closeRepositoryPicker()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help("Back to leaderboard")

                Text("Choose repository")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                if !store.repositories.isEmpty {
                    Text("\(store.repositories.count)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            .background(PRPulsePalette.chrome)

            PRPulseDivider()

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter repositories", text: $repositoryFilter)
                    .textFieldStyle(.plain)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                Color(nsColor: .controlBackgroundColor).opacity(0.58),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(PRPulsePalette.separator, lineWidth: 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            repositoryPickerContent

            PRPulseDivider()

            HStack {
                Text(repositoryPickerStatus)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await store.loadRepositories() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(store.isLoadingRepositories)
                .help("Refresh accessible repositories")
            }
            .font(.system(size: 11))
            .padding(.horizontal, 18)
            .frame(height: 40)
            .background(PRPulsePalette.chrome)
        }
    }

    @ViewBuilder
    var repositoryPickerContent: some View {
        if store.isLoadingRepositories, store.repositories.isEmpty {
            RepositoryLoadingRows()
        } else if let repositoryError = store.repositoryError, store.repositories.isEmpty {
            ContentUnavailableView(
                "Repositories unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text(repositoryError)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredRepositories.isEmpty {
            ContentUnavailableView.search(text: repositoryFilter)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredRepositories) { repository in
                        RepositoryRow(
                            repository: repository,
                            isSelected: store.repository?.caseInsensitiveCompare(repository.fullName)
                                == .orderedSame
                        ) {
                            onSelectRepository(repository)
                            closeRepositoryPicker()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
    }

    var filteredRepositories: [RepositoryOption] {
        let query = repositoryFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.repositories }
        return store.repositories.filter { $0.fullName.localizedCaseInsensitiveContains(query) }
    }

    var repositoryPickerStatus: String {
        if store.isLoadingRepositories {
            return "Refreshing repositories…"
        }
        if let repositoryError = store.repositoryError, !store.repositories.isEmpty {
            return repositoryError
        }
        return "Accessible through GitHub CLI"
    }

    func closeRepositoryPicker() {
        isChoosingRepository = false
        repositoryFilter = ""
        onRepositoryPickerVisibilityChange(false)
    }
}

private struct RepositoryRow: View {
    let repository: RepositoryOption
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                Image(systemName: repository.isPrivate ? "lock.fill" : "shippingbox")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Text(repository.fullName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Spacer()

                if repository.isArchived {
                    Text("Archived")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PRPulsePalette.accent)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .frame(height: 34)
        }
        .buttonStyle(LeaderboardRowButtonStyle())
        .help("Show month-to-date stats for \(repository.fullName)")
    }
}

private struct RepositoryLoadingRows: View {
    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { index in
                HStack(spacing: 9) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.quaternary)
                        .frame(width: 14, height: 14)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .frame(width: CGFloat(150 + (index % 3) * 34), height: 10)
                    Spacer()
                }
                .frame(height: 34)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Loading accessible repositories")
    }
}

private struct ContributorRow: View {
    let rank: Int
    let contributor: Contributor
    let repository: String
    let maxCount: Int
    let allowsExternalLinks: Bool
    let onDismiss: () -> Void

    @ViewBuilder
    var body: some View {
        if allowsExternalLinks {
            Button(action: openPullRequests) {
                rowContent
            }
            .buttonStyle(LeaderboardRowButtonStyle())
            .help("Open @\(contributor.login)'s open pull requests")
        } else {
            rowContent
        }
    }

    var rowContent: some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 18, alignment: .trailing)

            AvatarView(url: contributor.avatarURL, login: contributor.login)

            Text(contributor.login)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .frame(width: 112, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(PRPulsePalette.progressTrack)
                    Capsule()
                        .fill(PRPulsePalette.accent.opacity(0.9))
                        .frame(
                            width: max(
                                4,
                                proxy.size.width * CGFloat(contributor.mergedCount) / CGFloat(maxCount)
                            )
                        )
                }
            }
            .frame(height: 6)

            Text("\(contributor.mergedCount)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)

            Text("\(contributor.openCount) open")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 48, alignment: .leading)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 8)
        .frame(height: 39)
    }

    func openPullRequests() {
        guard let url = GitHubClient.openPullRequestsURL(
            repository: repository,
            author: contributor.login
        ) else { return }
        NSWorkspace.shared.open(url)
        onDismiss()
    }
}

private struct AvatarView: View {
    let url: URL?
    let login: String

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case let .success(image):
                image.resizable().scaledToFill()
            default:
                ZStack {
                    Circle().fill(Color.secondary.opacity(0.14))
                    Image(systemName: "person.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 27, height: 27)
        .clipShape(Circle())
        .overlay {
            Circle().stroke(PRPulsePalette.separator, lineWidth: 1)
        }
        .accessibilityLabel("\(login)'s avatar")
    }
}

private struct LeaderboardRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(LeaderboardRowInteraction(isPressed: configuration.isPressed))
    }
}

private struct LeaderboardRowInteraction: ViewModifier {
    let isPressed: Bool

    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(PRPulsePalette.selection.opacity(backgroundOpacity))
            }
            .onHover { isHovered = $0 }
    }

    private var backgroundOpacity: Double {
        if isPressed { return 0.18 }
        if isHovered { return 0.09 }
        return 0
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .foregroundStyle(.orange)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct LoadingLeaderboard: View {
    var body: some View {
        VStack(spacing: 9) {
            ForEach(0..<6, id: \.self) { index in
                HStack(spacing: 10) {
                    Circle().fill(.quaternary).frame(width: 27, height: 27)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .frame(width: CGFloat(75 + index * 7), height: 10)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .frame(width: 24, height: 10)
                }
                .frame(height: 39)
            }
            Spacer()
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Loading pull request leaderboard")
    }
}

private struct PRPulseDivider: View {
    var body: some View {
        Rectangle()
            .fill(PRPulsePalette.separator)
            .frame(height: 1)
    }
}

private enum PRPulsePalette {
    static let accent = Color(nsColor: .controlAccentColor)
    static let chrome = Color(nsColor: .windowBackgroundColor).opacity(0.32)
    static let progressTrack = Color(nsColor: .quaternaryLabelColor).opacity(0.45)
    static let selection = Color(nsColor: .selectedContentBackgroundColor)
    static let separator = Color(nsColor: .separatorColor).opacity(0.72)
}
