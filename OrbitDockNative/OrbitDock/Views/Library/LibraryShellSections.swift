import SwiftUI

struct LibraryEmptyState: View {
  let hasActiveFilters: Bool

  var body: some View {
    VStack(spacing: Spacing.lg) {
      Image(systemName: "books.vertical")
        .font(.system(size: 32, weight: .light))
        .foregroundStyle(Color.textQuaternary)

      Text(hasActiveFilters ? "No sessions match this slice" : "No sessions yet")
        .font(.system(size: TypeScale.subhead, weight: .medium))
        .foregroundStyle(Color.textTertiary)

      Text(
        hasActiveFilters
          ? "Try a different search, provider, or server filter."
          : "Sessions will show up here once OrbitDock has some history to archive."
      )
      .font(.system(size: TypeScale.caption))
      .foregroundStyle(Color.textQuaternary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.vertical, 60)
  }
}
