import AppKit
import SwiftUI

struct AskRecipesView: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var recipeStore: RecipeStore
    let isEnabled: Bool
    let onSelect: (String) -> Void

    var body: some View {
        let recipes = recipeStore.all()
        if !recipes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recipes")
                    .font(.ayrvo(13, .semibold))
                    .foregroundStyle(Theme.secondary(scheme))

                FlowLayout(spacing: 8) {
                    ForEach(recipes) { recipe in
                        Button {
                            onSelect(recipe.prompt)
                        } label: {
                            RecipeChip(text: recipe.name)
                        }
                        .buttonStyle(.plain)
                        .disabled(!isEnabled)
                        .opacity(isEnabled ? 1 : 0.45)
                        .contextMenu {
                            Button("Delete recipe", role: .destructive) {
                                recipeStore.delete(id: recipe.id)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct RecipeChip: View {
    @Environment(\.colorScheme) private var scheme
    let text: String

    var body: some View {
        Text(text)
            .font(.ayrvo(12, .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.card(scheme), in: Capsule())
            .overlay {
                Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .foregroundStyle(Theme.heading(scheme))
    }
}
