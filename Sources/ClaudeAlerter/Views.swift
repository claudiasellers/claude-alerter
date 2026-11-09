import SwiftUI

enum Palette {
    static let coral = Color(red: 0.85, green: 0.47, blue: 0.34)   // ready
    static let amber = Color(red: 0.95, green: 0.68, blue: 0.20)   // needs you
    static let ink = Color.primary
}

// MARK: - Shared list

struct ThreadBoard: View {
    let store: Store
    var compact = false

    var body: some View {
        let attention = store.attention
        let working = store.working
        let caughtUp = Array(store.caughtUp.prefix(compact ? 3 : 6))

        VStack(alignment: .leading, spacing: 0) {
            Header(store: store, readyCount: attention.count, workingCount: working.count, compact: compact)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if attention.isEmpty && working.isEmpty {
                        AllCaughtUp()
                    }
                    if !attention.isEmpty {
                        Section(title: "Ready for you", tint: Palette.coral) {
                            ForEach(attention) { ThreadRow(store: store, thread: $0, emphasized: true, compact: compact) }
                        }
                    }
                    if !working.isEmpty {
                        Section(title: "Working", tint: .secondary) {
                            ForEach(working) { ThreadRow(store: store, thread: $0, emphasized: false, compact: compact) }
                        }
                    }
                    if !caughtUp.isEmpty {
                        Section(title: "Seen", tint: .secondary) {
                            ForEach(caughtUp) { ThreadRow(store: store, thread: $0, emphasized: false, compact: compact, dimmed: true) }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
        }
    }
}

private struct Header: View {
    let store: Store
    let readyCount: Int
    let workingCount: Int
    let compact: Bool
    @State private var hoveringClear = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude threads")
                    .font(.system(size: compact ? 15 : 16, weight: .semibold, design: .rounded))
                Text(summary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            if readyCount > 0 {
                Button {
                    withAnimation(.snappy) { store.markAllSeen() }
                } label: {
                    Text("Clear all")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(.primary.opacity(hoveringClear ? 0.12 : 0.06)))
                }
                .buttonStyle(.plain)
                .onHover { hoveringClear = $0 }
                .help("Mark everything ready as seen")
            }
        }
    }

    private var summary: String {
        var parts: [String] = []
        if readyCount > 0 { parts.append("\(readyCount) ready") }
        if workingCount > 0 { parts.append("\(workingCount) working") }
        return parts.isEmpty ? "Nothing waiting on you" : parts.joined(separator: " · ")
    }
}

private struct Section<Content: View>: View {
    let title: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
            VStack(spacing: 2) { content }
        }
    }
}

private struct AllCaughtUp: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkle")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Palette.coral.opacity(0.8))
            Text("All caught up")
                .font(.system(size: 13, weight: .medium))
            Text("Threads show up here when Claude finishes.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}

// MARK: - Row

struct ThreadRow: View {
    let store: Store
    let thread: ClaudeThread
    let emphasized: Bool
    var compact = false
    var dimmed = false
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusDot(phase: thread.phase, fresh: emphasized)
                .frame(width: 14, height: 14)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(thread.title)
                        .font(.system(size: 13, weight: emphasized ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    RelativeTime(date: thread.finishedAt ?? thread.lastActive)
                }
                HStack(spacing: 5) {
                    Image(systemName: thread.source == .desktop ? "macwindow" : "terminal")
                        .font(.system(size: 9.5, weight: .medium))
                    Text(thread.project)
                        .lineLimit(1)
                    if thread.phase == .needsYou {
                        Text("· needs your input").foregroundStyle(Palette.amber)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                if let detail = thread.detail, !(compact && dimmed) {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary.opacity(0.9))
                        .lineLimit(compact ? 1 : 2)
                        .padding(.top, 1)
                }
            }

            if emphasized && hovering {
                Button {
                    withAnimation(.snappy) { store.markSeen(thread) }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("Mark as seen")
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowFill)
        )
        .opacity(dimmed ? 0.6 : 1)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .onTapGesture { store.open(thread) }
        .help(thread.source == .desktop ? "Open in Claude" : "Jump to terminal")
    }

    private var rowFill: Color {
        if hovering { return .primary.opacity(0.08) }
        if emphasized { return (thread.phase == .needsYou ? Palette.amber : Palette.coral).opacity(0.08) }
        return .clear
    }
}

struct StatusDot: View {
    let phase: ClaudeThread.Phase
    let fresh: Bool

    var body: some View {
        switch phase {
        case .working:
            Spinner()
        case .needsYou:
            ZStack {
                Circle().fill(Palette.amber)
                Image(systemName: "exclamationmark")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: 13, height: 13)
        case .ready:
            if fresh {
                Circle().fill(Palette.coral)
                    .frame(width: 9, height: 9)
                    .shadow(color: Palette.coral.opacity(0.7), radius: 4)
            } else {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct Spinner: View {
    var body: some View {
        TimelineView(.animation) { ctx in
            let angle = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.1) / 1.1 * 360
            Circle()
                .trim(from: 0.08, to: 0.72)
                .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                .frame(width: 11, height: 11)
                .rotationEffect(.degrees(angle))
        }
    }
}

struct RelativeTime: View {
    let date: Date
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            Text(Self.format(ctx.date.timeIntervalSince(date)))
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }

    static func format(_ s: TimeInterval) -> String {
        switch s {
        case ..<60: return "now"
        case ..<3600: return "\(Int(s / 60))m"
        case ..<86400: return "\(Int(s / 3600))h"
        default: return "\(Int(s / 86400))d"
        }
    }
}
