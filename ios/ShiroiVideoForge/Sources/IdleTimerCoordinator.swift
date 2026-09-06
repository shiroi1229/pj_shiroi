import Foundation
import UIKit

/// App-wide sleep ownership: releasing a POC must not release an AI render's lease.
@MainActor
final class IdleTimerCoordinator {
    static let shared = IdleTimerCoordinator()
    private var owners: Set<UUID> = []
    private var foreground = true
    private var observers: [NSObjectProtocol] = []
    private init() {
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.foreground = false; self?.apply() }
            })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.foreground = true; self?.apply() }
            })
    }
    func setActive(owner: UUID, active: Bool) {
        if active { owners.insert(owner) } else { owners.remove(owner) }
        apply()
    }
    private func apply() {
        UIApplication.shared.isIdleTimerDisabled = foreground && !owners.isEmpty
    }
}
