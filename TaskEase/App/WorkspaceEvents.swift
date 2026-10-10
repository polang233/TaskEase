import AppKit
import Foundation

/// Typed messages deliver application changes on MainActor without an extra task hop.
@MainActor
final class WorkspaceEvents {
    private var tokens: [NotificationCenter.ObservationToken] = []

    init(onFocus: @escaping @MainActor () -> Void,
         onMembership: @escaping @MainActor (String?) -> Void,
         onSleep: @escaping @MainActor () -> Void,
         onWake: @escaping @MainActor () -> Void,
         onVisibility: @escaping @MainActor () -> Void) {
        let workspace = NSWorkspace.shared
        let center = workspace.notificationCenter
        tokens.append(center.addObserver(of: workspace, for: NSWorkspace.DidActivateApplicationMessage.self) { _ in onFocus() })
        tokens.append(center.addObserver(of: workspace, for: NSWorkspace.DidDeactivateApplicationMessage.self) { _ in onFocus() })
        tokens.append(center.addObserver(of: workspace, for: NSWorkspace.DidHideApplicationMessage.self) { _ in onFocus() })
        tokens.append(center.addObserver(of: workspace, for: NSWorkspace.DidUnhideApplicationMessage.self) { _ in onFocus() })
        tokens.append(center.addObserver(of: workspace, for: NSWorkspace.DidLaunchApplicationMessage.self) { message in
            onMembership(message.application.bundleIdentifier)
        })
        tokens.append(center.addObserver(of: workspace, for: NSWorkspace.DidTerminateApplicationMessage.self) { message in
            onMembership(message.application.bundleIdentifier)
        })
        tokens.append(center.addObserver(of: workspace, for: NSWorkspace.WillSleepMessage.self) { _ in onSleep() })
        tokens.append(center.addObserver(of: workspace, for: NSWorkspace.DidWakeMessage.self) { _ in onWake() })
        tokens.append(center.addObserver(of: workspace, for: NSWorkspace.ActiveSpaceDidChangeMessage.self) { _ in
            await onFocus()
        })
        tokens.append(NotificationCenter.default.addObserver(for: NSWindow.DidChangeOcclusionStateMessage.self) { _ in
            onVisibility()
        })
    }
}
