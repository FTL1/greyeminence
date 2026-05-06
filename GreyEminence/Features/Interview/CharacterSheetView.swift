import SwiftUI

/// D&D-styled candidate dossier panel. Renders the `CharacterSheet` produced
/// by `ResumeAnalyzer` with class header, level, six attribute boxes, and
/// short feat/specialization lists. Used in `CandidateDetailView` below the
/// resume row.
struct CharacterSheetView: View {
    let sheet: CharacterSheet

    /// `Color.mix(with:by:)` is macOS 15+, but we deploy to 14.4. Define
    /// the parchment-on-brown text color literally.
    private static let darkBrown = Color(red: 0.35, green: 0.22, blue: 0.10)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            classHeader
            attributesGrid
            if !sheet.specializations.isEmpty {
                specializationsRow
            }
            if !sheet.notableFeats.isEmpty {
                feats
            }
        }
        .padding(14)
        .background(parchmentBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.brown.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Header

    private var classHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sheet.className)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Self.darkBrown)
                if let desc = sheet.classDescription, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("LVL \(sheet.level)")
                    .font(.system(size: 16, weight: .heavy, design: .serif))
                    .foregroundStyle(Self.darkBrown)
            }
        }
    }

    // MARK: - Attributes

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    private var attributesGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(sheet.attributes) { attribute in
                attributeBox(attribute)
            }
        }
    }

    private func attributeBox(_ attribute: DnDAttribute) -> some View {
        VStack(spacing: 2) {
            Text(attribute.abbreviation)
                .font(.system(size: 9, weight: .heavy, design: .serif))
                .foregroundStyle(.secondary)
                .tracking(1.2)
            Text("\(attribute.value)")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(attributeColor(attribute.value))
            Text(attribute.name)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.brown.opacity(0.25), lineWidth: 0.5)
        )
        .help(attribute.descriptor)
    }

    /// 8 (low) -> red. 10 (median) -> neutral. 18 (max) -> bright green.
    private func attributeColor(_ value: Int) -> Color {
        switch value {
        case ..<9: .red
        case 9...11: .secondary
        case 12...14: .blue
        case 15...16: .green
        default: Color(red: 0.45, green: 0.7, blue: 0.2)
        }
    }

    // MARK: - Specializations

    private var specializationsRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Proficiencies")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Self.darkBrown)
                .tracking(0.5)
            FlowLayout(spacing: 4) {
                ForEach(sheet.specializations, id: \.self) { spec in
                    Text(spec)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.brown.opacity(0.15), in: Capsule())
                        .foregroundStyle(Self.darkBrown)
                }
            }
        }
    }

    // MARK: - Feats

    private var feats: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notable Feats")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Self.darkBrown)
                .tracking(0.5)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(sheet.notableFeats, id: \.self) { feat in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 9))
                            .foregroundStyle(.brown.opacity(0.6))
                            .padding(.top, 3)
                        Text(feat)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Background

    private var parchmentBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.99, green: 0.96, blue: 0.88),
                Color(red: 0.95, green: 0.91, blue: 0.80)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
