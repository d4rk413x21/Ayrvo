import SwiftUI
import AppKit

struct DigestActionItemsView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.ayrvoActionColor) private var actionColor
    @ObservedObject var tracker: TaskTrackerStore
    let digest: DailyDigest
    let onRenameOwner: (String) -> Void
    let onMergeOwner: (String) -> Void
    @State private var digestChecked: Set<UUID> = []
    @State private var digestItemFilter: String?
    @State private var digestShowAllOwners = false

    // MARK: - Digest action items (with "Track" buttons)

    var body: some View {
        if !digest.actionItems.isEmpty {
            actionItemsCard
        }
    }

    private var actionItemsCard: some View {
        let filtered = digestFilteredItems(digest)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "checklist")
                    .font(.ayrvo(13, .medium))
                    .foregroundStyle(Theme.honey(scheme))
                Text("\(filtered.count) of \(digest.actionItems.count) action items")
                    .font(.ayrvo(14, .semibold))
                    .foregroundStyle(Theme.heading(scheme))
                Spacer()
            }
            // Owner filter bar
            digestItemFilterBar(digest)
            // Filtered items
            ForEach(filtered, id: \.id) { item in
                digestActionItemRow(item, digest: digest)
            }
            if filtered.isEmpty {
                Text("No items match this filter")
                    .font(.ayrvo(11))
                    .foregroundStyle(Theme.tertiary(scheme))
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(Theme.card(scheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Distinct resolved owners from the digest's action items, sorted.
    private func digestItemOwners(_ digest: DailyDigest) -> [String] {
        let raw = Set(digest.actionItems.compactMap { $0.owner })
        let resolved = Set(raw.map { tracker.resolveOwner($0) })
        return resolved.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    /// The action items after applying the owner filter.
    /// Default (nil + showAll=false) filters to the current user.
    private func digestFilteredItems(_ digest: DailyDigest) -> [ActionItem] {
        if digestShowAllOwners { return digest.actionItems }
        let target = digestItemFilter ?? AppSettings.currentUserName
        return digest.actionItems.filter { item in
            guard let owner = item.owner else { return false }
            return tracker.resolveOwner(owner).lowercased()
                .contains(target.lowercased())
        }
    }

    private func digestItemFilterBar(_ digest: DailyDigest) -> some View {
        let owners = digestItemOwners(digest)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Image(systemName: "person.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiary(scheme))
                    .padding(.top, 1)

                digestFilterPill(
                    label: "Mine",
                    isActive: !digestShowAllOwners
                        && digestItemFilter == nil,
                    action: {
                        digestShowAllOwners = false
                        digestItemFilter = nil
                    }
                )

                ForEach(owners, id: \.self) { owner in
                    DigestOwnerPill(
                        owner: owner,
                        isActive: digestIsActive(owner: owner),
                        action: { digestSelectOwner(owner) },
                        onMerge: { onMergeOwner(owner) },
                        onRename: { onRenameOwner(owner) }
                    )
                }

                digestFilterPill(
                    label: "All",
                    isActive: digestShowAllOwners,
                    action: {
                        digestShowAllOwners = true
                        digestItemFilter = nil
                    }
                )
            }
        }
        .padding(.bottom, 2)
    }

    private func digestIsActive(owner: String) -> Bool {
        if digestShowAllOwners { return false }
        if digestItemFilter == nil {
            return owner.lowercased()
                .contains(AppSettings.currentUserName.lowercased())
        }
        return digestItemFilter == owner
    }

    private func digestSelectOwner(_ owner: String) {
        digestShowAllOwners = false
        let isCurrentUser = owner.lowercased()
            .contains(AppSettings.currentUserName.lowercased())
        digestItemFilter = isCurrentUser ? nil : owner
    }

    private func digestFilterPill(
        label: String, isActive: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.ayrvo(10, .semibold))
                .foregroundStyle(isActive ? .white : Theme.secondary(scheme))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    isActive ? actionColor : Theme.chip(scheme),
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func digestActionItemRow(
        _ item: ActionItem, digest: DailyDigest
    ) -> some View {
        let resolvedOwner = item.owner.map { tracker.resolveOwner($0) }
        let isMine = resolvedOwner?.lowercased()
            .contains(AppSettings.currentUserName.lowercased()) ?? false
        let isLocallyChecked = digestChecked.contains(item.id)
        return HStack(spacing: 8) {
            Button {
                if isLocallyChecked {
                    digestChecked.remove(item.id)
                } else {
                    digestChecked.insert(item.id)
                }
            } label: {
                Image(systemName: isLocallyChecked
                    ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundStyle(isLocallyChecked
                        ? Theme.mint(scheme) : Theme.tertiary(scheme))
            }
            .buttonStyle(.plain)

            Text(item.text)
                .font(.ayrvo(12))
                .foregroundStyle(isLocallyChecked
                    ? Theme.secondary(scheme) : Theme.heading(scheme))
                .strikethrough(isLocallyChecked)
                .lineLimit(2)
            // Only show the owner badge when "All" is active or the owner
            // differs from the current filter — avoids repeating the same
            // pill on every row when filtering by one owner.
            if let owner = resolvedOwner, shouldShowOwnerBadge(owner: owner) {
                Text(owner)
                    .font(.ayrvo(10, .semibold))
                    .foregroundStyle(
                        isMine ? actionColor : Theme.blueberry(scheme))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        (isMine ? actionColor : Theme.blueberry(scheme))
                            .opacity(0.12),
                        in: Capsule()
                    )
            }
            Spacer(minLength: 0)
            Button {
                trackDigestItem(item, from: digest)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(actionColor)
            }
            .buttonStyle(.plain)
            .help("Add to Activity Tracker")
            .accessibilityLabel("Add to Activity Tracker")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    /// Show the owner badge only when viewing "All" or when the owner
    /// differs from the active filter target.
    private func shouldShowOwnerBadge(owner: String) -> Bool {
        if digestShowAllOwners { return true }
        let target = digestItemFilter ?? AppSettings.currentUserName
        return !owner.lowercased().contains(target.lowercased())
    }

    private func trackDigestItem(_ item: ActionItem, from digest: DailyDigest) {
        tracker.track(item, source: digest.actionItemSources[item.id])
    }
}

private struct DigestOwnerPill: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.ayrvoActionColor) private var actionColor

    let owner: String
    let isActive: Bool
    let action: () -> Void
    var onMerge: (() -> Void)? = nil
    var onRename: (() -> Void)? = nil

    var body: some View {
        Button(action: action) {
            Text(owner)
                .font(.ayrvo(10, .semibold))
                .foregroundStyle(isActive ? .white : Theme.secondary(scheme))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    isActive ? actionColor : Theme.chip(scheme),
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Filter") { action() }
            if let onRename {
                Button("Rename\u{2026}") { onRename() }
            }
            if let onMerge {
                Button("Merge with\u{2026}") { onMerge() }
            }
        }
    }
}
