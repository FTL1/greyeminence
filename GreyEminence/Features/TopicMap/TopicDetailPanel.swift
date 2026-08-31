import SwiftUI

struct TopicDetailPanel: View {
    let viewModel: TopicMapViewModel
    var onMeetingSelected: ((Meeting) -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let node = viewModel.selectedNode {
                    topicHeader(node)
                    peopleSection
                    speakersSection
                    actionsSection
                    meetingsSection
                    connectedTopicsSection
                } else if let person = viewModel.selectedPerson {
                    personHeader(person)
                    topTopicsSection
                    actionsSection
                    meetingsSection
                } else if let speaker = viewModel.selectedSpeaker {
                    speakerHeader(speaker)
                    topTopicsSection
                    actionsSection
                    meetingsSection
                }
            }
            .padding(.vertical)
        }
    }

    private func topicHeader(_ node: TopicNode) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(node.label)
                .font(.title3.weight(.bold))
            Text("\(node.meetingCount) meeting\(node.meetingCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private func personHeader(_ person: TopicMapRoster.Person) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(person.name)
                .font(.title3.weight(.bold))
            Text("\(person.meetingCount) meeting\(person.meetingCount == 1 ? "" : "s") · \(person.actionCount) action\(person.actionCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private func speakerHeader(_ speaker: TopicMapRoster.SpeakerRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(speaker.displayName)
                .font(.title3.weight(.bold))
            Text("\(speaker.talkPercent)% of talk time · \(speaker.meetingCount) meeting\(speaker.meetingCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var peopleSection: some View {
        let people = viewModel.peopleForSelection
        if !people.isEmpty {
            Divider()
            sectionHeader("People discussed")
            ForEach(people.prefix(8)) { person in
                Button {
                    viewModel.setSelectedPerson(person.id)
                } label: {
                    HStack(spacing: 8) {
                        Text(person.name)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Spacer()
                        Text("\(person.meetingCount)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show topics \(person.name) appeared in")
            }
        }
    }

    @ViewBuilder
    private var speakersSection: some View {
        let speakers = viewModel.speakersForSelection
        if !speakers.isEmpty {
            Divider()
            sectionHeader("Who talked")
            ForEach(speakers.prefix(8)) { speaker in
                Button {
                    viewModel.setSelectedSpeaker(speaker.id)
                } label: {
                    HStack(spacing: 8) {
                        Text(speaker.displayName)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Spacer()
                        Text("\(speaker.talkPercent)%")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show topics \(speaker.displayName) talked about")
            }
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        let items = viewModel.actionsForSelection
        if !items.isEmpty {
            Divider()
            sectionHeader("Action items")
            ForEach(items.prefix(10)) { item in
                Button {
                    if let meeting = item.meeting {
                        onMeetingSelected?(meeting)
                    }
                } label: {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 10))
                            .foregroundStyle(item.isCompleted ? .green : .orange)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.text)
                                .font(.caption)
                                .lineLimit(2)
                                .strikethrough(item.isCompleted)
                            if let who = item.displayAssignee {
                                Text(who)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var topTopicsSection: some View {
        let topics = viewModel.topTopicsForSelection
        if !topics.isEmpty {
            Divider()
            sectionHeader("Talked about most")
            ForEach(Array(topics.enumerated()), id: \.offset) { _, topic in
                Button {
                    viewModel.setSelectedTopic(topic.label.lowercased())
                } label: {
                    HStack(spacing: 8) {
                        Text(topic.label)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Spacer()
                        Text("\(topic.count)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var meetingsSection: some View {
        let meetings = viewModel.selectedMeetings
        if !meetings.isEmpty {
            Divider()
            sectionHeader("Meetings")
            ForEach(meetings, id: \.id) { meeting in
                Button {
                    onMeetingSelected?(meeting)
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.primary.opacity(0.3))
                            .frame(width: 5, height: 5)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(meeting.title)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text(meeting.date, style: .date)
                                Text(meeting.formattedDuration)
                            }
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var connectedTopicsSection: some View {
        if !viewModel.selectedNeighbours.isEmpty {
            Divider()
            sectionHeader("Connected topics")
            ForEach(viewModel.selectedNeighbours) { neighbour in
                Button {
                    viewModel.setSelectedTopic(neighbour.id)
                } label: {
                    HStack(spacing: 8) {
                        Text(neighbour.label)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Spacer()
                        Text("\(neighbour.weight)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("shared")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal)
    }
}
