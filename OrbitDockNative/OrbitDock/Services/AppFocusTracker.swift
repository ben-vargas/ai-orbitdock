import Foundation
import SwiftUI

@Observable
@MainActor
final class AppFocusTracker {
  private(set) var isAppActive: Bool = true

  #if os(macOS)
    @ObservationIgnored private var activationObserver: Any?
    @ObservationIgnored private var deactivationObserver: Any?

    func startObserving() {
      let center = NotificationCenter.default
      activationObserver = center.addObserver(
        forName: NSApplication.didBecomeActiveNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        guard let self else { return }
        Task { @MainActor [weak self] in
          self?.isAppActive = true
        }
      }
      deactivationObserver = center.addObserver(
        forName: NSApplication.didResignActiveNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        guard let self else { return }
        Task { @MainActor [weak self] in
          self?.isAppActive = false
        }
      }
    }
  #else
    func startObserving() {}

    func update(scenePhase: ScenePhase) {
      isAppActive = scenePhase == .active
    }
  #endif
}
