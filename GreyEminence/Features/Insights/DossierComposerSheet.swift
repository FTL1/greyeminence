import SwiftUI
import SwiftData

struct DossierComposerSheet: View {
    let meeting: Meeting
    var library: [Meeting]
    @Binding var request: DossierRequest
    var onExport: (DossierRequest) -> Void
    @Environment(\.dismiss) private var dismiss

    private var seriesCount: Int {
        DossierFacts.relatedMeetings(to: meeting, library: library).count
    }

    private var speakers: [String] {
        DossierFacts.snapshot(meeting: meeting).speakers
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Create meeting dossier")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create package") {
                    onExport(request)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()
            Form {
                Section {
                    Picker("Audience", selection: audienceKindBinding) {
                        Text("Me").tag(AudienceKind.me)
                        Text("My boss (everyone)").tag(AudienceKind.boss)
                        Text("Everyone / general").tag(AudienceKind.general)
                        Text("One speaker").tag(AudienceKind.person)
                    }
                    if case .person = request.audience {
                        Picker("Speaker", selection: personBinding) {
                            ForEach(speakers, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                    }
                    Picker("Depth", selection: $request.depth) {
                        ForEach(DossierDepth.allCases) { depth in
                            Text(depth.label).tag(depth)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Who and how much")
                } footer: {
                    Text("The written report is filtered for that audience. The chatbot prompt pack still includes every stored fact so a later model does not have to invent.")
                }

                Section {
                    Toggle("Written report", isOn: $request.includeReport)
                    Picker("Format", selection: $request.reportFormat) {
                        ForEach(DossierReportFormat.allCases) { format in
                            Text(format.menuTitle).tag(format)
                        }
                    }
                    .disabled(!request.includeReport)
                    Toggle("Transcript (stored lines only)", isOn: $request.includeTranscript)
                    Toggle("Audio (.m4a)", isOn: $request.includeAudio)
                    Toggle("Screen stills", isOn: $request.includeScreenshots)
                    Toggle("Chatbot prompt pack (no hallucination)", isOn: $request.includePromptPackage)
                } header: {
                    Text("Include")
                } footer: {
                    Text("Prompt pack is PROMPT.md + meeting.json for a separate Grok (or other) chat. Audio for one speaker is that person's time ranges concatenated; overlapping voices can still be heard. There is no movie of the call.")
                }

                Section {
                    if seriesCount > 1 {
                        Toggle("Series dossier (\(seriesCount) meetings)", isOn: $request.includeSeries)
                    }
                    Toggle("One-pagers for every speaker + general", isOn: $request.onePagers)
                } header: {
                    Text("Packages")
                } footer: {
                    Text("One-pagers is a zip of a short page per speaker plus _general.md. Series uses the calendar series when linked, otherwise meetings that share the first two name words.")
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 520, minHeight: 560)
        .onAppear {
            if case .person(let name) = request.audience, name.isEmpty, let first = speakers.first {
                request.audience = .person(first)
            }
        }
    }

    private enum AudienceKind: String, Hashable {
        case me, boss, general, person
    }

    private var audienceKindBinding: Binding<AudienceKind> {
        Binding(
            get: {
                switch request.audience {
                case .me: .me
                case .boss: .boss
                case .general: .general
                case .person: .person
                }
            },
            set: { kind in
                switch kind {
                case .me: request.audience = .me
                case .boss: request.audience = .boss
                case .general: request.audience = .general
                case .person: request.audience = .person(speakers.first ?? "")
                }
            }
        )
    }

    private var personBinding: Binding<String> {
        Binding(
            get: {
                if case .person(let name) = request.audience { return name }
                return speakers.first ?? ""
            },
            set: { request.audience = .person($0) }
        )
    }
}
