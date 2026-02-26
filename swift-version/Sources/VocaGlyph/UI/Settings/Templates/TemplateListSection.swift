import SwiftUI
import SwiftData

// MARK: - TemplateListSection

/// Template picker UI. Owns `@Query` for templates and presents the editor
/// as a custom floating overlay card (matching the app's delete-confirmation style).
struct TemplateListSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<PostProcessingTemplate> { $0.name != "Raw — No Processing" },
        sort: \PostProcessingTemplate.createdAt
    ) private var templates: [PostProcessingTemplate]

    @AppStorage(TemplateSeederService.activeTemplateKey) private var activeTemplateIdString: String = ""

    /// Called when the user taps Edit on a template. Parent handles presenting the editor.
    let onEdit: (PostProcessingTemplate) -> Void
    /// Called when the user taps "New Template". Parent handles presenting the card.
    let onAddTemplate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Refinement Template")
                .fontWeight(.semibold)
                .foregroundStyle(Theme.navy)
            Text("Choose a template that defines how the AI refines your text.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted)

            if templates.isEmpty {
                Text("No templates found. Restart the app to seed defaults.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
            } else {
                templateList
            }

            Button {
                onAddTemplate()
            } label: {
                Label("New Template", systemImage: "plus.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    @ViewBuilder
    private var templateList: some View {
        VStack(spacing: 0) {
            ForEach(templates) { template in
                templateRow(template)
                if template.id != templates.last?.id {
                    Divider().padding(.horizontal, 12)
                }
            }
        }
        .background(Theme.background)
        .clipShape(.rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.textMuted.opacity(0.2), lineWidth: 1))
    }

    @ViewBuilder
    private func templateRow(_ template: PostProcessingTemplate) -> some View {
        let isActive = activeTemplateIdString == template.id.uuidString
        HStack {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? Theme.accent : Theme.textMuted)

            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .fontWeight(isActive ? .semibold : .regular)
                    .foregroundStyle(Theme.navy)
                if !template.templateDescription.isEmpty {
                    Text(template.templateDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted)
                }
            }

            Spacer()

            Button("Edit") { onEdit(template) }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            activeTemplateIdString = template.id.uuidString
            Logger.shared.info("Settings: Active template changed to '\(template.name)'")
        }
    }
}
