import SwiftUI

struct SidebarItemView: View {
    let title: String
    let icon: String
    let tab: SettingsTab
    @Binding var selectedTab: SettingsTab?
    var showExperimentalBadge: Bool = false

    var isSelected: Bool { selectedTab == tab }

    var body: some View {
        Button(action: {
            selectedTab = tab
        }) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Theme.navy : Theme.textMuted)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 14).weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Theme.navy : Theme.textMuted)

                Spacer()

                if showExperimentalBadge {
                    Image(systemName: "flask.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.orange.opacity(0.8))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(isSelected ? Theme.accent.opacity(0.15) : Color.clear)
            .clipShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            if isHovering && !isSelected {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
