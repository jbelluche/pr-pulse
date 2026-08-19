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
    nonisolated static let userArgument = DemoData.userArgument

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
        guard DemoData.isValidGitHubLogin(featuredLogin) else {
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
        DemoData.configuration(
            featuredLogin: featuredLogin,
            now: now,
            calendar: calendar
        ).snapshots[0]
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
        let demoConfiguration = DemoData.configuration(
            featuredLogin: request.featuredLogin,
            now: now,
            calendar: calendar
        )
        let store = LeaderboardStore(
            repository: snapshot.repository,
            now: { now },
            calendar: calendar,
            demoConfiguration: demoConfiguration
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
