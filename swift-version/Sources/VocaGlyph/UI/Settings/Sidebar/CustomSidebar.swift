import SwiftUI

struct CustomSidebar: View {
    @Binding var selectedTab: SettingsTab?

    /// Reads the version directly from Info.plist — the same source Sparkle uses.
    /// Displays as "v1.0 (1)" — marketing version + build number.
    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(version) (\(build))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Padding for native macOS traffic lights (red/yellow/green buttons)
            Spacer().frame(height: 60)

            // App Identity
            HStack(spacing: 24) {
                if let imgUrl = Bundle.module.url(forResource: "appicon", withExtension: "png"),
                   let nsImage = NSImage(contentsOf: imgUrl) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                } else {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Theme.accent, Theme.navy], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 40, height: 40)
                            .opacity(0.8)
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 16).bold())
                            .foregroundStyle(.white)
                    }
                }
                Text("VocaGlyph")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.navy)
            }
            .padding(.leading, 16)
            .padding(.bottom, 24)

            // Navigation Links
            VStack(spacing: 4) {
                SidebarItemView(title: "General", icon: "gearshape.fill", tab: .general, selectedTab: $selectedTab)
                SidebarItemView(title: "History", icon: "clock.arrow.circlepath", tab: .history, selectedTab: $selectedTab)
                SidebarItemView(title: "Model", icon: "brain.head.profile", tab: .model, selectedTab: $selectedTab)
                SidebarItemView(title: "Writing Assistant", icon: "wand.and.stars", tab: .textProcessing, selectedTab: $selectedTab, showExperimentalBadge: false)
            }
            .padding(.horizontal, 6)

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text("Under Development")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.accent)
                Text(appVersionString)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }
}
