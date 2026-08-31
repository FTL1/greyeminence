import SwiftData
import SwiftUI

/// Pick who was actually on the call, re-analyze from saved audio using
/// their voice stamps, then assign leftover unknown-N clusters.
struct SpeakerReanalyzeSheet: View {
    let meeting: Meeting
    let contacts: [Contact]
    var isWorking: Bool
    var result: MeetingSpeakerRecovery.Result?
    var onRun: ([MeetingSpeakerRecovery.ExpectedSpeaker]) -> Void
    var onAssign: ([Speaker], Speaker, Contact?) -> Void
    var onDismiss: () -> Void

    @State private var selectedIDs: Set<String> = []
    @State private var unknownSelected: Set<Speaker.IdentityKey> = []
    @State private var typedName = ""
    @State private var showContactPicker = false
    @State private var didSeedSelection = false

    private var candidates: [MeetingSpeakerRecovery.ExpectedSpeaker] {
        MeetingSpeakerRecovery.candidates(meeting: meeting, contacts: contacts)
    }

    private var selectedPeople: [MeetingSpeakerRecovery.ExpectedSpeaker] {
        candidates.filter { selectedIDs.contains($0.id) }
    }

    private var unknownRows: [(speaker: Speaker, count: Int, sample: String)] {
        guard let result else { return [] }
        return result.unknownSpeakers.map { speaker in
            let lines = meeting.segments.filter { $0.speaker.matchesIdentity(speaker) }
            let sample = lines.first(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.text
                ?? ""
            return (speaker, lines.count, sample)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if result == nil {
                        peopleSection
                    } else {
                        resultSection
                    }
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(width: 460, height: 540)
        .onAppear {
            guard !didSeedSelection else { return }
            didSeedSelection = true
            selectedIDs = Set(candidates.filter(\.isPreselected).map(\.id))
        }
        .popover(isPresented: $showContactPicker) {
            ContactPicker(
                excludedContacts: [],
                prioritizedContacts: meeting.attendees,
                includeAppleDirectory: true
            ) { contact in
                assignSelectedUnknowns(to: .other(contact.name), contact: contact)
                showContactPicker = false
            }
            .frame(width: 280, height: 320)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Re-analyze speakers")
                .font(.headline)
            Text(result == nil
                 ? "Pick who was actually on this call. Saved voice stamps are used first. Anyone who does not match becomes speaker-1, speaker-2… You stay you."
                 : "Assign leftover unknown voices to someone on the call, a contact, or a typed name. A voice stamp is saved for each assignment.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("People on this call")
                .font(.subheadline.weight(.semibold))
            ForEach(candidates) { person in
                Toggle(isOn: binding(for: person)) {
                    HStack(spacing: 8) {
                        Text(person.name)
                        if person.isMe {
                            Text("you")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if person.hasVoicePrint {
                            Image(systemName: "waveform")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .help("Voice stamp on file")
                        } else {
                            Text("no stamp")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .disabled(person.isMe || isWorking)
            }
            Text("A waveform means this person already has a voice stamp. Unchecked people are not used as matches, so leftover clusters stay unknown instead of being named as someone who was not on the call.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let result {
                Text(result.changed == 0
                     ? "Audio did not change any remote labels."
                     : "Relabeled \(result.changed) remote line\(result.changed == 1 ? "" : "s").")
                    .font(.subheadline)
                if !result.matchedSpeakers.isEmpty {
                    Text("Matched: \(result.matchedSpeakers.map(\.displayName).joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if unknownRows.isEmpty {
                Label("No unmatched voices. Every remote cluster matched a selected voice stamp.", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("Unmatched voices")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button(unknownSelected.count == unknownRows.count ? "Clear" : "Select all") {
                        if unknownSelected.count == unknownRows.count {
                            unknownSelected = []
                        } else {
                            unknownSelected = Set(unknownRows.map { $0.speaker.identityKey })
                        }
                    }
                    .controlSize(.small)
                }
                ForEach(unknownRows, id: \.speaker.identityKey) { row in
                    Toggle(isOn: unknownBinding(row.speaker)) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(row.speaker.displayName)
                                    .font(.body.weight(.semibold))
                                Text(row.count == 1 ? "1 line" : "\(row.count) lines")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !row.sample.isEmpty {
                                Text(row.sample)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }

                Text("Assign selected to")
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 4)

                let known = selectedPeople.filter { !$0.isMe }
                if !known.isEmpty {
                    FlowLayout(spacing: 6, rowAlignment: .center) {
                        ForEach(known) { person in
                            Button(person.name) {
                                assignSelectedUnknowns(to: person.speaker, contact: contact(for: person))
                            }
                            .controlSize(.small)
                            .disabled(unknownSelected.isEmpty)
                        }
                    }
                }

                HStack {
                    Button("Choose contact…") {
                        showContactPicker = true
                    }
                    .controlSize(.small)
                    .disabled(unknownSelected.isEmpty)

                    TextField("Or type a name", text: $typedName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { assignTypedName() }

                    Button("Name") {
                        assignTypedName()
                    }
                    .controlSize(.small)
                    .disabled(unknownSelected.isEmpty || typedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Close") { onDismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            if result == nil {
                Button {
                    onRun(selectedPeople)
                } label: {
                    if isWorking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Re-analyze from audio")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking || selectedPeople.isEmpty)
            }
        }
        .padding(16)
    }

    private func binding(for person: MeetingSpeakerRecovery.ExpectedSpeaker) -> Binding<Bool> {
        Binding(
            get: { person.isMe || selectedIDs.contains(person.id) },
            set: { on in
                if person.isMe { return }
                if on {
                    selectedIDs.insert(person.id)
                } else {
                    selectedIDs.remove(person.id)
                }
            }
        )
    }

    private func unknownBinding(_ speaker: Speaker) -> Binding<Bool> {
        Binding(
            get: { unknownSelected.contains(speaker.identityKey) },
            set: { on in
                if on {
                    unknownSelected.insert(speaker.identityKey)
                } else {
                    unknownSelected.remove(speaker.identityKey)
                }
            }
        )
    }

    private func selectedUnknownSpeakers() -> [Speaker] {
        unknownRows.map(\.speaker).filter { unknownSelected.contains($0.identityKey) }
    }

    private func assignTypedName() {
        let name = typedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let contact = contacts.first { $0.matchesSpeakerName(name) }
        assignSelectedUnknowns(to: .other(contact?.name ?? name), contact: contact)
        typedName = ""
    }

    private func assignSelectedUnknowns(to speaker: Speaker, contact: Contact?) {
        let unknowns = selectedUnknownSpeakers()
        guard !unknowns.isEmpty else { return }
        onAssign(unknowns, speaker, contact)
        unknownSelected = []
    }

    private func contact(for person: MeetingSpeakerRecovery.ExpectedSpeaker) -> Contact? {
        guard let id = person.contactID else { return nil }
        return contacts.first { $0.id == id }
    }
}
