import SwiftUI

#if os(macOS)

  extension ProjectPicker {
    var selectedPathBanner: some View {
      HStack(spacing: Spacing.sm) {
        Image(systemName: "folder.fill")
          .font(.system(size: TypeScale.caption))
          .foregroundStyle(Color.accent)

        VStack(alignment: .leading, spacing: Spacing.xxs) {
          Text(URL(fileURLWithPath: selectedPath).lastPathComponent)
            .font(.system(size: TypeScale.body, weight: .medium))
            .foregroundStyle(Color.textPrimary)

          Text(ProjectPickerPlanner.displayPath(selectedPath))
            .font(.system(size: TypeScale.caption, design: .monospaced))
            .foregroundStyle(Color.textTertiary)
            .lineLimit(1)
            .truncationMode(.middle)
        }

        Spacer()

        Button {
          selectedPath = ""
          selectedPathIsGit = true
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: TypeScale.subhead))
            .foregroundStyle(Color.textQuaternary)
        }
        .buttonStyle(.plain)
      }
      .padding(Spacing.md)
      .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
          .stroke(Color.accent.opacity(OpacityTier.light), lineWidth: 1)
      )
    }

    var tabPicker: some View {
      HStack(spacing: 0) {
        ForEach(PickerTab.allCases, id: \.self) { tab in
          Button {
            withAnimation(Motion.hover) {
              activeTab = tab
            }
            if tab == .browse, directoryEntries.isEmpty {
              browseDirectory(nil)
            }
          } label: {
            Text(tab.rawValue)
              .font(.system(size: TypeScale.body, weight: activeTab == tab ? .semibold : .medium))
              .foregroundStyle(activeTab == tab ? Color.backgroundPrimary : Color.textTertiary)
              .padding(.horizontal, Spacing.lg)
              .padding(.vertical, Spacing.sm)
              .frame(minWidth: 76)
              .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                  .fill(activeTab == tab ? Color.accent : Color.clear)
              )
          }
          .buttonStyle(.plain)
        }
      }
      .padding(Spacing.xxs)
      .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
          .stroke(Color.surfaceBorder.opacity(OpacityTier.light), lineWidth: 1)
      )
    }

    var recentProjectsView: some View {
      VStack(alignment: .leading, spacing: Spacing.sm) {
        if isLoadingRecent {
          HStack {
            Spacer()
            ProgressView()
              .controlSize(.small)
            Spacer()
          }
          .padding(.vertical, Spacing.xl)
        } else if recentProjects.isEmpty {
          VStack(spacing: Spacing.sm) {
            Image(systemName: "clock")
              .font(.system(size: 24))
              .foregroundStyle(Color.textQuaternary)
            Text("No recent projects")
              .font(.system(size: TypeScale.body))
              .foregroundStyle(Color.textTertiary)
            Text("Start a session to see projects here")
              .font(.system(size: TypeScale.caption))
              .foregroundStyle(Color.textQuaternary)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, Spacing.xl)
        } else {
          ScrollView {
            LazyVStack(spacing: Spacing.xxs) {
              ForEach(groupedRecentProjects) { group in
                groupedRecentProjectSection(group)
              }
            }
            .padding(Spacing.sm)
          }
          .frame(minHeight: 200, maxHeight: 280)
        }
      }
      .padding(.vertical, Spacing.xs)
      .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
          .stroke(Color.surfaceBorder.opacity(OpacityTier.light), lineWidth: 1)
      )
    }

    func groupedRecentProjectSection(_ group: GroupedRecentProject) -> some View {
      VStack(spacing: Spacing.xxs) {
        if let project = group.repoProject {
          repoProjectRow(
            project: project,
            worktreeCount: group.worktrees.count,
            totalSessionCount: group.totalSessionCount
          )
        } else {
          syntheticRepoRow(group)
        }

        ForEach(group.worktrees) { worktree in
          worktreeProjectRow(worktree)
        }
      }
    }

    func repoProjectRow(
      project: ServerRecentProject,
      worktreeCount: Int,
      totalSessionCount: UInt32
    ) -> some View {
      projectSelectionRow(
        iconName: "folder.fill",
        iconFont: .system(size: 14),
        title: URL(fileURLWithPath: project.path).lastPathComponent,
        detail: ProjectPickerPlanner.displayPath(project.path),
        badges: projectBadges(worktreeCount: worktreeCount, totalSessionCount: totalSessionCount),
        selectionPath: project.path,
        leadingPadding: Spacing.md,
        onSelect: {
          selectedPath = project.path
          selectedPathIsGit = true
        }
      )
    }

    func syntheticRepoRow(_ group: GroupedRecentProject) -> some View {
      projectSelectionRow(
        iconName: "folder.fill",
        iconFont: .system(size: 14),
        title: URL(fileURLWithPath: group.repoPath).lastPathComponent,
        detail: ProjectPickerPlanner.displayPath(group.repoPath),
        badges: [
          "\(group.worktrees.count) worktree\(group.worktrees.count == 1 ? "" : "s")",
          ProjectPickerPlanner.sessionCountLabel(group.totalSessionCount),
        ],
        selectionPath: group.repoPath,
        leadingPadding: Spacing.md,
        onSelect: {
          selectedPath = group.repoPath
          selectedPathIsGit = true
        }
      )
    }

    func worktreeProjectRow(_ worktree: ProjectPickerRecentWorktreeProject) -> some View {
      projectSelectionRow(
        iconName: "arrow.triangle.branch",
        iconFont: .system(size: 13, weight: .semibold),
        title: worktree.branchPath,
        detail: ProjectPickerPlanner.worktreeRelativePath(worktree),
        badges: ["worktree", ProjectPickerPlanner.sessionCountLabel(worktree.project.sessionCount)],
        selectionPath: worktree.project.path,
        leadingPadding: Spacing.xl + Spacing.md,
        onSelect: {
          selectedPath = worktree.project.path
          selectedPathIsGit = true
        }
      )
    }

    private func projectBadges(worktreeCount: Int, totalSessionCount: UInt32) -> [String] {
      var badges: [String] = []
      if worktreeCount > 0 {
        badges.append("\(worktreeCount) worktree\(worktreeCount == 1 ? "" : "s")")
      }
      badges.append(ProjectPickerPlanner.sessionCountLabel(totalSessionCount))
      return badges
    }

    private func projectSelectionRow(
      iconName: String,
      iconFont: Font,
      title: String,
      detail: String,
      badges: [String],
      selectionPath: String,
      leadingPadding: CGFloat,
      onSelect: @escaping () -> Void
    ) -> some View {
      Button(action: onSelect) {
        HStack(spacing: Spacing.md) {
          Image(systemName: iconName)
            .font(iconFont)
            .foregroundStyle(Color.accent)
            .frame(width: 20)

          VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
              .font(.system(size: TypeScale.body, weight: .medium))
              .foregroundStyle(Color.textPrimary)

            Text(detail)
              .font(.system(size: TypeScale.caption, design: .monospaced))
              .foregroundStyle(Color.textTertiary)
              .lineLimit(1)
              .truncationMode(.middle)
          }

          Spacer()

          HStack(spacing: Spacing.sm) {
            ForEach(Array(badges.enumerated()), id: \.offset) { index, badge in
              if index == badges.count - 1, badges.count > 1 {
                Text(badge)
                  .font(.system(size: TypeScale.caption))
                  .foregroundStyle(Color.textQuaternary)
              } else {
                Text(badge)
                  .font(.system(size: TypeScale.micro, weight: .semibold))
                  .foregroundStyle(Color.accent)
                  .padding(.horizontal, Spacing.sm_)
                  .padding(.vertical, Spacing.xxs)
                  .background(Color.accent.opacity(OpacityTier.tint), in: Capsule())
              }
            }
          }
        }
        .padding(.leading, leadingPadding)
        .padding(.trailing, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(alignment: .leading) {
          RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(selectedPath == selectionPath ? Color.accent.opacity(OpacityTier.light) : Color.clear)
            .overlay(
              RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(selectedPath == selectionPath ? Color.accent.opacity(OpacityTier.medium) : Color.clear, lineWidth: 1)
            )
        }
        .overlay(alignment: .leading) {
          RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
            .fill(selectedPath == selectionPath ? Color.accent : Color.clear)
            .frame(width: EdgeBar.width)
            .padding(.vertical, Spacing.xs)
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
      }
      .buttonStyle(.plain)
    }

    var directoryBrowserView: some View {
      VStack(alignment: .leading, spacing: Spacing.sm) {
        HStack(spacing: Spacing.sm) {
          if ProjectPickerPlanner.canNavigateBack(browseHistory) {
            Button {
              navigateBack()
            } label: {
              Image(systemName: "chevron.left")
                .font(.system(size: TypeScale.meta, weight: .semibold))
                .foregroundStyle(Color.accent)
                .frame(width: 28, height: 28)
                .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: Radius.md))
            }
            .buttonStyle(.plain)
          }

          Text(ProjectPickerPlanner.displayPath(currentBrowsePath))
            .font(.system(size: TypeScale.caption, design: .monospaced))
            .foregroundStyle(Color.textTertiary)
            .lineLimit(1)
            .truncationMode(.head)

          Spacer()

          if !currentBrowsePath.isEmpty {
            Button {
              selectedPath = currentBrowsePath
              selectedPathIsGit = false
            } label: {
              Text("Use This")
                .font(.system(size: TypeScale.caption, weight: .semibold))
                .foregroundStyle(Color.accent)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(Color.accent.opacity(OpacityTier.light), in: RoundedRectangle(cornerRadius: Radius.sm))
            }
            .buttonStyle(.plain)
          }
        }

        if isLoadingDirectory {
          HStack {
            Spacer()
            ProgressView()
              .controlSize(.small)
            Spacer()
          }
          .padding(.vertical, Spacing.xl)
        } else {
          ScrollView {
            LazyVStack(spacing: Spacing.xxs) {
              ForEach(directoryEntries.filter(\.isDir)) { entry in
                directoryEntryRow(entry)
              }
            }
            .padding(Spacing.sm)
          }
          .frame(minHeight: 200, maxHeight: 280)
        }
      }
      .padding(.horizontal, Spacing.sm)
      .padding(.vertical, Spacing.sm)
      .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
          .stroke(Color.surfaceBorder.opacity(OpacityTier.light), lineWidth: 1)
      )
    }

    private func directoryEntryRow(_ entry: ServerDirectoryEntry) -> some View {
      Button {
        let newPath = ProjectPickerPlanner.childPath(entryName: entry.name, currentBrowsePath: currentBrowsePath)

        if entry.isGit {
          selectedPath = newPath
          selectedPathIsGit = true
        } else {
          browseDirectory(newPath)
        }
      } label: {
        HStack(spacing: Spacing.md) {
          Image(systemName: entry.isGit ? "chevron.left.forwardslash.chevron.right" : "folder")
            .font(.system(size: 13))
            .foregroundStyle(entry.isGit ? Color.accent : Color.textTertiary)
            .frame(width: 20)

          Text(entry.name)
            .font(.system(size: TypeScale.body, weight: entry.isGit ? .semibold : .regular))
            .foregroundStyle(entry.isGit ? Color.textPrimary : Color.textSecondary)

          Spacer()

          if entry.isGit {
            Text("repo")
              .font(.system(size: TypeScale.micro, weight: .semibold))
              .foregroundStyle(Color.accent)
              .padding(.horizontal, Spacing.sm_)
              .padding(.vertical, Spacing.xxs)
              .background(Color.accent.opacity(OpacityTier.tint), in: Capsule())
          } else {
            Image(systemName: "chevron.right")
              .font(.system(size: TypeScale.micro, weight: .medium))
              .foregroundStyle(Color.textQuaternary)
          }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
  }

#endif
