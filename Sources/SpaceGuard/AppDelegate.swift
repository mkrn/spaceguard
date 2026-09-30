import AppKit
import Combine
import SwiftUI
@preconcurrency import UserNotifications
import os

let log = Logger(subsystem: "io.github.mkrn.spaceguard", category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var timer: Timer?
    private var bag = Set<AnyCancellable>()
    private let store = Store.shared
    private var lastNotified: Date?
    private var lastLevel: DiskLevel = .ok

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil)
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        }

        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(width: PanelView.width, height: PanelView.height)
        popover.contentViewController = NSHostingController(rootView: PanelView(store: store, settings: store.settings))

        store.$available
            .combineLatest(store.settings.$showFreeInMenuBar, store.settings.$lowSpaceGB)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateButton() }
            .store(in: &bag)

        UNUserNotificationCenter.current().delegate = self
        store.refreshDisk()
        updateButton()
        Cleaner.shared.resumePurge()

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer?.tolerance = 15

        // Scan quietly in the background right away so the list is ready when the menu opens.
        store.scan(background: true) { [weak self] in
            MainActor.assumeIsolated { self?.checkLowSpace(afterScan: true) }
        }

        // Menu-bar apps have no window, so on the very first launch show where SpaceGuard lives.
        if !UserDefaults.standard.bool(forKey: "welcomed") {
            UserDefaults.standard.set(true, forKey: "welcomed")
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                self?.showPopover()
            }
        }
    }

    private func tick() {
        store.refreshDisk()
        checkLowSpace(afterScan: false)
    }

    private func checkLowSpace(afterScan: Bool) {
        let level = store.level
        defer { lastLevel = level }
        guard level != .ok else { return }
        let stale = store.lastScan.map { Date().timeIntervalSince($0) > 3600 } ?? true
        if !afterScan && stale && store.settings.autoScanWhenLow && !store.scanning {
            store.scan(background: true) { [weak self] in
                MainActor.assumeIsolated { self?.checkLowSpace(afterScan: true) }
            }
            return
        }
        let worsened = lastLevel == .ok || (level == .critical && lastLevel != .critical)
        let due = lastNotified.map { Date().timeIntervalSince($0) > 6 * 3600 } ?? true
        if store.settings.notify && (worsened || due) { notify(level) }
    }

    private func notify(_ level: DiskLevel) {
        lastNotified = Date()
        let available = store.available
        let recommended = store.bytes(of: store.recommendedIDs)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            log.notice("notification permission granted=\(granted, privacy: .public) error=\(String(describing: error), privacy: .public)")
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = level == .critical ? "Disk almost full: \(Fmt.bytes(available)) left" : "Disk space low: \(Fmt.bytes(available)) left"
            content.body = recommended > 0
                ? "SpaceGuard found \(Fmt.bytes(recommended)) of stale dev caches that are safe to clean. Click to review."
                : "Click to see which dev caches are taking space."
            content.sound = .default
            center.add(UNNotificationRequest(identifier: "low-space", content: content, trigger: nil)) { error in
                log.notice("low-space notification posted, error=\(String(describing: error), privacy: .public)")
            }
        }
    }

    private func updateButton() {
        guard let button = statusItem?.button else { return }
        let level = store.level
        let symbol = level == .ok ? "internaldrive" : "externaldrive.badge.exclamationmark"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "SpaceGuard")
            ?? NSImage(systemSymbolName: "internaldrive", accessibilityDescription: "SpaceGuard")
        image?.isTemplate = true
        button.image = image
        button.title = store.settings.showFreeInMenuBar && store.total > 0 ? " " + Fmt.compact(store.available) : ""
        button.contentTintColor = level == .critical ? .systemRed : level == .low ? .systemOrange : nil
        button.toolTip = "SpaceGuard: \(Fmt.bytes(store.available)) available"
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        store.refreshDisk()
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        let stale = store.lastScan.map { Date().timeIntervalSince($0) > 1800 } ?? true
        if stale && !store.scanning { store.scan(background: store.lastScan != nil) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in self.showPopover() }
        completionHandler()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
