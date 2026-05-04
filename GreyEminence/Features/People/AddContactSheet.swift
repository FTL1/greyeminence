import SwiftUI
import SwiftData

struct AddContactSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var existingContacts: [Contact]
    @State private var name = ""
    @State private var nickname = ""
    @State private var email = ""
    @State private var pendingDuplicate: PendingDuplicate?
    @FocusState private var focusedField: Field?

    private enum Field { case name, nickname, email }
    private enum PendingAction { case addAndDismiss, addAndCreateAnother }

    private struct PendingDuplicate: Identifiable {
        let match: Contact
        let action: PendingAction
        var id: PersistentIdentifier { match.persistentModelID }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            Text("Add Contact")
                .font(.headline)
                .padding()

            Form {
                TextField("Name", text: $name)
                    .focused($focusedField, equals: .name)
                TextField("Nickname (optional)", text: $nickname)
                    .focused($focusedField, equals: .nickname)
                TextField("Email (optional)", text: $email)
                    .focused($focusedField, equals: .email)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 160)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add & Create Another") {
                    attemptSave(.addAndCreateAnother)
                }
                .disabled(trimmedName.isEmpty)

                Button("Add") {
                    attemptSave(.addAndDismiss)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
            .padding()
        }
        .frame(width: 360)
        .onAppear { focusedField = .name }
        .alert(
            "Contact already exists",
            isPresented: Binding(
                get: { pendingDuplicate != nil },
                set: { if !$0 { pendingDuplicate = nil } }
            ),
            presenting: pendingDuplicate
        ) { pending in
            Button("Cancel", role: .cancel) {
                pendingDuplicate = nil
            }
            Button("Add anyway") {
                let action = pending.action
                pendingDuplicate = nil
                performSave(action)
            }
        } message: { pending in
            Text(duplicateAlertMessage(for: pending.match))
        }
    }

    private func attemptSave(_ action: PendingAction) {
        if let match = findDuplicate() {
            pendingDuplicate = PendingDuplicate(match: match, action: action)
            return
        }
        performSave(action)
    }

    private func performSave(_ action: PendingAction) {
        saveContact()
        switch action {
        case .addAndDismiss: dismiss()
        case .addAndCreateAnother: resetForm()
        }
    }

    /// Email is the strongest signal; name-only still warns because the
    /// "did I already add Sarah?" case typically has no email yet.
    private func findDuplicate() -> Contact? {
        let nameKey = trimmedName.lowercased()
        let emailKey = trimmedEmail.lowercased()
        return existingContacts.first { contact in
            if !emailKey.isEmpty, let existing = contact.email?.lowercased(), existing == emailKey {
                return true
            }
            return contact.name.lowercased() == nameKey
        }
    }

    private func duplicateAlertMessage(for match: Contact) -> String {
        var detail = "\"\(match.name)\""
        if let email = match.email, !email.isEmpty {
            detail += " (\(email))"
        }
        return "\(detail) is already in your contacts. Add another anyway?"
    }

    private func saveContact() {
        let contact = Contact(
            name: trimmedName,
            email: trimmedEmail.isEmpty ? nil : trimmedEmail
        )
        let nick = nickname.trimmingCharacters(in: .whitespaces)
        if !nick.isEmpty, nick != contact.firstName {
            contact.nickname = nick
        }
        modelContext.insert(contact)
    }

    private func resetForm() {
        name = ""
        nickname = ""
        email = ""
        focusedField = .name
    }
}
