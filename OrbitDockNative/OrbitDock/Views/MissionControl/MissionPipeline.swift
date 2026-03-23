import SwiftUI

struct MissionPipeline: View {
  let queuedIssues: [MissionIssueItem]
  let completedIssues: [MissionIssueItem]
  let missionId: String
  let endpointId: UUID
  let http: ServerHTTPClient?
  let isCompact: Bool
  let onNavigateToSession: (String) -> Void
  let onRefresh: () async -> Void
  let onSelectIssuesTab: () -> Void
  let onTransitionIssue: (String, OrchestrationState, String?) async -> Void

  @State private var completedExpanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xl) {
      if !queuedIssues.isEmpty {
        queuedSection
      }

      if !completedIssues.isEmpty {
        completedSection
      }
    }
  }

  // MARK: - Queued Section

  private var queuedSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      MissionSectionHeader(
        title: "Queued",
        icon: "clock.fill",
        color: Color.feedbackCaution,
        count: queuedIssues.count
      )

      ForEach(Array(queuedIssues.enumerated()), id: \.element.id) { index, issue in
        queuedRow(issue, position: index + 1)
      }
    }
  }

  private func queuedRow(_ issue: MissionIssueItem, position: Int) -> some View {
    HStack(spacing: Spacing.sm) {
      // Left edge bar
      RoundedRectangle(cornerRadius: 1.5, style: .continuous)
        .fill(Color.feedbackCaution)
        .frame(width: EdgeBar.width)

      // Queue position
      Text("#\(position)")
        .font(.system(size: TypeScale.micro, weight: .bold, design: .monospaced))
        .foregroundStyle(Color.feedbackCaution.opacity(0.6))
        .frame(width: 20, alignment: .trailing)

      if isCompact {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
          HStack(spacing: Spacing.sm_) {
            Text(issue.identifier)
              .font(.system(size: TypeScale.micro, weight: .bold, design: .monospaced))
              .foregroundStyle(Color.feedbackCaution)

            Spacer()

            IssueTransitionMenu(issue: issue) { target, reason in
              await onTransitionIssue(issue.issueId, target, reason)
            }
          }

          Text(issue.title)
            .font(.system(size: TypeScale.caption))
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      } else {
        HStack(spacing: Spacing.sm_) {
          Text(issue.identifier)
            .font(.system(size: TypeScale.micro, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.feedbackCaution)

          Text(issue.title)
            .font(.system(size: TypeScale.caption))
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

          Spacer()

          IssueTransitionMenu(issue: issue) { target, reason in
            await onTransitionIssue(issue.issueId, target, reason)
          }
        }
      }
    }
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.sm)
    .background(
      RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
        .fill(Color.backgroundSecondary)
    )
  }

  // MARK: - Completed Section

  private var completedSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      MissionSectionHeader(
        title: "Completed",
        icon: "checkmark.circle.fill",
        color: Color.feedbackPositive,
        count: completedIssues.count,
        urgency: .settled
      )

      let visibleIssues = completedExpanded ? completedIssues : Array(completedIssues.prefix(3))

      ForEach(visibleIssues) { issue in
        completedRow(issue)
      }

      if completedIssues.count > 3 {
        Button {
          if completedExpanded {
            onSelectIssuesTab()
          } else {
            withAnimation(Motion.standard) { completedExpanded = true }
          }
        } label: {
          HStack(spacing: Spacing.xs) {
            Text(completedExpanded ? "View all in Issues tab" : "Show \(completedIssues.count - 3) more")
              .font(.system(size: TypeScale.micro, weight: .medium))
            Image(systemName: completedExpanded ? "arrow.right" : "chevron.down")
              .font(.system(size: 8, weight: .bold))
          }
          .foregroundStyle(Color.accent)
        }
        .buttonStyle(.plain)
        .padding(.leading, Spacing.lg)
      }
    }
  }

  private func completedRow(_ issue: MissionIssueItem) -> some View {
    HStack(spacing: Spacing.sm) {
      // Left edge bar
      RoundedRectangle(cornerRadius: 1.5, style: .continuous)
        .fill(Color.feedbackPositive.opacity(0.5))
        .frame(width: EdgeBar.width)

      if isCompact {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
          HStack(spacing: Spacing.sm_) {
            Text(issue.identifier)
              .font(.system(size: TypeScale.micro, weight: .bold, design: .monospaced))
              .foregroundStyle(Color.feedbackPositive.opacity(0.7))

            Spacer()

            Text(issue.trackerState)
              .font(.system(size: TypeScale.micro, weight: .medium))
              .foregroundStyle(Color.textQuaternary)

            IssueTransitionMenu(issue: issue) { target, reason in
              await onTransitionIssue(issue.issueId, target, reason)
            }
          }

          Text(issue.title)
            .font(.system(size: TypeScale.caption))
            .foregroundStyle(Color.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
      } else {
        HStack(spacing: Spacing.sm_) {
          Text(issue.identifier)
            .font(.system(size: TypeScale.micro, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.feedbackPositive.opacity(0.7))

          Text(issue.title)
            .font(.system(size: TypeScale.caption))
            .foregroundStyle(Color.textTertiary)
            .fixedSize(horizontal: false, vertical: true)

          Spacer()

          Text(issue.trackerState)
            .font(.system(size: TypeScale.micro, weight: .medium))
            .foregroundStyle(Color.textQuaternary)

          IssueTransitionMenu(issue: issue) { target, reason in
            await onTransitionIssue(issue.issueId, target, reason)
          }

          if issue.sessionId != nil {
            Image(systemName: "arrow.right")
              .font(.system(size: 8, weight: .bold))
              .foregroundStyle(Color.accent)
          }
        }
      }
    }
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.sm)
    .background(
      RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
        .fill(Color.backgroundSecondary)
    )
    .opacity(0.65)
    .contentShape(Rectangle())
    .onTapGesture {
      if let sessionId = issue.sessionId {
        onNavigateToSession(sessionId)
      } else if let url = issue.url, let link = URL(string: url) {
        #if os(macOS)
          NSWorkspace.shared.open(link)
        #endif
      }
    }
  }
}
