import Foundation

struct DashboardClient: Sendable {
  let http: ServerHTTPClient

  func fetchDashboardSnapshot() async throws -> ServerDashboardSnapshotPayload {
    try await http.get("/api/dashboard")
  }
}
