import SwiftUI

struct TopicDetailPanel: View {
    let viewModel: TopicMapViewModel
    var onMeetingSelected: ((Meeting) -> Void)?

    var body: some View {
        if let node = viewModel.selectedNode {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text(node.label)
                            .font(.title3.weight(.bold))
                        Text("\(node.meetingCount) meeting\(node.meetingCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)

                    Divider()

                    // Meetings
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Meetings")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)

                        ForEach(viewModel.selectedMeetings, id: \.id) { meeting in
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

                    if !viewModel.selectedNeighbours.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Connected topics")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)

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
                }
                .padding(.vertical)
            }
        }
    }
}
