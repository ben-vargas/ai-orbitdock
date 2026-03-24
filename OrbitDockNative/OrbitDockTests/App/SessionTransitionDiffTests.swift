import Foundation
@testable import OrbitDock
import Testing

private let testEndpointID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!

private func sid(_ sessionId: String) -> String {
  "\(testEndpointID.uuidString)::\(sessionId)"
}

@MainActor
struct SessionTransitionDiffTests {
  @Test func workingToPermissionProducesNeedsAttention() {
    let prev = makeNode(id: "s1", displayStatus: .working)
    let curr = makeNode(id: "s1", displayStatus: .permission, pendingToolName: "Bash")

    let transitions = SessionTransitionDiff.transitions(
      previous: [sid("s1"): prev],
      current: [sid("s1"): curr]
    )

    #expect(transitions == [
      SessionTransition.needsAttention(scopedID: sid("s1"), status: .permission, title: "project", detail: "Bash"),
    ])
  }

  @Test func workingToQuestionProducesNeedsAttention() {
    let prev = makeNode(id: "s1", displayStatus: .working)
    let curr = makeNode(id: "s1", displayStatus: .question)

    let transitions = SessionTransitionDiff.transitions(
      previous: [sid("s1"): prev],
      current: [sid("s1"): curr]
    )

    #expect(transitions == [
      SessionTransition.needsAttention(scopedID: sid("s1"), status: .question, title: "project", detail: nil),
    ])
  }

  @Test func workingToReplyProducesWorkComplete() {
    let prev = makeNode(id: "s1", displayStatus: .working)
    let curr = makeNode(id: "s1", displayStatus: .reply)

    let transitions = SessionTransitionDiff.transitions(
      previous: [sid("s1"): prev],
      current: [sid("s1"): curr]
    )

    #expect(transitions == [
      SessionTransition.workComplete(scopedID: sid("s1"), title: "project", provider: .claude),
    ])
  }

  @Test func workingToEndedProducesWorkComplete() {
    let prev = makeNode(id: "s1", displayStatus: .working)
    let curr = makeNode(id: "s1", displayStatus: .ended, sessionStatus: .ended)

    let transitions = SessionTransitionDiff.transitions(
      previous: [sid("s1"): prev],
      current: [sid("s1"): curr]
    )

    #expect(transitions == [
      SessionTransition.workComplete(scopedID: sid("s1"), title: "project", provider: .claude),
    ])
  }

  @Test func permissionToWorkingProducesAttentionCleared() {
    let prev = makeNode(id: "s1", displayStatus: .permission)
    let curr = makeNode(id: "s1", displayStatus: .working)

    let transitions = SessionTransitionDiff.transitions(
      previous: [sid("s1"): prev],
      current: [sid("s1"): curr]
    )

    #expect(transitions == [
      SessionTransition.attentionCleared(scopedID: sid("s1")),
    ])
  }

  @Test func identicalStateProducesNoTransitions() {
    let node = makeNode(id: "s1", displayStatus: .working)

    let transitions = SessionTransitionDiff.transitions(
      previous: [sid("s1"): node],
      current: [sid("s1"): node]
    )

    #expect(transitions.isEmpty)
  }

  @Test func newSessionNeedingAttentionProducesNeedsAttention() {
    let curr = makeNode(id: "s1", displayStatus: .permission)

    let transitions = SessionTransitionDiff.transitions(
      previous: [:],
      current: [sid("s1"): curr]
    )

    #expect(transitions == [
      SessionTransition.needsAttention(scopedID: sid("s1"), status: .permission, title: "project", detail: nil),
    ])
  }

  @Test func newSessionWorkingProducesNoTransitions() {
    let curr = makeNode(id: "s1", displayStatus: .working)

    let transitions = SessionTransitionDiff.transitions(
      previous: [:],
      current: [sid("s1"): curr]
    )

    #expect(transitions.isEmpty)
  }

  @Test func passiveCodexSessionsAreSkipped() {
    let prev = makeNode(id: "s1", displayStatus: .working, provider: .codex, codexIntegrationMode: .passive)
    let curr = makeNode(id: "s1", displayStatus: .permission, provider: .codex, codexIntegrationMode: .passive)

    let transitions = SessionTransitionDiff.transitions(
      previous: [sid("s1"): prev],
      current: [sid("s1"): curr]
    )

    #expect(transitions.isEmpty)
  }

  @Test func removedSessionWithAttentionProducesAttentionCleared() {
    let prev = makeNode(id: "s1", displayStatus: .permission)

    let transitions = SessionTransitionDiff.transitions(
      previous: [sid("s1"): prev],
      current: [:]
    )

    #expect(transitions == [
      SessionTransition.attentionCleared(scopedID: sid("s1")),
    ])
  }

  @Test func removedSessionWithoutAttentionProducesNothing() {
    let prev = makeNode(id: "s1", displayStatus: .working)

    let transitions = SessionTransitionDiff.transitions(
      previous: [sid("s1"): prev],
      current: [:]
    )

    // Working session removed produces workComplete
    #expect(transitions == [
      SessionTransition.workComplete(scopedID: sid("s1"), title: "project", provider: .claude),
    ])
  }

  // MARK: - Helpers

  private func makeNode(
    id: String,
    displayStatus: SessionDisplayStatus,
    sessionStatus: Session.SessionStatus = .active,
    provider: Provider = .claude,
    codexIntegrationMode: CodexIntegrationMode? = nil,
    pendingToolName: String? = nil
  ) -> RootSessionNode {
    let attentionReason: Session.AttentionReason = switch displayStatus {
      case .permission: .awaitingPermission
      case .question: .awaitingQuestion
      case .reply: .awaitingReply
      default: .none
    }
    let workStatus: Session.WorkStatus = switch displayStatus {
      case .working: .working
      case .permission: .permission
      case .question: .waiting
      case .reply: .waiting
      case .ended: .ended
    }

    return makeRootSessionNode(from: Session(
      id: id,
      endpointId: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
      endpointName: nil,
      endpointConnectionStatus: .connected,
      projectPath: "/tmp/project",
      projectName: nil,
      status: sessionStatus,
      workStatus: workStatus,
      attentionReason: attentionReason,
      pendingToolName: pendingToolName,
      provider: provider,
      codexIntegrationMode: codexIntegrationMode
    ))
  }
}
