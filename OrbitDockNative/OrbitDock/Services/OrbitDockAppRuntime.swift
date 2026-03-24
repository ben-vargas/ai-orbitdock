import Foundation
import SwiftUI

#if os(macOS)
  private struct ServerManagerEnvironmentKey: EnvironmentKey {
    static let defaultValue = ServerManager.missingEnvironmentDefault()
  }

  extension EnvironmentValues {
    var serverManager: ServerManager {
      get { self[ServerManagerEnvironmentKey.self] }
      set { self[ServerManagerEnvironmentKey.self] = newValue }
    }
  }
#endif

@Observable
@MainActor
final class OrbitDockAppRuntime {
  let runtimeRegistry: ServerRuntimeRegistry
  let externalNavigationCenter: AppExternalNavigationCenter
  let notificationCoordinator: NotificationCoordinator
  let focusTracker: AppFocusTracker
  let usageServiceRegistry: UsageServiceRegistry
  let startupCoordinator: ClientStartupCoordinator
  let demoExperience: DemoModeExperience
  var isDemoModeEnabled = false
  #if os(macOS)
    let serverManager: ServerManager
  #endif

  #if os(macOS)
    init() {
      let runtimeRegistry = ServerRuntimeRegistry()
      self.runtimeRegistry = runtimeRegistry
      self.externalNavigationCenter = AppExternalNavigationCenter()
      self.notificationCoordinator = NotificationCoordinator()
      self.focusTracker = AppFocusTracker()
      self.usageServiceRegistry = UsageServiceRegistry(runtimeRegistry: runtimeRegistry)
      self.demoExperience = DemoModeExperience()
      self.serverManager = .live()
      self.startupCoordinator = ClientStartupCoordinator(
        runtimeRegistry: runtimeRegistry,
        shouldConnectServer: AppRuntimeMode.current.shouldConnectServer
      )
    }
  #else
    init() {
      let runtimeRegistry = ServerRuntimeRegistry()
      self.runtimeRegistry = runtimeRegistry
      self.externalNavigationCenter = AppExternalNavigationCenter()
      self.notificationCoordinator = NotificationCoordinator()
      self.focusTracker = AppFocusTracker()
      self.usageServiceRegistry = UsageServiceRegistry(runtimeRegistry: runtimeRegistry)
      self.demoExperience = DemoModeExperience()
      self.startupCoordinator = ClientStartupCoordinator(
        runtimeRegistry: runtimeRegistry,
        shouldConnectServer: AppRuntimeMode.current.shouldConnectServer
      )
    }
  #endif

  func startIfNeeded() async {
    notificationCoordinator.startIfNeeded()
    focusTracker.startObserving()
    await startupCoordinator.startIfNeeded()
  }

  func enterDemoMode() {
    isDemoModeEnabled = true
  }

  func exitDemoMode() {
    isDemoModeEnabled = false
  }
}
