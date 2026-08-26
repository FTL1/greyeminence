import SwiftUI
import SwiftData

/// Ask, as a conversation. The centre is the dialogue; the conversation list
/// sits on the left and the retrieved snippets go in the app's right-hand
/// inspector slot (see `ContentView`), where transcripts live everywhere else.
struct AskView: View {
    @AppStorage("embeddingProvider") private var providerRaw: String = EmbeddingProvider.nlEmbedding.rawValue
    @AppStorage("askDateFilter") private var defaultDateFilterRaw: String = AskDateFilter.anyTime.rawValue
    @AppStorage("askShowConversations") private var showConversations: Bool = true

    @Bindable var viewModel: AskViewModel

    @State private var renaming: AskConversation?
    @State private var renameText: String = ""

    private var provider: EmbeddingProvider {
        EmbeddingProvider(rawValue: providerRaw) ?? .nlEmbedding
    }

    /// The open conversation's filter, or the saved default for a thread that
    /// hasn't been created yet.
    private var dateFilter: AskDateFilter {
        viewModel.currentConversation?.dateFilter
            ?? AskDateFilter(rawValue: defaultDateFilterRaw)
            ?? .anyTime
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                if showConversations {
                    conversationSidebar
                        .frame(width: 210)
                    Divider()
                }
                AskChatView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .alert("Rename conversation", isPresented: renameBinding) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") {
                if let renaming { viewModel.rename(renaming, to: renameText) }
                renaming = nil
            }
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showConversations.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(.bordered)
            .help(showConversations ? "Hide conversations" : "Show conversations")

            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.currentConversation?.title ?? "New conversation")
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Menu {
                ForEach(AskDateFilter.allCases) { option in
                    Button {
                        // Retrieval is per-turn, so this applies from the next
                        // question on rather than re-running what's already
                        // been asked.
                        defaultDateFilterRaw = option.rawValue
                        viewModel.setDateFilter(option)
                    } label: {
                        if option == dateFilter {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                Label(dateFilter.label, systemImage: "calendar")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Limit new questions to meetings in this range")

            Button {
                viewModel.startNewConversation()
            } label: {
                Label("New", systemImage: "square.and.pencil")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .help("Start a new conversation (⇧⌘N)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.background)
    }

    private var subtitle: String {
        guard let conversation = viewModel.currentConversation, !conversation.turns.isEmpty else {
            return "Grounded in your transcripts and screen shares · \(provider.shortLabel)"
        }
        let turns = conversation.turns.count
        let sources = conversation.sources.count
        return "\(turns) \(turns == 1 ? "question" : "questions") · \(sources) \(sources == 1 ? "source" : "sources") · \(provider.shortLabel)"
    }

    // MARK: - Conversation sidebar

    @ViewBuilder
    private var conversationSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Conversations")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !viewModel.conversations.isEmpty {
                    Button {
                        viewModel.deleteAll()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Delete all conversations")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)

            Divider()

            if viewModel.conversations.isEmpty {
                Text("Your conversations will be listed here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.sortedConversations) { conversation in
                            conversationRow(conversation)
                        }
                    }
                    .padding(6)
                }
            }
        }
    }

    @ViewBuilder
    private func conversationRow(_ conversation: AskConversation) -> some View {
        let isCurrent = conversation.id == viewModel.selectedConversationID
        Button {
            viewModel.select(conversation)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    Text(conversation.updatedAt, format: .relative(presentation: .numeric))
                    if conversation.turns.count > 1 {
                        Text("·")
                        Text("\(conversation.turns.count) turns")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                isCurrent ? Color.accentColor.opacity(0.15) : Color.clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                renameText = conversation.title
                renaming = conversation
            } label: {
                Label("Rename…", systemImage: "pencil")
            }
            Button(role: .destructive) {
                viewModel.delete(conversation)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
