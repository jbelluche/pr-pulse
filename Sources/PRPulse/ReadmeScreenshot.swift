import AppKit
import SwiftUI

enum ReadmeScreenshot {
    struct Request: Equatable {
        let outputURL: URL
        let featuredLogin: String
    }

    enum ScreenshotError: LocalizedError, Equatable {
        case missingOutputPath
        case missingFeaturedLogin
        case invalidFeaturedLogin
        case couldNotCreateBitmap
        case couldNotEncodePNG

        var errorDescription: String? {
            switch self {
            case .missingOutputPath:
                "Pass an output path after --generate-readme-screenshot."
            case .missingFeaturedLogin:
                "Pass a GitHub login after --demo-user."
            case .invalidFeaturedLogin:
                "The demo user must be a valid GitHub login."
            case .couldNotCreateBitmap:
                "macOS could not create the screenshot bitmap."
            case .couldNotEncodePNG:
                "macOS could not encode the screenshot as PNG."
            }
        }
    }

    nonisolated static let generateArgument = "--generate-readme-screenshot"
    nonisolated static let userArgument = "--demo-user"
    nonisolated static let fixtureRepository = "example/project"

    nonisolated static func request(arguments: [String]) throws -> Request? {
        guard let generateIndex = arguments.firstIndex(of: generateArgument) else {
            return nil
        }
        let outputIndex = arguments.index(after: generateIndex)
        guard arguments.indices.contains(outputIndex),
              !arguments[outputIndex].hasPrefix("--")
        else {
            throw ScreenshotError.missingOutputPath
        }

        guard let userIndex = arguments.firstIndex(of: userArgument) else {
            throw ScreenshotError.missingFeaturedLogin
        }
        let loginIndex = arguments.index(after: userIndex)
        guard arguments.indices.contains(loginIndex),
              !arguments[loginIndex].hasPrefix("--")
        else {
            throw ScreenshotError.missingFeaturedLogin
        }
        let featuredLogin = arguments[loginIndex]
        guard isValidGitHubLogin(featuredLogin) else {
            throw ScreenshotError.invalidFeaturedLogin
        }

        return Request(
            outputURL: URL(fileURLWithPath: arguments[outputIndex]),
            featuredLogin: featuredLogin
        )
    }

    nonisolated static func fixture(
        featuredLogin: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> LeaderboardSnapshot {
        let contributors = [
            Contributor(login: featuredLogin, avatarURL: nil, mergedCount: 42, openCount: 2),
            Contributor(login: "contributor-02", avatarURL: nil, mergedCount: 31, openCount: 1),
            Contributor(login: "contributor-03", avatarURL: nil, mergedCount: 24, openCount: 4),
            Contributor(login: "contributor-04", avatarURL: nil, mergedCount: 18),
            Contributor(login: "contributor-05", avatarURL: nil, mergedCount: 12, openCount: 2),
            Contributor(login: "contributor-06", avatarURL: nil, mergedCount: 7, openCount: 1),
        ]
        let window = MonthWindow(containing: now, calendar: calendar)
        return LeaderboardSnapshot(
            metricVersion: LeaderboardSnapshot.currentMetricVersion,
            repository: fixtureRepository,
            periodStart: window.start,
            periodEnd: window.end,
            fetchedAt: now,
            totalCount: contributors.reduce(0) { $0 + $1.mergedCount },
            contributors: contributors
        )
    }

    @MainActor
    static func generate(_ request: Request) throws {
        let now = Date()
        let calendar = Calendar.current
        let snapshot = fixture(
            featuredLogin: request.featuredLogin,
            now: now,
            calendar: calendar
        )
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PRPulseScreenshot-\(UUID().uuidString)", isDirectory: true)
        let cache = SnapshotCache(fileURL: temporaryDirectory.appendingPathComponent("fixture.json"))
        let defaultsSuite = "PRPulseScreenshot.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
            throw ScreenshotError.couldNotCreateBitmap
        }
        defer {
            defaults.removePersistentDomain(forName: defaultsSuite)
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        try cache.save(snapshot)
        let store = LeaderboardStore(
            repository: snapshot.repository,
            cache: cache,
            preference: RepositoryPreference(defaults: defaults),
            now: { now },
            calendar: calendar
        )
        let contentSize = NSSize(
            width: 560,
            height: LeaderboardView.preferredHeight(
                contributorCount: snapshot.contributors.count
            )
        )
        let screenshotView = ZStack {
            Color(nsColor: .windowBackgroundColor)
            LeaderboardView(
                store: store,
                onRepositoryPickerVisibilityChange: { _ in },
                onSelectRepository: { _ in },
                onDismiss: {}
            )
        }
        .frame(width: contentSize.width, height: contentSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .environment(\.colorScheme, .dark)

        let hostingView = NSHostingView(rootView: screenshotView)
        hostingView.frame = NSRect(origin: .zero, size: contentSize)
        hostingView.appearance = NSAppearance(named: .darkAqua)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.contentView = hostingView
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        hostingView.displayIfNeeded()

        let scale: CGFloat = 2
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(contentSize.width * scale),
            pixelsHigh: Int(contentSize.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw ScreenshotError.couldNotCreateBitmap
        }
        bitmap.size = contentSize
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let pngData = bitmap.representation(
            using: .png,
            properties: [.compressionFactor: 1]
        ) else {
            throw ScreenshotError.couldNotEncodePNG
        }

        try FileManager.default.createDirectory(
            at: request.outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try pngData.write(to: request.outputURL, options: .atomic)
    }
}

private extension ReadmeScreenshot {
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
