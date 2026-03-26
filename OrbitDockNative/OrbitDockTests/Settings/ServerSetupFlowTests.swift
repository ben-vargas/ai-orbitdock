@testable import OrbitDock
import Testing

@MainActor
struct ServerSetupVisibilityTests {
  @Test func showsSetupWhenNotConfiguredAndNoConnectedRuntimes() {
    let shouldShow = AppWindowPlanner.shouldShowSetup(
      connectedRuntimeCount: 0,
      installState: .notConfigured
    )

    #expect(shouldShow)
  }

  @Test func hidesSetupWhenAnyRuntimeIsConnected() {
    let shouldShow = AppWindowPlanner.shouldShowSetup(
      connectedRuntimeCount: 1,
      installState: .notConfigured
    )

    #expect(!shouldShow)
  }

  @Test func hidesSetupWhenServerStateIsConfiguredButDisconnected() {
    let shouldShow = AppWindowPlanner.shouldShowSetup(
      connectedRuntimeCount: 0,
      installState: .installed
    )

    #expect(!shouldShow)
  }
}

#if os(macOS)
  private func forcedStateLabel(_ state: ServerInstallState?) -> String {
    guard let state else { return "nil" }
    switch state {
      case .notConfigured: return "notConfigured"
      case .running: return "running"
      case .installed: return "installed"
      case .remote: return "remote"
      case .unknown: return "unknown"
    }
  }

  @MainActor
  struct ServerManagerForcedStateParsingTests {
    @Test func parsesNotConfiguredAliases() {
      #expect(forcedStateLabel(ServerManager.parseForcedInstallState("not_configured")) == "notConfigured")
      #expect(forcedStateLabel(ServerManager.parseForcedInstallState("notconfigured")) == "notConfigured")
      #expect(forcedStateLabel(ServerManager.parseForcedInstallState("not-configured")) == "notConfigured")
      #expect(forcedStateLabel(ServerManager.parseForcedInstallState("  NOT_CONFIGURED  ")) == "notConfigured")
    }

    @Test func parsesKnownStates() {
      #expect(forcedStateLabel(ServerManager.parseForcedInstallState("running")) == "running")
      #expect(forcedStateLabel(ServerManager.parseForcedInstallState("installed")) == "installed")
      #expect(forcedStateLabel(ServerManager.parseForcedInstallState("remote")) == "remote")
      #expect(forcedStateLabel(ServerManager.parseForcedInstallState("unknown")) == "unknown")
    }

    @Test func returnsNilForInvalidInput() {
      #expect(forcedStateLabel(ServerManager.parseForcedInstallState(nil)) == "nil")
      #expect(forcedStateLabel(ServerManager.parseForcedInstallState("")) == "nil")
      #expect(forcedStateLabel(ServerManager.parseForcedInstallState("   ")) == "nil")
      #expect(forcedStateLabel(ServerManager.parseForcedInstallState("garbage")) == "nil")
    }

    @Test func installStateResolverUsesRemoteOnlyAfterHealthAndLaunchd() {
      #expect(
        ServerInstallStateResolver.resolve(
          isHealthy: true,
          launchdPlistExists: false,
          hasRemoteEndpoint: true
        ) == .running
      )
      #expect(
        ServerInstallStateResolver.resolve(
          isHealthy: false,
          launchdPlistExists: true,
          hasRemoteEndpoint: true
        ) == .installed
      )
      #expect(
        ServerInstallStateResolver.resolve(
          isHealthy: false,
          launchdPlistExists: false,
          hasRemoteEndpoint: true
        ) == .remote
      )
      #expect(
        ServerInstallStateResolver.resolve(
          isHealthy: false,
          launchdPlistExists: false,
          hasRemoteEndpoint: false
        ) == .notConfigured
      )
    }

    @Test func parsesBinaryVersionsFromCliOutput() {
      let stable = OrbitDockBinaryVersion.parse("orbitdock 0.5.0")
      let nightly = OrbitDockBinaryVersion.parse("orbitdock v0.5.0-nightly.20260326")

      #expect(stable?.major == 0)
      #expect(stable?.minor == 5)
      #expect(stable?.patch == 0)
      #expect(stable?.suffix == nil)
      #expect(nightly?.suffix == "nightly.20260326")
    }

    @Test func bundledServerSyncReplacesWhenBundleCoreVersionIsNewer() {
      let bundled = OrbitDockBinaryVersion.parse("orbitdock 0.5.0")
      let installed = OrbitDockBinaryVersion.parse("orbitdock 0.4.0")

      #expect(ServerManager.bundledServerSyncDecision(
        bundledVersion: bundled,
        installedVersion: installed
      ) == .replace)
    }

    @Test func bundledServerSyncReplacesWhenOnlyTheSameCoreBuildDiffers() {
      let bundled = OrbitDockBinaryVersion.parse("orbitdock 0.5.0-nightly.20260326")
      let installed = OrbitDockBinaryVersion.parse("orbitdock 0.5.0")

      #expect(ServerManager.bundledServerSyncDecision(
        bundledVersion: bundled,
        installedVersion: installed
      ) == .replace)
    }

    @Test func bundledServerSyncSkipsDowngradeWhenInstalledCoreVersionIsNewer() {
      let bundled = OrbitDockBinaryVersion.parse("orbitdock 0.5.0")
      let installed = OrbitDockBinaryVersion.parse("orbitdock 0.6.0")

      #expect(ServerManager.bundledServerSyncDecision(
        bundledVersion: bundled,
        installedVersion: installed
      ) == .skipDowngrade)
    }
  }
#endif
