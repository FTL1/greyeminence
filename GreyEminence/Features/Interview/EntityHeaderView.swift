import SwiftUI

/// Hero header for editor screens — replaces the buried-in-a-Section
/// anti-pattern with a tinted icon tile + inline title TextField.
///
/// Drop in *above* a List/ScrollView in a parent VStack — never as a
/// list row, since `.insetGrouped` insets and row reordering fight the
/// full-bleed treatment.
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            iconTile
            VStack(alignment: .leading, spacing: 4) {
                TextField(namePrompt, text: $name)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                if !description.isEmpty || descriptionFocused {
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

    @ViewBuilder
    private var heroIconLabel: some View {
        Image(systemName: resolvedIcon)
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 56, height: 56)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SheetHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}
