import Foundation
@testable import OrbitDock
import Testing

struct ServerCompatibilityContractsTests {
  @Test func helloAcceptsCompatibleServerVerdict() throws {
    let hello = ServerHelloMetadata(
      serverVersion: OrbitDockProtocol.releaseVersion,
      compatibility: ServerCompatibilityStatus(
        compatible: true,
        serverCompatibility: OrbitDockProtocol.compatibility,
        reason: nil,
        message: nil
      ),
      capabilities: ["dashboard_projection_v1"]
    )

    #expect(throws: Never.self) {
      try hello.validateCompatibility()
    }
  }

  @Test func helloRejectsIncompatibleServerVerdict() throws {
    let hello = ServerHelloMetadata(
      serverVersion: OrbitDockProtocol.releaseVersion,
      compatibility: ServerCompatibilityStatus(
        compatible: false,
        serverCompatibility: "legacy_contract",
        reason: "upgrade_app",
        message: "Update OrbitDock to a build compatible with server 0.4.0."
      ),
      capabilities: []
    )

    #expect(throws: ServerCompatibilityError.incompatibleServer(
      serverVersion: OrbitDockProtocol.releaseVersion,
      serverCompatibility: "legacy_contract",
      reason: "upgrade_app",
      message: "Update OrbitDock to a build compatible with server 0.4.0."
    )) {
      try hello.validateCompatibility()
    }
  }

  @Test func serverMetaRejectsIncompatibleServerVerdict() throws {
    let meta = ServerMetaResponse(
      serverVersion: OrbitDockProtocol.releaseVersion,
      compatibility: ServerCompatibilityStatus(
        compatible: false,
        serverCompatibility: "legacy_contract",
        reason: "upgrade_server",
        message: "Update the OrbitDock server to work with client 0.5.0."
      ),
      capabilities: [],
      isPrimary: true,
      clientPrimaryClaims: []
    )

    #expect(throws: ServerCompatibilityError.incompatibleServer(
      serverVersion: OrbitDockProtocol.releaseVersion,
      serverCompatibility: "legacy_contract",
      reason: "upgrade_server",
      message: "Update the OrbitDock server to work with client 0.5.0."
    )) {
      try meta.validateCompatibility()
    }
  }

  @Test func httpResponseRejectsIncompatibleServerVerdict() throws {
    let response = HTTPResponse(
      statusCode: 200,
      headers: [
        "X-OrbitDock-Server-Version": OrbitDockProtocol.releaseVersion,
        "X-OrbitDock-Server-Compatibility": "legacy_contract",
        "X-OrbitDock-Compatible": "false",
        "X-OrbitDock-Compatibility-Reason": "upgrade_app",
        "X-OrbitDock-Compatibility-Message": "Update OrbitDock to a build compatible with server 0.4.0.",
      ],
      body: Data()
    )

    #expect(throws: ServerCompatibilityError.incompatibleServer(
      serverVersion: OrbitDockProtocol.releaseVersion,
      serverCompatibility: "legacy_contract",
      reason: "upgrade_app",
      message: "Update OrbitDock to a build compatible with server 0.4.0."
    )) {
      try response.validateServerCompatibilityHeaders()
    }
  }

  @Test func httpResponseRequiresCompatibilityMetadata() throws {
    let response = HTTPResponse(
      statusCode: 200,
      headers: [
        "X-OrbitDock-Server-Version": OrbitDockProtocol.releaseVersion,
      ],
      body: Data()
    )

    #expect(throws: ServerCompatibilityError.missingCompatibilityMetadata(transport: "HTTP")) {
      try response.validateServerCompatibilityHeaders()
    }
  }
}
