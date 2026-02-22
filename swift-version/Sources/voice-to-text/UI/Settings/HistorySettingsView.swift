import SwiftUI
import SwiftData

// MARK: - Context Menu Model
struct HistoryMenuState: Identifiable {
    let id = UUID()
    let item: TranscriptionItem
    /// Frame of the kebab button in the HistorySettingsView coordinate space
    let buttonFrame: CGRect
}

struct HistorySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TranscriptionItem.timestamp, order: .reverse) private var items: [TranscriptionItem]
    @State private var searchText = ""
    @State private var activeMenu: HistoryMenuState? = nil
    @State private var itemToDelete: TranscriptionItem? = nil

    var filteredItems: [TranscriptionItem] {
        if searchText.isEmpty {
            return items
        } else {
            return items.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var groupedItems: [(String, [TranscriptionItem])] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none

        let groups = Dictionary(grouping: filteredItems) { item -> String in
            if calendar.isDateInToday(item.timestamp) {
                return "TODAY"
            } else if calendar.isDateInYesterday(item.timestamp) {
                return "YESTERDAY"
            } else {
                return formatter.string(from: item.timestamp).uppercased()
            }
        }

        let sortedGroups = groups.sorted { (group1, group2) -> Bool in
            guard let date1 = group1.value.first?.timestamp,
                  let date2 = group2.value.first?.timestamp else { return false }
            return date1 > date2
        }

        return sortedGroups
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 32) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Transcription History")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.navy)
                    Text("Manage and review your recent dictations")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textMuted)
                }
                .padding(.horizontal, 40)
                .padding(.top, 40)

                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Theme.textMuted)
                    TextField("Search history...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.navy)
                        .tint(Theme.navy)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Theme.textMuted)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(10)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.textMuted.opacity(0.2), lineWidth: 1))
                .padding(.horizontal, 40)

                if filteredItems.isEmpty {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("No transcriptions found")
                                .foregroundColor(Theme.textMuted)
                            Spacer()
                        }
                        Spacer()
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(groupedItems, id: \.0) { group in
                                VStack(alignment: .leading, spacing: 0) {
                                    // Date Header
                                    HStack {
                                        Spacer()
                                        Text(group.0)
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(Theme.textMuted)
                                            .tracking(1.0)
                                        Spacer()
                                    }
                                    .padding(.vertical, 12)

                                    Divider().background(Theme.textMuted.opacity(0.1))

                                    // Items
                                    ForEach(group.1) { item in
                                        HistoryRowView(
                                            item: item,
                                            isMenuOpen: activeMenu?.item.id == item.id,
                                            onCopy: { copyToClipboard(text: item.text) },
                                            onDelete: { deleteItem(item) },
                                            onMenuToggle: { buttonFrame in
                                                if activeMenu?.item.id == item.id {
                                                    activeMenu = nil
                                                } else {
                                                    activeMenu = HistoryMenuState(item: item, buttonFrame: buttonFrame)
                                                }
                                            }
                                        )

                                        if item.id != group.1.last?.id {
                                            Divider().background(Theme.textMuted.opacity(0.1))
                                                .padding(.vertical, 8)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.bottom, 40)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Dismiss menu on background tap
            .contentShape(Rectangle())
            .onTapGesture {
                if activeMenu != nil { activeMenu = nil }
            }

            // MARK: Floating action menu overlay
            if let menu = activeMenu {
                HistoryActionMenu(
                    item: menu.item,
                    buttonFrame: menu.buttonFrame,
                    onRetranscribe: {
                        activeMenu = nil
                    },
                    onShare: {
                        activeMenu = nil
                        let sharingPicker = NSSharingServicePicker(items: [menu.item.text])
                        if let nsView = NSApp.keyWindow?.contentView {
                            sharingPicker.show(relativeTo: .zero, of: nsView, preferredEdge: .minY)
                        }
                    },
                    onDelete: {
                        activeMenu = nil
                        itemToDelete = menu.item
                    }
                )
            }

            // MARK: Delete Confirmation Overlay
            if let item = itemToDelete {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            itemToDelete = nil
                        }
                    }

                CustomConfirmationDialog(
                    title: "Are you sure you want to delete this transcript?",
                    message: "Once deleted it cannot be recovered",
                    confirmTitle: "Yes, delete it",
                    cancelTitle: "Cancel",
                    onConfirm: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            deleteItem(item)
                            itemToDelete = nil
                        }
                    },
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            itemToDelete = nil
                        }
                    }
                )
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .coordinateSpace(name: "historyView")
        .animation(.easeInOut(duration: 0.2), value: itemToDelete != nil)
    }

    private func copyToClipboard(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func deleteItem(_ item: TranscriptionItem) {
        modelContext.delete(item)
        try? modelContext.save()
    }
}

// MARK: - Floating Action Menu Card
struct HistoryActionMenu: View {
    let item: TranscriptionItem
    let buttonFrame: CGRect
    let onRetranscribe: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void

    private let cardHeight: CGFloat = 148
    private let cardWidth: CGFloat = 200
    private let gap: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let totalHeight = proxy.size.height

            // Place card just below the button
            let idealY = buttonFrame.maxY + gap
            let clampedY = max(8, min(idealY, totalHeight - cardHeight - 8))

            // Right-align card to the gray hover row box's right edge.
            // The row has .padding(.horizontal, 8), so the gray box extends 8pt
            // past the button's right edge (buttonFrame.maxX).
            let rowRightEdge = buttonFrame.maxX + 8
            let cardX = rowRightEdge - cardWidth

            VStack(alignment: .leading, spacing: 0) {
                menuRow(
                    icon: "arrow.triangle.2.circlepath",
                    label: "Retranscribe",
                    color: Theme.navy,
                    action: onRetranscribe
                )
                Divider().padding(.horizontal, 12)
                menuRow(
                    icon: "square.and.arrow.up",
                    label: "Share",
                    color: Theme.navy,
                    action: onShare
                )
                Divider().padding(.horizontal, 12)
                menuRow(
                    icon: "trash",
                    label: "Delete transcript",
                    color: .red,
                    action: onDelete
                )
            }
            .frame(width: cardWidth)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.14), radius: 20, x: 0, y: 6)
            .shadow(color: Color.black.opacity(0.07), radius: 6, x: 0, y: 2)
            .offset(x: cardX, y: clampedY)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.92).combined(with: .opacity),
                removal: .scale(scale: 0.92).combined(with: .opacity)
            ))
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: clampedY)
        }
    }

    @ViewBuilder
    private func menuRow(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .foregroundStyle(color)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowButtonStyle())
    }
}

// MARK: - Button Style with Hover
struct MenuRowButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                isHovering || configuration.isPressed
                    ? Color.gray.opacity(0.08)
                    : Color.clear
            )
            .onHover { hovering in
                isHovering = hovering
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }
}

// MARK: - Row View
struct HistoryRowView: View {
    let item: TranscriptionItem
    let isMenuOpen: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void
    /// Called with the kebab button's frame in the HistorySettingsView coordinate space
    let onMenuToggle: (_ buttonFrame: CGRect) -> Void

    @State private var isHovering = false
    @State private var isCopied = false

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: item.timestamp)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(timeString)
                .font(.system(size: 13))
                .foregroundColor(Theme.textMuted)
                .frame(width: 70, alignment: .leading)

            Text(item.text)
                .font(.system(size: 14))
                .foregroundColor(Theme.navy)
                .lineLimit(nil)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Button(action: {
                    onCopy()
                    withAnimation(.easeInOut(duration: 0.2)) { isCopied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation(.easeInOut(duration: 0.2)) { isCopied = false }
                    }
                }) {
                    if isCopied {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "doc.on.clipboard")
                            .foregroundColor(Theme.textMuted)
                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .help("Copy to Clipboard")

                // Kebab button — captures its frame to pass button position to parent
                GeometryReader { geo in
                    Button(action: {
                        let frame = geo.frame(in: .named("historyView"))
                        onMenuToggle(frame)
                    }) {
                        VStack(spacing: 3) {
                            Circle().fill(isMenuOpen ? Theme.navy.opacity(0.6) : Theme.navy)
                                .frame(width: 3.5, height: 3.5)
                            Circle().fill(isMenuOpen ? Theme.navy.opacity(0.6) : Theme.navy)
                                .frame(width: 3.5, height: 3.5)
                            Circle().fill(isMenuOpen ? Theme.navy.opacity(0.6) : Theme.navy)
                                .frame(width: 3.5, height: 3.5)
                        }
                        .frame(width: 20, height: 24)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("More Actions")
                }
                .frame(width: 20, height: 24)
            }
            .opacity(isCopied || isMenuOpen ? 1.0 : (isHovering ? 1.0 : 0.4))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(isHovering ? Theme.textMuted.opacity(0.05) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { hovering in isHovering = hovering }
    }
}
