import Foundation
@testable import OrbitDock
import Testing
import UserNotifications

private let testEndpointID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!

private func scopedID(_ sessionId: String) -> String {
  "\(testEndpointID.uuidString)::\(sessionId)"
}

@MainActor
struct NotificationCoordinatorTests {
  @Test func startIfNeededRequestsAuthorizationOnce() {
    var requestCount = 0

    let coordinator = makeCoordinator(
      isRunningTests: false,
      onRequestAuthorization: { completion in
        requestCount += 1
        completion(true, nil)
      }
    )

    coordinator.startIfNeeded()
    coordinator.startIfNeeded()

    #expect(requestCount == 1)
  }

  @Test func configuresCategoriesAndDelegate() {
    var assignedDelegate: UNUserNotificationCenterDelegate?
    var registeredCategories: Set<UNNotificationCategory> = []

    let coordinator = makeCoordinator(
      onSetDelegate: { assignedDelegate = $0 },
      onSetCategories: { registeredCategories = $0 }
    )

    let delegate = TestNotificationDelegate()
    coordinator.configureCategories(delegate: delegate)

    #expect(assignedDelegate === delegate)
    #expect(registeredCategories.count == 1)
    let category = registeredCategories.first
    #expect(category?.identifier == "SESSION_ATTENTION")
    #expect(category?.actions.map(\.identifier) == ["VIEW_SESSION"])
  }

  @Test func sendTestNotificationUsesInjectedClient() {
    var addedRequest: UNNotificationRequest?

    let coordinator = makeCoordinator(
      notificationsEnabled: true,
      onAddRequest: { request, _ in addedRequest = request }
    )

    coordinator.sendTestNotification(soundID: "default")

    #expect(addedRequest?.content.title == "Test Notification")
    #expect(addedRequest?.content.subtitle == "OrbitDock")
    #expect(addedRequest?.content.categoryIdentifier == "SESSION_ATTENTION")
  }

  @Test func attentionTransitionShowsToastWhenAppIsActive() {
    let coordinator = makeCoordinator(isAuthorized: true, notificationsEnabled: true)
    coordinator.appIsActive = true

    let working = [makeSession(id: "s1", displayStatus: .working)]
    coordinator.processSessionUpdate(working)

    let permission = [makeSession(id: "s1", displayStatus: .permission)]
    coordinator.processSessionUpdate(permission)

    #expect(coordinator.toasts.count == 1)
    #expect(coordinator.toasts.first?.sessionId == scopedID("s1"))
  }

  @Test func attentionTransitionSendsOSNotificationWhenAppIsInactive() {
    var addedRequest: UNNotificationRequest?

    let coordinator = makeCoordinator(
      isAuthorized: true,
      notificationsEnabled: true,
      onAddRequest: { request, _ in addedRequest = request }
    )
    coordinator.appIsActive = false

    let working = [makeSession(id: "s1", displayStatus: .working)]
    coordinator.processSessionUpdate(working)

    let permission = [makeSession(id: "s1", displayStatus: .permission)]
    coordinator.processSessionUpdate(permission)

    #expect(coordinator.toasts.isEmpty)
    #expect(addedRequest?.content.title == "Session Needs Attention")
    #expect(addedRequest?.identifier == "attention-\(scopedID("s1"))")
  }

  @Test func viewedSessionIsSuppressed() {
    var addedRequest: UNNotificationRequest?

    let coordinator = makeCoordinator(
      isAuthorized: true,
      notificationsEnabled: true,
      onAddRequest: { request, _ in addedRequest = request }
    )
    coordinator.appIsActive = true
    coordinator.viewedSessionScopedID = scopedID("s1")

    let working = [makeSession(id: "s1", displayStatus: .working)]
    coordinator.processSessionUpdate(working)

    let permission = [makeSession(id: "s1", displayStatus: .permission)]
    coordinator.processSessionUpdate(permission)

    #expect(coordinator.toasts.isEmpty)
    #expect(addedRequest == nil)
  }

  @Test func notificationsDisabledSuppressesEverything() {
    var addedRequest: UNNotificationRequest?

    let coordinator = makeCoordinator(
      isAuthorized: true,
      notificationsEnabled: false,
      onAddRequest: { request, _ in addedRequest = request }
    )
    coordinator.appIsActive = false

    let working = [makeSession(id: "s1", displayStatus: .working)]
    coordinator.processSessionUpdate(working)

    let permission = [makeSession(id: "s1", displayStatus: .permission)]
    coordinator.processSessionUpdate(permission)

    #expect(coordinator.toasts.isEmpty)
    #expect(addedRequest == nil)
  }

  @Test func attentionClearedRemovesOSNotification() {
    var removedIdentifiers: [String] = []

    let coordinator = makeCoordinator(
      isAuthorized: true,
      notificationsEnabled: true,
      onRemoveDelivered: { removedIdentifiers.append(contentsOf: $0) }
    )
    coordinator.appIsActive = false

    let permission = [makeSession(id: "s1", displayStatus: .permission)]
    coordinator.processSessionUpdate(permission)

    let working = [makeSession(id: "s1", displayStatus: .working)]
    coordinator.processSessionUpdate(working)

    #expect(removedIdentifiers.contains("attention-\(scopedID("s1"))"))
  }

  @Test func workCompleteOSNotificationWhenBackgrounded() {
    var addedRequest: UNNotificationRequest?

    let coordinator = makeCoordinator(
      isAuthorized: true,
      notificationsEnabled: true,
      notifyOnWorkComplete: true,
      onAddRequest: { request, _ in addedRequest = request }
    )
    coordinator.appIsActive = false

    let working = [makeSession(id: "s1", displayStatus: .working)]
    coordinator.processSessionUpdate(working)

    let reply = [makeSession(id: "s1", displayStatus: .reply)]
    coordinator.processSessionUpdate(reply)

    #expect(addedRequest?.content.title == "Claude Finished")
  }

  @Test func workCompleteDisabledSuppresses() {
    var addedRequest: UNNotificationRequest?

    let coordinator = makeCoordinator(
      isAuthorized: true,
      notificationsEnabled: true,
      notifyOnWorkComplete: false,
      onAddRequest: { request, _ in addedRequest = request }
    )
    coordinator.appIsActive = false

    let working = [makeSession(id: "s1", displayStatus: .working)]
    coordinator.processSessionUpdate(working)

    let reply = [makeSession(id: "s1", displayStatus: .reply)]
    coordinator.processSessionUpdate(reply)

    #expect(addedRequest == nil)
  }

  @Test func dismissRemovesToast() {
    let coordinator = makeCoordinator(isAuthorized: true, notificationsEnabled: true)
    coordinator.appIsActive = true

    let working = [makeSession(id: "s1", displayStatus: .working)]
    coordinator.processSessionUpdate(working)

    let permission = [makeSession(id: "s1", displayStatus: .permission)]
    coordinator.processSessionUpdate(permission)

    #expect(coordinator.toasts.count == 1)
    if let toast = coordinator.toasts.first {
      coordinator.dismiss(toast)
    }
    #expect(coordinator.toasts.isEmpty)
  }

  // MARK: - Factory Helpers

  private func makeCoordinator(
    isAuthorized: Bool = false,
    isRunningTests: Bool = true,
    notificationsEnabled: Bool = true,
    notifyOnWorkComplete: Bool = true,
    onRequestAuthorization: @escaping (@Sendable @escaping (Bool, Error?) -> Void) -> Void = { $0(false, nil) },
    onSetDelegate: @escaping (UNUserNotificationCenterDelegate?) -> Void = { _ in },
    onSetCategories: @escaping (Set<UNNotificationCategory>) -> Void = { _ in },
    onAddRequest: @escaping (UNNotificationRequest, @Sendable @escaping (Error?) -> Void) -> Void = { _, c in c(nil) },
    onRemoveDelivered: @escaping ([String]) -> Void = { _ in }
  ) -> NotificationCoordinator {
    let coordinator = NotificationCoordinator(
      notificationCenter: NotificationCenterClient(
        requestAuthorization: onRequestAuthorization,
        setDelegate: onSetDelegate,
        setNotificationCategories: onSetCategories,
        addRequest: onAddRequest,
        removeDeliveredNotifications: onRemoveDelivered
      ),
      preferences: NotificationPreferences(
        stringForKey: { _ in nil },
        objectForKey: { key in
          if key == "notificationsEnabled" { return notificationsEnabled }
          if key == "notifyOnWorkComplete" { return notifyOnWorkComplete }
          return nil
        },
        boolForKey: { key in
          if key == "notificationsEnabled" { return notificationsEnabled }
          if key == "notifyOnWorkComplete" { return notifyOnWorkComplete }
          return false
        }
      ),
      isRunningTestsProcess: isRunningTests
    )

    if isAuthorized {
      coordinator.isAuthorized = true
    }

    return coordinator
  }

  private func makeSession(
    id: String,
    displayStatus: SessionDisplayStatus
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
    let sessionStatus: Session.SessionStatus = displayStatus == .ended ? .ended : .active

    return makeRootSessionNode(from: Session(
      id: id,
      endpointId: testEndpointID,
      endpointName: nil,
      endpointConnectionStatus: .connected,
      projectPath: "/tmp/project",
      projectName: nil,
      status: sessionStatus,
      workStatus: workStatus,
      attentionReason: attentionReason,
      provider: .claude
    ))
  }
}

private final class TestNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {}
