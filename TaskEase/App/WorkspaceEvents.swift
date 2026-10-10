import AppKit
import Foundation

/// 统一前台、应用成员、睡眠和窗口可见性事件，随系统版本选择通知 API。
@MainActor
final class WorkspaceEvents {
    private var modern: AnyObject?
    private var legacy: LegacyWorkspaceEvents?

    init(onFocus: @escaping @MainActor () -> Void,
         onMembership: @escaping @MainActor (String?) -> Void,
         onSleep: @escaping @MainActor () -> Void,
         onWake: @escaping @MainActor () -> Void,
         onVisibility: @escaping @MainActor () -> Void) {
        if #available(macOS 26.0, *) {
            modern = ModernWorkspaceEvents(onFocus: onFocus, onMembership: onMembership,
                                           onSleep: onSleep, onWake: onWake, onVisibility: onVisibility)
        } else {
            legacy = LegacyWorkspaceEvents(onFocus: onFocus, onMembership: onMembership,
                                           onSleep: onSleep, onWake: onWake, onVisibility: onVisibility)
        }
    }
}

/// 类型化通知直接在声明的 actor 上交付，令新系统的前台恢复更及时。
@available(macOS 26.0, *)
@MainActor
private final class ModernWorkspaceEvents {
    private var tokens: [NotificationCenter.ObservationToken] = []
    private var windowEvents: LegacyWorkspaceEvents?
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
        if #available(macOS 27.0, *) {
            tokens.append(NotificationCenter.default.addObserver(for: NSWindow.DidChangeOcclusionStateMessage.self) { _ in
                onVisibility()
            })
        } else {
            windowEvents = LegacyWorkspaceEvents(onVisibility: onVisibility)
        }

    }
}

/// 旧系统通过公开通知接收同一组事件；只向主 actor 传递可发送的值。
private final class LegacyWorkspaceEvents {
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    @MainActor init(onVisibility: @escaping @MainActor () -> Void) {
        observe(.default, NSWindow.didChangeOcclusionStateNotification) { _ in Task { @MainActor in onVisibility() } }
    }

    @MainActor init(onFocus: @escaping @MainActor () -> Void,
                    onMembership: @escaping @MainActor (String?) -> Void,
                    onSleep: @escaping @MainActor () -> Void,
                    onWake: @escaping @MainActor () -> Void,
                    onVisibility: @escaping @MainActor () -> Void) {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didDeactivateApplicationNotification,
                     NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification] {
            observe(center, name) { _ in Task { @MainActor in onFocus() } }
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observe(center, name) { notification in
                let id = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                Task { @MainActor in onMembership(id) }
            }
        }
        observe(center, NSWorkspace.willSleepNotification) { _ in Task { @MainActor in onSleep() } }
        observe(center, NSWorkspace.didWakeNotification) { _ in Task { @MainActor in onWake() } }
        observe(.default, NSWindow.didChangeOcclusionStateNotification) { _ in Task { @MainActor in onVisibility() } }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping @Sendable (Notification) -> Void) {
        observers.append((center, center.addObserver(forName: name, object: nil, queue: .main, using: action)))
    }

    deinit {
        for (center, token) in observers { center.removeObserver(token) }
    }
}
