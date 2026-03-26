//
//  ServerManager.swift
//  OrbitDock
//
//  Thin CLI wrapper around `orbitdock` subcommands.
//  Detects install state, shells out for init/install/start/stop.
//  NO embedded process management — the server runs via launchd or manually.
//

import Combine
import Foundation
import os.log

enum ServerInstallState: Equatable {
  case unknown // Haven't checked yet
  case notConfigured // No server binary found, no remote endpoint
  case running // Health check passes (don't care how it started)
  case installed // Binary + launchd plist exist, but not responding
  case remote // Remote endpoint configured
}

struct OrbitDockBinaryVersion: Equatable, Sendable {
  let major: Int
  let minor: Int
  let patch: Int
  let suffix: String?

  var core: (Int, Int, Int) {
    (major, minor, patch)
  }

  static func parse(_ rawValue: String) -> OrbitDockBinaryVersion? {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    guard let token = trimmed
      .split(whereSeparator: \.isWhitespace)
      .last
      .map(String.init)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    else {
      return nil
    }
    guard !token.isEmpty else { return nil }

    let normalized = token.hasPrefix("v") ? String(token.dropFirst()) : token
    let components = normalized.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
    let core = components[0].split(separator: ".", omittingEmptySubsequences: false)
    guard core.count == 3,
          let major = Int(core[0]),
          let minor = Int(core[1]),
          let patch = Int(core[2])
    else {
      return nil
    }

    let suffix = components.count > 1 ? String(components[1]) : nil
    return OrbitDockBinaryVersion(
      major: major,
      minor: minor,
      patch: patch,
      suffix: suffix?.isEmpty == true ? nil : suffix
    )
  }
}

enum BundledServerSyncDecision: Equatable {
  case upToDate
  case replace
  case skipDowngrade
}

enum ServerInstallStateResolver {
  static func resolve(
    isHealthy: Bool,
    launchdPlistExists: Bool,
    hasRemoteEndpoint: Bool
  ) -> ServerInstallState {
    if isHealthy {
      return .running
    }
    if launchdPlistExists {
      return .installed
    }
    if hasRemoteEndpoint {
      return .remote
    }
    return .notConfigured
  }
}

#if os(macOS)
  @MainActor
  final class ServerManager: ObservableObject {
    private nonisolated static let forcedInstallStateEnvKey = "ORBITDOCK_FORCE_SERVER_INSTALL_STATE"
    private nonisolated static let appManagedLocalInstallKey = "orbitdock.server.app-managed-local-install"
    private let logger = Logger(subsystem: "com.orbitdock", category: "server-manager")
    private let endpointSettings: ServerEndpointSettingsClient

    static func live(endpointSettings: ServerEndpointSettingsClient? = nil) -> ServerManager {
      ServerManager(endpointSettings: endpointSettings)
    }

    static func missingEnvironmentDefault(
      file: StaticString = #fileID,
      line: UInt = #line
    ) -> ServerManager {
      ServerManager(previewInstallState: .unknown)
    }

    @Published private(set) var installState: ServerInstallState = .unknown
    @Published var isInstalling = false
    @Published var installError: String?

    private let serverPort = 4_000
    private let serviceName = "com.orbitdock.server"

    private lazy var healthCheckSession: URLSession = {
      let config = URLSessionConfiguration.ephemeral
      config.timeoutIntervalForRequest = 2
      config.timeoutIntervalForResource = 2
      config.waitsForConnectivity = false
      return URLSession(configuration: config)
    }()

    private init(endpointSettings: ServerEndpointSettingsClient? = nil) {
      self.endpointSettings = endpointSettings ?? .live()
    }

    init(
      previewInstallState: ServerInstallState,
      endpointSettings: ServerEndpointSettingsClient? = nil,
      isInstalling: Bool = false,
      installError: String? = nil
    ) {
      self.endpointSettings = endpointSettings ?? .live()
      self.installState = previewInstallState
      self.isInstalling = isInstalling
      self.installError = installError
    }

    // MARK: - State Detection

    /// Refresh install state. Priority order:
    /// 1. Health check → .running
    /// 2. Launchd plist exists → .installed (stopped)
    /// 3. Remote endpoint configured → .remote
    /// 4. Otherwise → .notConfigured
    func refreshState() async {
      if let forcedState = Self.forcedInstallStateFromEnvironment() {
        installState = forcedState
        return
      }

      installState = await ServerInstallStateResolver.resolve(
        isHealthy: checkHealth(),
        launchdPlistExists: launchdPlistExists(),
        hasRemoteEndpoint: endpointSettings.hasRemoteEndpoint()
      )
    }

    nonisolated static func parseForcedInstallState(_ rawValue: String?) -> ServerInstallState? {
      guard let raw = rawValue?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased(),
        !raw.isEmpty
      else {
        return nil
      }

      switch raw {
        case "not_configured", "notconfigured", "not-configured":
          return .notConfigured
        case "running":
          return .running
        case "installed":
          return .installed
        case "remote":
          return .remote
        case "unknown":
          return .unknown
        default:
          return nil
      }
    }

    private nonisolated static func forcedInstallStateFromEnvironment() -> ServerInstallState? {
      parseForcedInstallState(ProcessInfo.processInfo.environment[forcedInstallStateEnvKey])
    }

    // MARK: - Binary Discovery

    /// Find the orbitdock binary. Checks:
    /// 1. Bundle Resources (bundled with app)
    /// 2. ORBITDOCK_SERVER_PATH env var
    /// 3. ~/.orbitdock/bin/ (installed by us)
    /// 4. PATH (brew, cargo install, etc.)
    func findServerBinary() -> String? {
      // 1. Bundle Resources
      if let bundlePath = Bundle.main.url(forResource: "orbitdock", withExtension: nil) {
        if FileManager.default.fileExists(atPath: bundlePath.path) {
          return bundlePath.path
        }
      }

      // 2. Environment override
      if let envPath = ProcessInfo.processInfo.environment["ORBITDOCK_SERVER_PATH"],
         FileManager.default.fileExists(atPath: envPath)
      {
        return envPath
      }

      // 3. Installed location
      let installedPath = PlatformPaths.orbitDockBinDirectory
        .appendingPathComponent("orbitdock").path
      if FileManager.default.fileExists(atPath: installedPath) {
        return installedPath
      }

      // 4. Search PATH
      let shellPath = Self.resolveLoginShellPath()
        ?? ProcessInfo.processInfo.environment["PATH"]
        ?? ""
      let pathDirs = shellPath.split(separator: ":")
      for dir in pathDirs {
        let path = "\(dir)/orbitdock"
        if FileManager.default.fileExists(atPath: path) {
          return path
        }
      }

      return nil
    }

    // MARK: - Install

    /// Full setup sequence:
    /// 1. Find binary
    /// 2. Copy to ~/.orbitdock/bin/ (if from bundle)
    /// 3. Run `orbitdock ensure-path`
    /// 4. Run `orbitdock init`
    /// 5. Run `orbitdock install-hooks`
    /// 6. Run `orbitdock install-service --enable`
    /// 7. Wait for health check
    /// 8. Refresh state
    func install() async throws {
      isInstalling = true
      installError = nil

      defer { isInstalling = false }

      guard let sourcePath = findServerBinary() else {
        let msg = "Could not find orbitdock binary"
        installError = msg
        throw ServerInstallError.binaryNotFound
      }

      // If the binary is from the bundle, copy it to ~/.orbitdock/bin/
      let binaryPath: String
      if sourcePath.contains(".app/Contents/Resources") {
        let binDir = PlatformPaths.orbitDockBinDirectory
        PlatformPaths.ensureDirectory(binDir)
        let destPath = binDir.appendingPathComponent("orbitdock").path
        do {
          try installBundledBinary(from: sourcePath, to: destPath)
          binaryPath = destPath
        } catch {
          let msg = "Failed to copy binary: \(error.localizedDescription)"
          installError = msg
          throw ServerInstallError.copyFailed(error)
        }
      } else {
        binaryPath = sourcePath
      }

      // Ensure CLI binary directory is persisted on PATH.
      do {
        _ = try await runCLI(binaryPath, arguments: ["ensure-path"])
        logger.info("orbitdock ensure-path completed")
      } catch {
        logger.warning("orbitdock ensure-path failed: \(error.localizedDescription)")
      }

      // Run init
      do {
        _ = try await runCLI(binaryPath, arguments: ["init"])
        logger.info("orbitdock init completed")
      } catch {
        let msg = "init failed: \(error.localizedDescription)"
        installError = msg
        throw error
      }

      // Install hooks
      do {
        _ = try await runCLI(binaryPath, arguments: ["install-hooks"])
        logger.info("orbitdock install-hooks completed")
      } catch {
        let msg = "install-hooks failed: \(error.localizedDescription)"
        installError = msg
        throw error
      }

      // Install + enable launchd service
      do {
        _ = try await runCLI(binaryPath, arguments: ["install-service", "--enable"])
        logger.info("orbitdock install-service --enable completed")
      } catch {
        let msg = "install-service failed: \(error.localizedDescription)"
        installError = msg
        throw error
      }

      // Wait for server to come up
      let ready = await waitForHealth(maxAttempts: 15)
      if !ready {
        let msg = "Server installed but not responding"
        installError = msg
        throw ServerInstallError.healthCheckFailed
      }

      await refreshState()
      markAppManagedLocalInstall()
      logger.info("Server installation complete")
    }

    // MARK: - Uninstall

    func uninstall() async throws {
      let plistPath = launchdPlistPath()

      // Unload service
      if FileManager.default.fileExists(atPath: plistPath) {
        do {
          try await runShell("/bin/launchctl", arguments: ["unload", plistPath])
        } catch {
          logger.warning("launchctl unload failed (may already be unloaded): \(error.localizedDescription)")
        }

        // Remove plist
        try? FileManager.default.removeItem(atPath: plistPath)
        logger.info("Removed launchd plist")
      }

      await refreshState()
      clearAppManagedLocalInstallMarker()
    }

    // MARK: - Service Control

    func startService() async throws {
      try await runShell("/bin/launchctl", arguments: ["start", serviceName])
      // Wait briefly for startup
      let ready = await waitForHealth(maxAttempts: 10)
      if ready {
        installState = .running
      }
    }

    func stopService() async throws {
      try await runShell("/bin/launchctl", arguments: ["stop", serviceName])
      // Give the process time to terminate
      try? await Task.sleep(for: .milliseconds(500))
      await refreshState()
    }

    func restartService() async throws {
      try await stopService()
      try await startService()
    }

    func syncBundledServerIfNeeded() async {
      guard let bundledBinaryPath = bundledServerBinaryPath() else { return }

      let installedBinaryPath = installedServerBinaryPath()
      guard FileManager.default.fileExists(atPath: installedBinaryPath) else { return }
      guard shouldManageLocalInstalledServer() else { return }

      let bundledVersionOutput: String
      let installedVersionOutput: String
      do {
        bundledVersionOutput = try await runCLI(bundledBinaryPath, arguments: ["--version"])
        installedVersionOutput = try await runCLI(installedBinaryPath, arguments: ["--version"])
      } catch {
        logger.warning("Skipping bundled server sync; version probe failed: \(error.localizedDescription)")
        return
      }

      let bundledVersion = OrbitDockBinaryVersion.parse(bundledVersionOutput)
      let installedVersion = OrbitDockBinaryVersion.parse(installedVersionOutput)
      let decision = Self.bundledServerSyncDecision(
        bundledVersion: bundledVersion,
        installedVersion: installedVersion
      )

      guard decision == .replace else {
        if decision == .skipDowngrade {
          logger.info("Skipping bundled server sync because the installed server is newer")
        }
        return
      }

      do {
        try await upgradeInstalledLocalServer(
          bundledBinaryPath: bundledBinaryPath,
          installedBinaryPath: installedBinaryPath,
          bundledVersionOutput: bundledVersionOutput,
          installedVersionOutput: installedVersionOutput
        )
        await refreshState()
      } catch {
        logger.error("Bundled server sync failed: \(error.localizedDescription)")
      }
    }

    // MARK: - Health Check

    private func checkHealth() async -> Bool {
      guard let url = URL(string: "http://127.0.0.1:\(serverPort)/health") else {
        return false
      }

      do {
        let (_, response) = try await healthCheckSession.data(from: url)
        if let httpResponse = response as? HTTPURLResponse {
          return httpResponse.statusCode == 200
        }
        return false
      } catch {
        return false
      }
    }

    /// Wait for server to become healthy with exponential backoff.
    func waitForHealth(maxAttempts: Int = 10) async -> Bool {
      for attempt in 1 ... maxAttempts {
        if await checkHealth() {
          return true
        }
        if attempt < maxAttempts {
          let backoffMs = min(250 * Int(pow(2.0, Double(attempt - 1))), 2_000)
          try? await Task.sleep(for: .milliseconds(backoffMs))
        }
      }
      return false
    }

    // MARK: - Helpers

    private func launchdPlistPath() -> String {
      let home = FileManager.default.homeDirectoryForCurrentUser.path
      return "\(home)/Library/LaunchAgents/\(serviceName).plist"
    }

    private func launchdPlistExists() -> Bool {
      FileManager.default.fileExists(atPath: launchdPlistPath())
    }

    private func bundledServerBinaryPath() -> String? {
      guard let bundlePath = Bundle.main.url(forResource: "orbitdock", withExtension: nil),
            FileManager.default.fileExists(atPath: bundlePath.path)
      else {
        return nil
      }
      return bundlePath.path
    }

    private func installedServerBinaryPath() -> String {
      PlatformPaths.orbitDockBinDirectory
        .appendingPathComponent("orbitdock").path
    }

    private func installedServerBackupPath() -> String {
      PlatformPaths.orbitDockBinDirectory
        .appendingPathComponent("orbitdock.backup").path
    }

    private func shouldManageLocalInstalledServer() -> Bool {
      if UserDefaults.standard.bool(forKey: Self.appManagedLocalInstallKey) {
        return true
      }

      // Older app-installed setups won't have the marker yet. If the launchd service
      // exists and we still have a local managed endpoint configured, treat it as an
      // app-managed install and migrate it onto the safer update path.
      return launchdPlistExists() && endpointSettings.endpoints().contains(where: \.isLocalManaged)
    }

    private func markAppManagedLocalInstall() {
      UserDefaults.standard.set(true, forKey: Self.appManagedLocalInstallKey)
    }

    private func clearAppManagedLocalInstallMarker() {
      UserDefaults.standard.removeObject(forKey: Self.appManagedLocalInstallKey)
    }

    private func installBundledBinary(from sourcePath: String, to destinationPath: String) throws {
      let fileManager = FileManager.default
      let binDir = PlatformPaths.orbitDockBinDirectory
      PlatformPaths.ensureDirectory(binDir)

      let staleInstalledPath = binDir.appendingPathComponent("orbitdock-server").path
      if fileManager.fileExists(atPath: destinationPath) {
        try fileManager.removeItem(atPath: destinationPath)
      }
      if fileManager.fileExists(atPath: staleInstalledPath) {
        try fileManager.removeItem(atPath: staleInstalledPath)
      }

      try fileManager.copyItem(atPath: sourcePath, toPath: destinationPath)
      try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationPath)

      // Quarantine tags propagate from the app bundle copy and will prevent launchd
      // from starting the service unless we clear them here.
      removexattr(destinationPath, "com.apple.quarantine", 0)
      logger.info("Installed bundled server binary at \(destinationPath)")
    }

    private func upgradeInstalledLocalServer(
      bundledBinaryPath: String,
      installedBinaryPath: String,
      bundledVersionOutput: String,
      installedVersionOutput: String
    ) async throws {
      let backupPath = installedServerBackupPath()
      let fileManager = FileManager.default

      if fileManager.fileExists(atPath: backupPath) {
        try? fileManager.removeItem(atPath: backupPath)
      }
      try fileManager.copyItem(atPath: installedBinaryPath, toPath: backupPath)

      do {
        try installBundledBinary(from: bundledBinaryPath, to: installedBinaryPath)

        do {
          _ = try await runCLI(installedBinaryPath, arguments: ["ensure-path"])
        } catch {
          logger.warning("Bundled server upgrade ensure-path failed: \(error.localizedDescription)")
        }

        if launchdPlistExists() {
          _ = try await runCLI(installedBinaryPath, arguments: ["install-service", "--enable"])
          let ready = await waitForHealth(maxAttempts: 15)
          guard ready else {
            throw ServerInstallError.healthCheckFailed
          }
        }

        markAppManagedLocalInstall()
        logger.info(
          "Upgraded bundled server from \(installedVersionOutput.trimmingCharacters(in: .whitespacesAndNewlines)) to \(bundledVersionOutput.trimmingCharacters(in: .whitespacesAndNewlines))"
        )
        try? fileManager.removeItem(atPath: backupPath)
      } catch {
        logger.error("Bundled server upgrade failed; restoring previous binary")
        try? installBundledBinary(from: backupPath, to: installedBinaryPath)

        if launchdPlistExists() {
          do {
            _ = try await runCLI(installedBinaryPath, arguments: ["install-service", "--enable"])
          } catch {
            logger
              .error(
                "Failed to restore previous local server service after upgrade error: \(error.localizedDescription)"
              )
          }
        }

        try? fileManager.removeItem(atPath: backupPath)
        throw error
      }
    }

    /// Run the orbitdock CLI binary with arguments.
    private func runCLI(_ binaryPath: String, arguments: [String]) async throws -> String {
      try await runShell(binaryPath, arguments: arguments)
    }

    /// Run an arbitrary command, capturing stdout/stderr. Throws on non-zero exit.
    @discardableResult
    private func runShell(_ executablePath: String, arguments: [String]) async throws -> String {
      try await withCheckedThrowingContinuation { continuation in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        // Inherit login shell PATH so the server binary can find dependencies
        var env = ProcessInfo.processInfo.environment
        if let shellPath = Self.resolveLoginShellPath() {
          env["PATH"] = shellPath
        }
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        process.terminationHandler = { proc in
          let outData = stdout.fileHandleForReading.readDataToEndOfFile()
          let errData = stderr.fileHandleForReading.readDataToEndOfFile()
          let outStr = String(data: outData, encoding: .utf8) ?? ""
          let errStr = String(data: errData, encoding: .utf8) ?? ""

          if proc.terminationStatus == 0 {
            continuation.resume(returning: outStr)
          } else {
            let msg = errStr.isEmpty ? "Exit code \(proc.terminationStatus)" : errStr
              .trimmingCharacters(in: .whitespacesAndNewlines)
            continuation.resume(throwing: ServerInstallError.commandFailed(msg))
          }
        }

        do {
          try process.run()
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }

    /// Resolve the user's full PATH from their login shell.
    /// macOS GUI apps have a minimal PATH that misses nvm, homebrew, etc.
    private nonisolated static func resolveLoginShellPath() -> String? {
      let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
      let proc = Process()
      proc.executableURL = URL(fileURLWithPath: shell)
      proc.arguments = ["-i", "-l", "-c", "echo $PATH"]
      let pipe = Pipe()
      proc.standardOutput = pipe
      proc.standardError = FileHandle.nullDevice

      do {
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let path, !path.isEmpty {
          return path
        }
      } catch {
        // Fall through
      }

      return nil
    }

    static func bundledServerSyncDecision(
      bundledVersion: OrbitDockBinaryVersion?,
      installedVersion: OrbitDockBinaryVersion?
    ) -> BundledServerSyncDecision {
      guard let bundledVersion, let installedVersion else {
        return .replace
      }

      if bundledVersion.core > installedVersion.core {
        return .replace
      }
      if bundledVersion.core < installedVersion.core {
        return .skipDowngrade
      }

      if bundledVersion != installedVersion {
        return .replace
      }

      return .upToDate
    }
  }

  // MARK: - Errors

  enum ServerInstallError: LocalizedError {
    case binaryNotFound
    case copyFailed(Error)
    case commandFailed(String)
    case healthCheckFailed

    var errorDescription: String? {
      switch self {
        case .binaryNotFound:
          "Could not find orbitdock binary"
        case let .copyFailed(err):
          "Failed to copy binary: \(err.localizedDescription)"
        case let .commandFailed(msg):
          msg
        case .healthCheckFailed:
          "Server installed but not responding to health checks"
      }
    }
  }

#else

  @MainActor
  final class ServerManager: ObservableObject {
    static let shared = ServerManager()
    private let endpointSettings: ServerEndpointSettingsClient

    static func live(endpointSettings: ServerEndpointSettingsClient? = nil) -> ServerManager {
      ServerManager(endpointSettings: endpointSettings)
    }

    @Published private(set) var installState: ServerInstallState = .notConfigured
    @Published var isInstalling = false
    @Published var installError: String?

    private init(endpointSettings: ServerEndpointSettingsClient? = nil) {
      self.endpointSettings = endpointSettings ?? .live()
    }

    init(
      previewInstallState: ServerInstallState,
      endpointSettings: ServerEndpointSettingsClient? = nil,
      isInstalling: Bool = false,
      installError: String? = nil
    ) {
      self.endpointSettings = endpointSettings ?? .live()
      self.installState = previewInstallState
      self.isInstalling = isInstalling
      self.installError = installError
    }

    func refreshState() async {
      installState = ServerInstallStateResolver.resolve(
        isHealthy: false,
        launchdPlistExists: false,
        hasRemoteEndpoint: endpointSettings.hasRemoteEndpoint()
      )
    }

    func findServerBinary() -> String? {
      nil
    }
  }

#endif
