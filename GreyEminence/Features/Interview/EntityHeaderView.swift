import SwiftUI

/// Hero header for "you're editing a named thing" screens. Replaces the
/// anti-pattern of a `Section("Template Details") { … }` Form section
/// with a tiny icon + body-font name field — that read like generic
/// chrome and made the entity name feel buried.
///
/// Layout: large tinted icon (44pt symbol in a 56×56 rounded tile)
/// alongside an inline title-styled name TextField and a callout-sized
/// description TextField. The name *is* the title — no mode switch, no
/// pencil button, just a TextField with `.title2.weight(.semibold)`
/// styling. Description hides when empty and unfocused.
///
/// Drop in *above* a List/ScrollView in a parent VStack — never as a
/// list row, since `.insetGrouped` insets and row reordering both fight
/// the full-bleed treatment.
struct EntityHeaderView: View {
    @Binding var name: String
    @Binding var description: String
    @Binding var iconName: String
    var iconFallback: String
    var tint: Color = .cyan
    var namePrompt: String
    var descriptionPrompt: String = "Add a description"
    /// Non-nil = the icon is tappable and presents `PhaseIconMenu`.
    /// Nil = read-only glyph (e.g. a candidate avatar).
    var iconCatalog: [String]? = PhaseIconCatalog.symbols

    @FocusState private var descriptionFocused: Bool

    private var resolvedIcon: String {
        iconName.isEmpty ? iconFallback : iconName
    }

    private var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            iconTile
            VStack(alignment: .leading, spacing: 4) {
                TextField(namePrompt, text: $name)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                if !trimmedDescription.isEmpty || descriptionFocused {
                    TextField(descriptionPrompt, text: $description, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1...3)
                        .focused($descriptionFocused)
                } else if !descriptionPrompt.isEmpty {
                    Button {
                        descriptionFocused = true
                    } label: {
                        Text(descriptionPrompt)
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.6)
        }
    }

    @ViewBuilder
    private var iconTile: some View {
        if iconCatalog != nil {
            PhaseIconMenu(
                current: resolvedIcon,
                tint: tint,
                onPick: { sym in iconName = sym },
                label: { heroIconLabel }
            )
            .help("Pick icon")
        } else {
            heroIconLabel
        }
    }

    private var heroIconLabel: AnyView {
        AnyView(
            Image(systemName: resolvedIcon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 56, height: 56)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        )
    }
}
