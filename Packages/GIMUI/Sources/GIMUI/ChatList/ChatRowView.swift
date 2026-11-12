import GIMFeatures
import SwiftUI
import UIKit

/// One chat list row: avatar, title with the muted and pinned marks, time and status ticks, then the subtitle and the
/// unread badge. VoiceOver reads it as one element.
struct ChatRowView: View {
    let row: ChatRow
    let subtitle: String
    let status: MessageStatus?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                standardLayout
            }
        }
        .frame(minHeight: 44)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(row: row, subtitle: subtitle, status: status))
    }

    private var standardLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            ChatRowAvatar(row: row, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    titleText.lineLimit(1)
                    marks
                    Spacer(minLength: 8)
                    ticks
                    timeText
                }
                HStack(alignment: .top) {
                    subtitleText
                    UnreadBadge(count: row.unreadCount)
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }
    }

    /// Time and badge get their own line so nothing clips at the largest text sizes.
    private var accessibilityLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            ChatRowAvatar(row: row, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                titleText.lineLimit(2)
                subtitleText
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    marks
                    ticks
                    timeText
                    Spacer(minLength: 8)
                    UnreadBadge(count: row.unreadCount)
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }
    }

    private var titleText: some View {
        Text(row.title)
            .font(.headline)
            .foregroundStyle(.primary)
    }

    private var subtitleText: some View {
        Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var timeText: some View {
        if let time = row.time {
            Text(time)
                .font(.footnote)
                .foregroundStyle(row.unreadCount > 0 ? ChatColors.unreadBadge : Color.secondary)
        }
    }

    /// Bell-slash for a muted chat, pin for a pinned one; the row label reads both.
    @ViewBuilder
    private var marks: some View {
        if row.isMuted {
            Image(systemName: "bell.slash.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Muted", tableName: "Chat", bundle: .module))
        }
        if row.isPinned {
            Image(systemName: "pin.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Pinned", tableName: "Chat", bundle: .module))
        }
    }

    /// Same symbols as `StatusTicksView`; the row label reads the status.
    private var ticks: some View {
        Group {
            switch status {
            case .sending:
                Image(systemName: "clock").foregroundStyle(.secondary)
            case .sent:
                Image(systemName: "checkmark").foregroundStyle(.secondary)
            case .delivered:
                doubleCheckmark.foregroundStyle(.secondary)
            case .read:
                doubleCheckmark.foregroundStyle(ChatColors.readTicks)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
            case nil:
                EmptyView()
            }
        }
        .font(.caption2)
        .accessibilityHidden(true)
    }

    private var doubleCheckmark: some View {
        HStack(spacing: -6) {
            Image(systemName: "checkmark")
            Image(systemName: "checkmark")
        }
    }

    /// Name, pinned and muted, status of the own last message, subtitle, time and unread count, joined with ", ".
    nonisolated static func accessibilityLabel(row: ChatRow, subtitle: String, status: MessageStatus?) -> String {
        var parts = [row.title]
        if row.isPinned {
            parts.append(String(localized: "Pinned", table: "Chat", bundle: .module))
        }
        if row.isMuted {
            parts.append(String(localized: "Muted", table: "Chat", bundle: .module))
        }
        if let status {
            parts.append(statusText(status))
        }
        parts.append(subtitle)
        if let time = row.time {
            parts.append(time)
        }
        if row.unreadCount > 0 {
            parts.append(String(localized: "\(Int(row.unreadCount)) unread", table: "Common", bundle: .module))
        }
        return parts.joined(separator: ", ")
    }

    private nonisolated static func statusText(_ status: MessageStatus) -> String {
        switch status {
        case .sending: String(localized: "Sending", table: "Chat", bundle: .module)
        case .sent: String(localized: "Sent", table: "Chat", bundle: .module)
        case .delivered: String(localized: "Delivered", table: "Chat", bundle: .module)
        case .read: String(localized: "Read", table: "Chat", bundle: .module)
        case .failed: String(localized: "Not sent", table: "Chat", bundle: .module)
        }
    }
}

/// The row's avatar; the note to self shows the own avatar with a note badge.
struct ChatRowAvatar: View {
    let row: ChatRow
    let size: CGFloat

    var body: some View {
        AvatarView(id: row.avatarId, name: row.avatarName, avatarPath: nil, size: size)
            .overlay(alignment: .bottomTrailing) {
                if row.isNoteToSelf {
                    NoteToSelfBadge(size: size * 0.42)
                }
            }
    }
}

/// The note badge on the note to self's avatar.
struct NoteToSelfBadge: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "note.text")
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.accentColor))
            .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2))
            .accessibilityHidden(true)
    }
}
