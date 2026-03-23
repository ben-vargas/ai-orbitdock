import SwiftUI

struct MissionWorktreeCleanupSheet: View {
  let worktrees: [MissionWorktreeItem]
  let isLoading: Bool
  let isCleaning: Bool
  let onCancel: () -> Void
  let onConfirm: (Set<String>) -> Void

  @State private var selectedIds: Set<String> = []
  @State private var initialized = false

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()

      if isLoading {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if worktrees.isEmpty {
        emptyState
      } else {
        worktreeList
      }

      Divider()
      footer
    }
    .frame(maxWidth: 500)
    .background(Color.panelBackground)
    .onAppear {
      guard !initialized else { return }
      initialized = true
      selectedIds = Set(worktrees.filter(\.isCleanable).map(\.id))
    }
  }

  // MARK: - Header

  private var header: some View {
    HStack {
      Text("Clean Up Worktrees")
        .font(.system(size: TypeScale.body, weight: .semibold))
      Spacer()
      if !worktrees.isEmpty {
        Text("\(selectedIds.count) selected")
          .font(.system(size: TypeScale.micro, weight: .medium, design: .monospaced))
          .foregroundStyle(Color.textTertiary)
      }
    }
    .padding(.horizontal, Spacing.lg)
    .padding(.top, Spacing.lg)
    .padding(.bottom, Spacing.md)
  }

  // MARK: - Empty State

  private var emptyState: some View {
    VStack(spacing: Spacing.md) {
      Image(systemName: "arrow.triangle.branch")
        .font(.system(size: 32, weight: .light))
        .foregroundStyle(Color.textQuaternary)
      Text("No worktrees to clean up")
        .font(.system(size: TypeScale.body))
        .foregroundStyle(Color.textSecondary)
      Text("This mission has no associated worktrees, or they have already been cleaned up.")
        .font(.system(size: TypeScale.caption))
        .foregroundStyle(Color.textTertiary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(Spacing.xl)
  }

  // MARK: - Worktree List

  private var worktreeList: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.sm_) {
        Text("Select worktrees to remove from disk. Local branches will also be deleted.")
          .font(.system(size: TypeScale.meta))
          .foregroundStyle(Color.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.bottom, Spacing.xs)

        ForEach(worktrees) { worktree in
          worktreeRow(worktree)
        }
      }
      .padding(Spacing.lg)
    }
  }

  private func worktreeRow(_ worktree: MissionWorktreeItem) -> some View {
    let isSelected = selectedIds.contains(worktree.id)
    let isDisabled = worktree.isActive

    return HStack(spacing: Spacing.md) {
      Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        .font(.system(size: 18))
        .foregroundStyle(isDisabled ? Color.textQuaternary : isSelected ? Color.accent : Color.textTertiary)

      VStack(alignment: .leading, spacing: Spacing.xxs) {
        HStack(spacing: Spacing.sm_) {
          Text(worktree.issueIdentifier)
            .font(.system(size: TypeScale.caption, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.textTertiary)

          Text(worktree.issueTitle)
            .font(.system(size: TypeScale.caption))
            .foregroundStyle(Color.textPrimary)
            .lineLimit(1)
        }

        HStack(spacing: Spacing.sm) {
          Image(systemName: "arrow.triangle.branch")
            .font(.system(size: 9))
          Text(worktree.branch)
            .font(.system(size: TypeScale.micro, design: .monospaced))
            .lineLimit(1)
        }
        .foregroundStyle(Color.textQuaternary)
      }

      Spacer()

      HStack(spacing: Spacing.sm_) {
        if !worktree.diskPresent {
          Text("Not on disk")
            .font(.system(size: TypeScale.micro, weight: .medium))
            .foregroundStyle(Color.textQuaternary)
        }

        Text(worktree.orchestrationState.displayLabel)
          .font(.system(size: TypeScale.micro, weight: .bold))
          .foregroundStyle(worktree.orchestrationState.color)
          .padding(.horizontal, Spacing.xs)
          .padding(.vertical, 1)
          .background(
            worktree.orchestrationState.color.opacity(OpacityTier.subtle),
            in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
          )
      }
    }
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.sm)
    .background(
      RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
        .fill(isSelected ? Color.accent.opacity(OpacityTier.subtle) : Color.backgroundSecondary)
    )
    .contentShape(Rectangle())
    .onTapGesture {
      guard !isDisabled else { return }
      if isSelected {
        selectedIds.remove(worktree.id)
      } else {
        selectedIds.insert(worktree.id)
      }
    }
    .opacity(isDisabled ? 0.5 : 1.0)
    .help(isDisabled ? "Cannot remove while agent is active" : "")
  }

  // MARK: - Footer

  private var footer: some View {
    HStack {
      Spacer()

      Button("Cancel") {
        onCancel()
      }
      .keyboardShortcut(.cancelAction)

      Button {
        onConfirm(selectedIds)
      } label: {
        if isCleaning {
          ProgressView()
            .controlSize(.small)
            .frame(width: 80)
        } else {
          Text("Clean Up")
        }
      }
      .keyboardShortcut(.defaultAction)
      .buttonStyle(.borderedProminent)
      .tint(Color.statusPermission)
      .disabled(selectedIds.isEmpty || isCleaning)
    }
    .padding(.horizontal, Spacing.lg)
    .padding(.vertical, Spacing.md)
  }
}
