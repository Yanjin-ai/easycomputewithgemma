import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let model: MenuBarModel
    private let serviceManager: ServiceManager
    private let modelManager: ModelDownloadManager
    private var cancellables = Set<AnyCancellable>()
    private var animationTimer: Timer?
    private var rotation: CGFloat = 0

    init(
        model: MenuBarModel,
        serviceManager: ServiceManager,
        modelManager: ModelDownloadManager
    ) {
        self.model = model
        self.serviceManager = serviceManager
        self.modelManager = modelManager
        self.statusItem = NSStatusBar.system.statusItem(withLength: 30)
        self.popover = NSPopover()

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 430)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(model)
                .environmentObject(serviceManager)
                .environmentObject(modelManager)
        )

        configureButton()
        observeModel()
    }

    private func configureButton() {
        guard let button = statusItem.button else {
            return
        }

        button.image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "Gemma")
            ?? NSImage(systemSymbolName: "cpu", accessibilityDescription: "Gemma")
        button.imagePosition = .imageOnly
        button.action = #selector(togglePopover(_:))
        button.target = self
        button.contentTintColor = .systemGreen
    }

    private func observeModel() {
        model.$tasks
            .receive(on: RunLoop.main)
            .sink { [weak self] tasks in
                self?.updateIcon(for: tasks)
            }
            .store(in: &cancellables)
    }

    private func updateIcon(for tasks: [GemmaTask]) {
        guard let button = statusItem.button else {
            return
        }

        let state = StatusBarState(tasks: tasks)
        button.image = NSImage(systemSymbolName: state.symbolName, accessibilityDescription: state.accessibilityDescription)
        button.contentTintColor = state.tintColor

        if state.isAnimated {
            startAnimation()
        } else {
            stopAnimation()
        }
    }

    private func startAnimation() {
        guard animationTimer == nil,
              let button = statusItem.button else {
            return
        }

        button.wantsLayer = true
        animationTimer = Timer.scheduledTimer(
            timeInterval: 0.08,
            target: self,
            selector: #selector(advanceAnimation),
            userInfo: nil,
            repeats: true
        )
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        rotation = 0
        statusItem.button?.layer?.setAffineTransform(CGAffineTransform.identity)
    }

    @objc private func advanceAnimation() {
        rotation += 0.18
        statusItem.button?.layer?.setAffineTransform(CGAffineTransform(rotationAngle: rotation))
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

private struct StatusBarState {
    let symbolName: String
    let tintColor: NSColor
    let accessibilityDescription: String
    let isAnimated: Bool

    init(tasks: [GemmaTask]) {
        let states = Set(tasks.map(\.currentState))

        if states.contains("failed") {
            symbolName = "xmark.circle"
            tintColor = .systemRed
            accessibilityDescription = "Gemma tasks failed"
            isAnimated = false
        } else if states.contains("running") {
            symbolName = "arrow.triangle.2.circlepath"
            tintColor = .systemBlue
            accessibilityDescription = "Gemma tasks running"
            isAnimated = true
        } else if !states.isDisjoint(with: ["pending", "routing", "scheduled"]) {
            symbolName = "exclamationmark.triangle"
            tintColor = .systemOrange
            accessibilityDescription = "Gemma tasks waiting"
            isAnimated = false
        } else {
            symbolName = "checkmark.circle"
            tintColor = .systemGreen
            accessibilityDescription = "Gemma tasks complete"
            isAnimated = false
        }
    }
}
