import SwiftUI

struct MissionAlertBoard: View {
  let failedIssues: [MissionIssueItem]
  let blockedIssues: [MissionIssueItem]
  let missionId: String
  let endpointId: UUID
  let http: ServerHTTPClient?
  let isCompact: Bool
  let onNavigateToSession: (String) -> Void
  let onRefresh: () async -> Void
  let onTransitionIssue: (String, OrchestrationState, String?) async -> Void

  @State private var actionError: String?

  private var allAlertIssues: [MissionIssueItem] {
    blockedIssues + failedIssues
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      MissionSectionHeader(
        title: "Needs Attention",
        icon: "exclamationmark.triangle.fill",
        color: Color.feedbackNegative,
        count: allAlertIssues.count,
        urgency: .attention
      )

      ForEach(allAlertIssues) { issue in
        alertRow(issue)
      }
    }
    .padding(Spacing.lg)
    .background(alertBackground)
    .alert("Error", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(actionError ?? "")
    }
  }

  // MARK: - Alert Background

  private var alertBackground: some View {
    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
      .fill(Color.feedbackNegative.opacity(OpacityTier.tint))
      .overlay(
        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
          .strokeBorder(Color.feedbackNegative.opacity(OpacityTier.subtle), lineWidth: 1)
      )
      .shadow(color: Color.feedbackNegative.opacity(0.08), radius: 8, y: 2)
  }

  // MARK: - Alert Row

  private func alertRow(_ issue: MissionIssueItem) -> some View {
    let isBlocked = issue.orchestrationState == .blocked
    let alertColor = isBlocked ? Color.feedbackWarning : Color.feedbackNegative

    return HStack(spacing: Spacing.sm) {
      // Left edge bar
      RoundedRectangle(cornerRadius: 1.5, style: .continuous)
        .fill(alertColor)
        .frame(width: EdgeBar.width)

      VStack(alignment: .leading, spacing: Spacing.xs) {
        if isCompact {
          compactAlertRow(issue, isBlocked: isBlocked, alertColor: alertColor)
        } else {
          desktopAlertRow(issue, isBlocked: isBlocked, alertColor: alertColor)
        }
      }
    }
    .padding(.vertical, Spacing.sm)
  }

  // MARK: - Compact Alert

  private func compactAlertRow(
    _ issue: MissionIssueItem,
    isBlocked: Bool,
    alertColor: Color
  ) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      HStack(spacing: Spacing.sm_) {
        Text(issue.identifier)
          .font(.system(size: TypeScale.micro, weight: .bold, design: .monospaced))
          .foregroundStyle(alertColor)

        stateBadge(isBlocked ? "Blocked" : "Failed", color: alertColor)

        if issue.attempt > 1 {
          Text("#\(issue.attempt)")
            .font(.system(size: TypeScale.micro, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.feedbackCaution)
        }

        Spacer()

        if let sessionId = issue.sessionId {
          Button {
            onNavigateToSession(sessionId)
          } label: {
            Text("Open \u{2192}")
              .font(.system(size: TypeScale.micro, weight: .semibold))
              .foregroundStyle(Color.accent)
          }
          .buttonStyle(.plain)
        }

        IssueTransitionMenu(issue: issue) { target, reason in
          await onTransitionIssue(issue.issueId, target, reason)
        }
      }

      Text(issue.title)
        .font(.system(size: TypeScale.caption))
        .foregroundStyle(Color.textPrimary)
        .fixedSize(horizontal: false, vertical: true)

      if let error = issue.error, !error.isEmpty {
        Text(error)
          .font(.system(size: TypeScale.micro))
          .foregroundStyle(Color.textTertiary)
          .lineLimit(2)
      }
    }
  }

  // MARK: - Desktop Alert

  private func desktopAlertRow(
    _ issue: MissionIssueItem,
    isBlocked: Bool,
    alertColor: Color
  ) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      HStack(spacing: Spacing.sm_) {
        Text(issue.identifier)
          .font(.system(size: TypeScale.caption, weight: .bold, design: .monospaced))
          .foregroundStyle(alertColor)

        Text(issue.title)
          .font(.system(size: TypeScale.caption))
          .foregroundStyle(Color.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
      }

      HStack(spacing: Spacing.sm_) {
        stateBadge(isBlocked ? "Blocked" : "Failed", color: alertColor)

        if let error = issue.error, !error.isEmpty {
          Text(error)
            .font(.system(size: TypeScale.micro))
            .foregroundStyle(Color.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }

        if issue.attempt > 1 {
          Text("attempt #\(issue.attempt)")
            .font(.system(size: TypeScale.micro, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.feedbackCaution)
        }
      }

      HStack(spacing: Spacing.sm) {
        Text(issue.provider.capitalized)
          .font(.system(size: TypeScale.micro, weight: .semibold))
          .foregroundStyle(issue.providerColor)

        Spacer()

        if let sessionId = issue.sessionId {
          Button {
            onNavigateToSession(sessionId)
          } label: {
            Text("Open \u{2192}")
              .font(.system(size: TypeScale.micro, weight: .semibold))
              .foregroundStyle(Color.accent)
          }
          .buttonStyle(.plain)
          .help("Open session")
        }

        IssueTransitionMenu(issue: issue) { target, reason in
          await onTransitionIssue(issue.issueId, target, reason)
        }
      }
    }
  }

  // MARK: - Helpers

  private func stateBadge(_ label: String, color: Color) -> some View {
    Text(label)
      .font(.system(size: TypeScale.micro, weight: .bold))
      .foregroundStyle(color)
      .padding(.horizontal, Spacing.xs)
      .padding(.vertical, 1)
      .background(
        color.opacity(OpacityTier.subtle),
        in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
      )
  }
}
