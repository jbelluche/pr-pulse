import AppKit
import SwiftUI

enum StatusItemInteraction: Equatable {
    case togglePopover
    case showQuitMenu
}

struct RefreshTaskGeneration {
    private var value = 0

    mutating func begin() -> Int {
        value += 1
        return value
    }

    mutating func invalidate() {
        value += 1
    }

    func owns(_ generation: Int) -> Bool {
        generation == value
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    nonisolated static let refreshInterval: TimeInterval = 30
    nonisolated static let quitMenuTitle = "Quit PR Pulse"

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var store: LeaderboardStore!
    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var refreshTaskGeneration = RefreshTaskGeneration()
    private var repositoryTask: Task<Void, Never>?
    private var outsideClickMonitor: Any?
    private var isChoosingRepository = false
    private lazy var contextMenu: NSMenu = {
        let menu = NSMenu()
        let quitItem = NSMenuItem(
            title: Self.quitMenuTitle,
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            if let request = try ReadmeScreenshot.request(
                arguments: ProcessInfo.processInfo.arguments
            ) {
                NSApp.setActivationPolicy(.accessory)
                try ReadmeScreenshot.generate(request)
                print("Generated \(request.outputURL.path)")
                NSApp.terminate(nil)
                return
            }
        } catch {
            FileHandle.standardError.write(
                Data("Could not generate README screenshot: \(error.localizedDescription)\n".utf8)
            )
            exit(EXIT_FAILURE)
        }

        NSApp.setActivationPolicy(.accessory)

        let preference = RepositoryPreference.live
        let cache = SnapshotCache.live
        let initialRepository = preference.load() ?? cache.lastRepository()
        store = LeaderboardStore(
            repository: initialRepository,
            cache: cache,
            preference: preference,
            onPresentationChange: { [weak self] snapshot, hasError in
                self?.updatePresentation(snapshot: snapshot, hasError: hasError)
            }
        )

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "PRPulseStatusItem"
        if let button = statusItem.button {
            let image = NSImage(
                systemSymbolName: "waveform.path.ecg",
                accessibilityDescription: "PR Pulse"
            )
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "PR Pulse month-to-date leaderboard"
            let accessibilityTitle = "PR Pulse, \(store.snapshot?.totalCount ?? 0) pull requests"
            button.setAccessibilityLabel(accessibilityTitle)
            button.setAccessibilityTitle(accessibilityTitle)
        }

        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        updatePopoverSize(for: store.snapshot, hasError: false)
        popover.contentViewController = NSHostingController(
            rootView: LeaderboardView(
                store: store,
                onRepositoryPickerVisibilityChange: { [weak self] isVisible in
                    self?.setRepositoryPickerVisible(isVisible)
                },
                onSelectRepository: { [weak self] repository in
                    self?.selectRepository(repository)
                },
                onDismiss: { [weak self] in self?.closePopover() }
            )
        )

        refreshTimer = Timer.scheduledTimer(
            timeInterval: Self.refreshInterval,
            target: self,
            selector: #selector(refreshFromTimer),
            userInfo: nil,
            repeats: true
        )
        startRepositoryLoad()
        startRefresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTask?.cancel()
        repositoryTask?.cancel()
        removeOutsideClickMonitor()
    }

    func popoverDidClose(_ notification: Notification) {
        removeOutsideClickMonitor()
    }

    nonisolated static func interaction(
        for eventType: NSEvent.EventType?,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> StatusItemInteraction {
        if eventType == .rightMouseUp
            || (eventType == .leftMouseUp && modifierFlags.contains(.control)) {
            return .showQuitMenu
        }
        return .togglePopover
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        switch Self.interaction(
            for: event?.type,
            modifierFlags: event?.modifierFlags ?? []
        ) {
        case .togglePopover:
            togglePopover()
        case .showQuitMenu:
            closePopover()
            contextMenu.popUp(
                positioning: nil,
                at: NSPoint(x: sender.bounds.minX, y: sender.bounds.minY),
                in: sender
            )
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            closePopover()
            return
        }

        // Show cached content before starting any network work.
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        installOutsideClickMonitor()
        startRefresh()
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    @objc private func refreshFromTimer() {
        startRefresh()
    }

    private func startRefresh() {
        guard store.repository != nil, refreshTask == nil else { return }
        let generation = refreshTaskGeneration.begin()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await store.refresh()
            guard refreshTaskGeneration.owns(generation) else { return }
            refreshTask = nil
        }
    }

    private func startRepositoryLoad() {
        guard repositoryTask == nil else { return }
        repositoryTask = Task { [weak self] in
            guard let self else { return }
            await store.loadRepositories()
            repositoryTask = nil
        }
    }

    private func selectRepository(_ repository: RepositoryOption) {
        guard store.selectRepository(repository.fullName) else {
            setRepositoryPickerVisible(false)
            return
        }

        refreshTask?.cancel()
        refreshTask = nil
        refreshTaskGeneration.invalidate()
        setRepositoryPickerVisible(false)
        startRefresh()
    }

    private func setRepositoryPickerVisible(_ isVisible: Bool) {
        isChoosingRepository = isVisible
        if isVisible, store.repositories.isEmpty {
            startRepositoryLoad()
        }
        updatePopoverSize(for: store.snapshot, hasError: store.lastError != nil)
    }

    private func updatePresentation(snapshot: LeaderboardSnapshot?, hasError: Bool) {
        let accessibilityTitle = "PR Pulse, \(snapshot?.totalCount ?? 0) pull requests"
        statusItem.button?.setAccessibilityLabel(accessibilityTitle)
        statusItem.button?.setAccessibilityTitle(accessibilityTitle)
        updatePopoverSize(for: snapshot, hasError: hasError)
    }

    private func updatePopoverSize(for snapshot: LeaderboardSnapshot?, hasError: Bool) {
        popover.contentSize = NSSize(
            width: 560,
            height: isChoosingRepository
                ? LeaderboardView.repositoryPickerHeight
                : LeaderboardView.preferredHeight(
                    contributorCount: snapshot?.contributors.count,
                    hasError: hasError
                )
        )
    }

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closePopover()
            }
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        removeOutsideClickMonitor()
    }

    private func removeOutsideClickMonitor() {
        guard let outsideClickMonitor else { return }
        NSEvent.removeMonitor(outsideClickMonitor)
        self.outsideClickMonitor = nil
    }
}
