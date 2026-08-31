import SwiftUI
import SwiftData

/// One strip: who is in the meeting. Click a name to hide or show their lines.
struct SpeakerRosterBar: View {
    var roster: SpeakerRoster
    var segments: [TranscriptSegment] = []
    var onAssignVoice: ((Speaker, SpeakerRoster.Seat) -> Void)?
    var onTagName: ((SpeakerRoster.Seat) -> Void)?
    var onAddedPerson: ((SpeakerRoster.Seat, Contact?) -> Void)?
    var onEnrollVoicePrint: ((Speaker) -> Void)?

    @Query(sort: \Contact.name) private var contacts: [Contact]
    @State private var showAdd = false
    @State private var addName = ""
    @State private var showContactPicker = false

    private var heard: [Speaker] {
        roster.unboundVoices(in: segments)
    }

    private var talkShareByKey: [Speaker.IdentityKey: Int] {
        SpeakerTalkShare.percents(in: segments)
    }

    private var spokenSeats: [SpeakerRoster.Seat] {
        roster.spokenSeats(in: segments)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 6, rowAlignment: .center) {
                ForEach(spokenSeats) { seat in
                    seatChip(seat)
                }
                ForEach(heard, id: \.identityKey) { voice in
                    heardChip(voice)
                }
                addPersonButton
                if !roster.hiddenSpeakers.isEmpty || roster.isolatedSpeaker != nil {
                    Button("Show all") {
                        roster.showAllSpeakers()
                    }
                    .controlSize(.small)
                    .helpTip(.showAllSpeakers)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let paint = roster.paintSeat {
                paintBanner(paint)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .onAppear {
            SpeakerPalette.assign(contacts: Array(contacts))
        }
        .popover(isPresented: $showAdd) {
            addPopover
        }
        .popover(isPresented: $showContactPicker) {
            ContactPicker(excludedContacts: []) { contact in
                let seat = roster.addSeat(name: contact.name, contactID: contact.id)
                onAddedPerson?(seat, contact)
                showContactPicker = false
            }
            .frame(width: 280, height: 320)
        }
    }

    private var addPersonButton: some View {
        Button {
            addName = ""
            showAdd = true
        } label: {
            Image(systemName: "plus.circle")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .helpTip(.addPerson)
    }

    private func color(for speaker: Speaker) -> Color {
        SpeakerPalette.color(for: speaker, contacts: Array(contacts))
    }

    private func seatChip(_ seat: SpeakerRoster.Seat) -> some View {
        let painting = roster.paintSeatID == seat.id
        let isolationTarget = roster.isolationSpeaker(for: seat, in: segments)
        let spoken = isolationTarget != nil || segments.contains { seat.binds($0.speaker) }
        let hidden = roster.isSeatHidden(seat, in: segments)
        let percent = roster.talkSharePercent(for: seat, percents: talkShareByKey, in: segments)
        let color = color(for: seat.speaker)
        let on = spoken && !hidden

        return HStack(spacing: 0) {
            Button {
                roster.toggleHidden(seat: seat, in: segments)
            } label: {
                HStack(spacing: 5) {
                    Text(initials(seat.name))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background((on ? color : Color.secondary.opacity(0.45)), in: Circle())
                    Text(seat.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(on ? color : .secondary)
                        .lineLimit(1)
                    if seat.isMe {
                        Text("you")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let percent {
                        Text("\(percent)%")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(on ? color : Color.secondary.opacity(0.7))
                    }
                }
                .padding(.leading, 4)
                .padding(.vertical, 3)
            }
            .buttonStyle(.plain)
            .help(hidden
                  ? "\(seat.name) is hidden. Click to show their lines. Grey = off."
                  : "Click to hide \(seat.name). Grey = off, color = on. Right-click to assign, lock, or enroll.")
            .opacity(on ? 1 : 0.55)

            lockButton(for: seat, color: color)
        }
        .background(
            (painting ? color.opacity(0.22) : Color.primary.opacity(on ? 0.06 : 0.03)),
            in: Capsule()
        )
        .overlay(
            Capsule().strokeBorder(painting ? color : Color.clear, lineWidth: 1.25)
        )
        .contextMenu {
            Button(hidden ? "Show \(seat.name)" : "Hide \(seat.name)") {
                roster.toggleHidden(seat: seat, in: segments)
            }
            Button(painting ? "Stop tagging lines" : "Tag lines as \(seat.name)") {
                roster.paintSeatID = painting ? nil : seat.id
            }
            if onEnrollVoicePrint != nil {
                Button("Enroll voice print") {
                    onEnrollVoicePrint?(isolationTarget ?? seat.speaker)
                }
            }
            if !seat.isMe {
                Button(seat.isLocked ? "Unlock ID" : "Lock this ID") {
                    roster.setLocked(seat.id, !seat.isLocked)
                }
                Button("Remove from roster", role: .destructive) {
                    roster.removeSeat(seat.id)
                }
            }
        }
    }

    private func heardChip(_ voice: Speaker) -> some View {
        let hidden = roster.isHidden(voice)
        let namedSeats = roster.seats.filter { !$0.isMe }
        let percent = talkShareByKey[voice.identityKey]
        let color = color(for: voice)
        return HStack(spacing: 0) {
            Button {
                roster.toggleHidden(voice)
            } label: {
                HStack(spacing: 5) {
                    Text(initials(voice.displayName))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(Color.secondary.opacity(0.55), in: Circle())
                    Text(voice.displayName)
                        .font(.caption)
                        .foregroundStyle(hidden ? .tertiary : .secondary)
                    if let percent {
                        Text("\(percent)%")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
            }
            .buttonStyle(.plain)
            .helpTip(.heardChip)
            .opacity(hidden ? 0.5 : 1)
        }
        .background(Color.primary.opacity(0.04), in: Capsule())
        .overlay(
            Capsule().strokeBorder(
                Color.secondary.opacity(0.35),
                style: StrokeStyle(lineWidth: 1, dash: [3, 2])
            )
        )
        .contextMenu {
            Button(hidden ? "Show \(voice.displayName)" : "Hide \(voice.displayName)") {
                roster.toggleHidden(voice)
            }
            ForEach(namedSeats) { seat in
                Button("This is \(seat.name)") {
                    onAssignVoice?(voice, seat)
                }
            }
            Button("Add as new person") {
                let seat = roster.addSeat(name: voice.displayName)
                onAssignVoice?(voice, seat)
                onAddedPerson?(seat, nil)
            }
        }
    }

    @ViewBuilder
    private func lockButton(for seat: SpeakerRoster.Seat, color: Color) -> some View {
        if seat.isMe {
            Image(systemName: "lock.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 3)
                .padding(.vertical, 4)
                .helpTip(.lockMe)
        } else {
            Button {
                roster.setLocked(seat.id, !seat.isLocked)
            } label: {
                Image(systemName: seat.isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(seat.isLocked ? color : .secondary)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(seat.isLocked
                  ? "Unlock \(seat.name) so later lines can be retagged."
                  : "Lock \(seat.name) so later lines stay on this person.")
        }
    }

    private func paintBanner(_ paint: SpeakerRoster.Seat) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "paintbrush.pointed.fill")
                .foregroundStyle(color(for: paint.speaker))
            Text("Tagging as \(paint.name). Click a line to assign it.")
                .font(.caption)
            Spacer()
            Button("Done tagging") {
                roster.paintSeatID = nil
            }
            .controlSize(.small)
        }
        .padding(6)
        .background(color(for: paint.speaker).opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    private var addPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add a person")
                .font(.headline)
            Text("Pre-tag who you expect. When they talk, assign their voice and click the lock on their name.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Name", text: $addName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submitTypedName() }
            HStack {
                Button("Choose contact…") {
                    showAdd = false
                    showContactPicker = true
                }
                Spacer()
                Button("Add") { submitTypedName() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(addName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private func submitTypedName() {
        let name = addName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let seat = roster.addSeat(name: name)
        onAddedPerson?(seat, nil)
        showAdd = false
        addName = ""
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}
