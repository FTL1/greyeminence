import SwiftUI
import SwiftData

enum OrganizationTab: String, CaseIterable {
    case departments = "Departments & Teams"
    case roleLevels = "Role Levels"
    case roles = "Roles"
}

struct OrganizationSettingsView: View {
    @State private var selectedTab: OrganizationTab = .departments

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(OrganizationTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            switch selectedTab {
            case .departments:
                DepartmentsTeamsTab()
            case .roleLevels:
                RoleLevelsTab()
            case .roles:
                RolesTab()
            }
        }
    }
}

// MARK: - Departments & Teams

private struct DepartmentsTeamsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Department.sortOrder) private var departments: [Department]
    @State private var newDepartmentName = ""
    @State private var newTeamNames: [UUID: String] = [:]

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("New department name...", text: $newDepartmentName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addDepartment() }
                    Button("Add") { addDepartment() }
                        .disabled(newDepartmentName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Label("Add Department", systemImage: "building.2")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }

            ForEach(departments) { dept in
                Section {
                    // Department name (editable)
                    HStack {
                        Image(systemName: "building.2")
                            .foregroundStyle(.cyan)
                        TextField("Department", text: Binding(
                            get: { dept.name },
                            set: { dept.name = $0 }
                        ))
                        .font(.headline)
                    }

                    // Teams within department
                    ForEach(dept.sortedTeams) { team in
                        HStack {
                            Image(systemName: "person.3")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            TextField("Team name", text: Binding(
                                get: { team.name },
                                set: { team.name = $0 }
                            ))
                            Spacer()
                            Button {
                                dept.teams.removeAll { $0.id == team.id }
                                modelContext.delete(team)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.leading, 8)
                    }

                    // Add team
                    HStack {
                        TextField("New team name...", text: Binding(
                            get: { newTeamNames[dept.id] ?? "" },
                            set: { newTeamNames[dept.id] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addTeam(to: dept) }
                        Button("Add Team") { addTeam(to: dept) }
                            .controlSize(.small)
                            .disabled((newTeamNames[dept.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.leading, 8)
                } header: {
                    HStack {
                        Text(dept.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .textCase(nil)
                        Spacer()
                        Button(role: .destructive) {
                            modelContext.delete(dept)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func addDepartment() {
        let name = newDepartmentName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let dept = Department(name: name, sortOrder: departments.count)
        modelContext.insert(dept)
        newDepartmentName = ""
    }

    private func addTeam(to dept: Department) {
        let name = (newTeamNames[dept.id] ?? "").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let team = Team(name: name, sortOrder: dept.teams.count)
        team.department = dept
        dept.teams.append(team)
        newTeamNames[dept.id] = ""
    }
}

// MARK: - Role Levels

private struct RoleLevelsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RoleLevel.sortOrder) private var levels: [RoleLevel]
    @State private var newLevelName = ""
    @State private var newLevelCategory: RoleLevelCategory = .ic

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("New role level name...", text: $newLevelName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addLevel() }
                    Picker("", selection: $newLevelCategory) {
                        ForEach(RoleLevelCategory.allCases, id: \.self) { cat in
                            Text(cat.rawValue).tag(cat)
                        }
                    }
                    .frame(width: 180)
                    Button("Add") { addLevel() }
                        .disabled(newLevelName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Label("Add Role Level", systemImage: "person.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }

            ForEach(RoleLevelCategory.allCases, id: \.self) { category in
                let categoryLevels = levels.filter { $0.category == category }
                if !categoryLevels.isEmpty {
                    Section {
                        ForEach(categoryLevels) { level in
                            HStack {
                                TextField("Level name", text: Binding(
                                    get: { level.name },
                                    set: { level.name = $0 }
                                ))
                                Spacer()
                                Button {
                                    modelContext.delete(level)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        Text(category.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .textCase(nil)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func addLevel() {
        let name = newLevelName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let level = RoleLevel(name: name, category: newLevelCategory, sortOrder: levels.count)
        modelContext.insert(level)
        newLevelName = ""
    }
}

// MARK: - Roles

private struct RolesTab: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \InterviewRole.createdAt) private var roles: [InterviewRole]
    @Query(sort: \Department.sortOrder) private var departments: [Department]
    @Query(sort: \RoleLevel.sortOrder) private var levels: [RoleLevel]

    // Add Role form
    @State private var selectedDepartment: Department?
    @State private var selectedTeam: Team?
    @State private var selectedLevel: RoleLevel?
    @State private var customTitle = ""

    // Browser. `expandedDepartments` keys on `Department.id`, with `nil`
    // standing in for the "All Departments" group (roles not scoped to
    // any specific department).
    @State private var roleSearch = ""
    @State private var expandedDepartments: Set<UUID?> = []
    @State private var selectedRoleID: UUID?

    private var availableTeams: [Team] {
        selectedDepartment?.sortedTeams ?? []
    }

    var body: some View {
        Form {
            addRoleSection
            roleBrowserSection
        }
        .formStyle(.grouped)
        .onChange(of: selectedDepartment) { _, _ in selectedTeam = nil }
    }

    // MARK: Add Role

    private var addRoleSection: some View {
        Section {
            HStack(spacing: 8) {
                Picker("Department", selection: $selectedDepartment) {
                    Text("All").tag(nil as Department?)
                    ForEach(departments) { dept in
                        Text(dept.name).tag(dept as Department?)
                    }
                }
                .frame(maxWidth: 180)

                if !availableTeams.isEmpty {
                    Picker("Team", selection: $selectedTeam) {
                        Text("All Teams").tag(nil as Team?)
                        ForEach(availableTeams) { team in
                            Text(team.name).tag(team as Team?)
                        }
                    }
                    .frame(maxWidth: 160)
                }

                Picker("Level", selection: $selectedLevel) {
                    Text("Select...").tag(nil as RoleLevel?)
                    ForEach(levels) { level in
                        Text(level.name).tag(level as RoleLevel?)
                    }
                }
                .frame(maxWidth: 200)
            }

            HStack {
                TextField("Custom title (optional)", text: $customTitle)
                    .textFieldStyle(.roundedBorder)
                Button("Add Role") { addRole() }
                    .disabled(selectedLevel == nil)
            }
        } header: {
            Label("Add Role", systemImage: "person.badge.shield.checkmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .textCase(nil)
        }
    }

    private func addRole() {
        guard let level = selectedLevel else { return }
        let title = customTitle.trimmingCharacters(in: .whitespaces)
        let role = InterviewRole(
            level: level,
            department: selectedDepartment,
            team: selectedTeam,
            customTitle: title.isEmpty ? nil : title
        )
        modelContext.insert(role)
        customTitle = ""
        selectedLevel = nil
        // Surface the freshly-added role: expand its department and select it.
        expandedDepartments.insert(role.department?.id)
        selectedRoleID = role.id
    }

    // MARK: Browser

    private var isSearching: Bool {
        !roleSearch.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @ViewBuilder
    private var roleBrowserSection: some View {
        Section {
            if roles.isEmpty {
                Text("No roles yet — add one above.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Filter roles, teams, departments…", text: $roleSearch)
                        .textFieldStyle(.plain)
                    if isSearching {
                        Button { roleSearch = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 12) {
                    Button("Expand all") { expandedDepartments = Set(deptGroups.map(\.id)) }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    Button("Collapse all") { expandedDepartments = [] }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    Spacer()
                }
                .font(.caption)
                .disabled(isSearching)

                let groups = deptGroups
                if groups.isEmpty {
                    Text("No roles match “\(roleSearch)”.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(groups) { group in
                        departmentDisclosure(group)
                    }
                }
            }
        } header: {
            Label("Roles (\(roles.count))", systemImage: "list.bullet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .textCase(nil)
        }
    }

    @ViewBuilder
    private func departmentDisclosure(_ group: DeptGroup) -> some View {
        DisclosureGroup(isExpanded: disclosureBinding(for: group.id)) {
            ForEach(group.teamGroups) { tg in
                teamSubsection(tg)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: group.department == nil ? "questionmark.folder" : "building.2")
                    .foregroundStyle(group.department == nil ? Color.secondary : Color.cyan)
                Text(group.department?.name ?? "All Departments")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(group.roleCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.secondary.opacity(0.15), in: Capsule())
            }
        }
    }

    private func disclosureBinding(for key: UUID?) -> Binding<Bool> {
        Binding(
            get: { isSearching || expandedDepartments.contains(key) },
            set: { open in
                guard !isSearching else { return }
                if open { expandedDepartments.insert(key) } else { expandedDepartments.remove(key) }
            }
        )
    }

    @ViewBuilder
    private func teamSubsection(_ tg: TeamGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(tg.team?.name ?? "All Teams")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Rectangle()
                    .fill(.secondary.opacity(0.2))
                    .frame(height: 1)
            }
            ForEach(tg.roles) { role in
                roleRow(role)
            }
        }
        .padding(.leading, 8)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func roleRow(_ role: InterviewRole) -> some View {
        let isOpen = selectedRoleID == role.id
        let category = role.level.flatMap { $0.isDeleted ? nil : $0.category }
        let meta = roleMetaText(role)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                selectedRoleID = isOpen ? nil : role.id
            } label: {
                HStack(spacing: 8) {
                    Text(role.displayTitle)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    if let category {
                        Circle().fill(category.tint).frame(width: 6, height: 6)
                    }
                    if !meta.isEmpty {
                        Text(meta)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                RoleDetailInline(
                    role: role,
                    departments: departments,
                    levels: levels,
                    onDelete: {
                        selectedRoleID = nil
                        modelContext.delete(role)
                    }
                )
                .padding(.top, 6)
                .padding(.bottom, 2)
            }
        }
        .padding(.vertical, 2)
    }

    /// Trailing meta for a role row: when a custom title is shown, surface
    /// the underlying level name so the abstraction isn't hidden; otherwise
    /// the row title *is* the level name, so show the category instead.
    private func roleMetaText(_ role: InterviewRole) -> String {
        if role.customTitle != nil, let level = role.level, !level.isDeleted {
            return level.name
        }
        return role.level?.category.abbrev ?? ""
    }

    // MARK: Grouping

    private struct TeamGroup: Identifiable {
        let team: Team?          // nil → "All Teams"
        let roles: [InterviewRole]
        var id: UUID? { team?.id }
    }

    private struct DeptGroup: Identifiable {
        let department: Department?   // nil → "All Departments"
        let teamGroups: [TeamGroup]
        var roleCount: Int { teamGroups.reduce(0) { $0 + $1.roles.count } }
        var id: UUID? { department?.id }
    }

    private var filteredRoles: [InterviewRole] {
        let q = roleSearch.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return roles }
        return roles.filter { role in
            role.displayTitle.lowercased().contains(q)
                || (role.level?.name.lowercased().contains(q) ?? false)
                || (role.team?.name.lowercased().contains(q) ?? false)
                || (role.department?.name.lowercased().contains(q) ?? false)
        }
    }

    private var deptGroups: [DeptGroup] {
        let byDept = Dictionary(grouping: filteredRoles) { $0.department?.id }
        var groups: [DeptGroup] = []
        var consumed = Set<UUID>()
        for dept in departments {
            guard let deptRoles = byDept[dept.id], !deptRoles.isEmpty else { continue }
            groups.append(DeptGroup(department: dept, teamGroups: teamGroups(for: deptRoles, in: dept)))
            consumed.insert(dept.id)
        }
        // Roles pointing at a department that's not in the query (stale data).
        for (key, deptRoles) in byDept {
            guard let key, !consumed.contains(key) else { continue }
            let dept = deptRoles.first?.department
            groups.append(DeptGroup(department: dept, teamGroups: teamGroups(for: deptRoles, in: dept)))
        }
        if let orphans = byDept[UUID?.none], !orphans.isEmpty {
            groups.append(DeptGroup(department: nil, teamGroups: teamGroups(for: orphans, in: nil)))
        }
        return groups
    }

    private func teamGroups(for roleSet: [InterviewRole], in dept: Department?) -> [TeamGroup] {
        let byTeam = Dictionary(grouping: roleSet) { $0.team?.id }
        var groups: [TeamGroup] = []
        var consumed = Set<UUID>()
        for team in dept?.sortedTeams ?? [] {
            guard let teamRoles = byTeam[team.id], !teamRoles.isEmpty else { continue }
            groups.append(TeamGroup(team: team, roles: sortRoles(teamRoles)))
            consumed.insert(team.id)
        }
        for (key, teamRoles) in byTeam {
            guard let key, !consumed.contains(key) else { continue }
            groups.append(TeamGroup(team: teamRoles.first?.team, roles: sortRoles(teamRoles)))
        }
        if let noTeam = byTeam[UUID?.none], !noTeam.isEmpty {
            groups.append(TeamGroup(team: nil, roles: sortRoles(noTeam)))
        }
        return groups
    }

    private func sortRoles(_ roleSet: [InterviewRole]) -> [InterviewRole] {
        roleSet.sorted { a, b in
            let la = a.level?.sortOrder ?? Int.max
            let lb = b.level?.sortOrder ?? Int.max
            if la != lb { return la < lb }
            return a.displayTitle.localizedCaseInsensitiveCompare(b.displayTitle) == .orderedAscending
        }
    }
}

// MARK: - Role detail (inline)

private struct RoleDetailInline: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var role: InterviewRole
    let departments: [Department]
    let levels: [RoleLevel]
    let onDelete: () -> Void

    private var availableTeams: [Team] {
        role.department?.sortedTeams ?? []
    }

    private var linkedRubrics: [(name: String, strictness: RubricStrictness)] {
        role.roleRubricLinks
            .compactMap { link in link.rubric.map { (name: $0.name, strictness: link.strictness) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var linkedTemplates: [String] {
        role.templateRoleLinks
            .compactMap { $0.template?.name }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            pickerRow("Department") {
                Picker("", selection: $role.department) {
                    Text("All").tag(nil as Department?)
                    ForEach(departments) { Text($0.name).tag($0 as Department?) }
                }
                .labelsHidden()
            }
            if !availableTeams.isEmpty {
                pickerRow("Team") {
                    Picker("", selection: $role.team) {
                        Text("All Teams").tag(nil as Team?)
                        ForEach(availableTeams) { Text($0.name).tag($0 as Team?) }
                    }
                    .labelsHidden()
                }
            }
            pickerRow("Level") {
                Picker("", selection: $role.level) {
                    Text("None").tag(nil as RoleLevel?)
                    ForEach(levels) { Text($0.name).tag($0 as RoleLevel?) }
                }
                .labelsHidden()
            }
            pickerRow("Title") {
                TextField("Custom title (optional)", text: Binding(
                    get: { role.customTitle ?? "" },
                    set: { role.customTitle = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }

            Divider()

            linkList("Rubrics", count: linkedRubrics.count) {
                ForEach(linkedRubrics, id: \.name) { entry in
                    HStack(spacing: 6) {
                        Text(entry.name).font(.caption)
                        Spacer()
                        Label(entry.strictness.label, systemImage: entry.strictness.symbolName)
                            .font(.caption2)
                            .foregroundStyle(entry.strictness.color)
                    }
                }
            }
            linkList("Templates", count: linkedTemplates.count) {
                ForEach(linkedTemplates, id: \.self) { name in
                    Text(name).font(.caption)
                }
            }

            HStack {
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Label("Delete role", systemImage: "trash")
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        .onChange(of: role.department?.id) { _, _ in
            if let team = role.team,
               role.department?.teams.contains(where: { $0.id == team.id }) != true {
                role.team = nil
            }
        }
    }

    @ViewBuilder
    private func pickerRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func linkList<Content: View>(_ title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(title) (\(count))")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            if count == 0 {
                Text("None")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                content()
            }
        }
    }
}

private extension RoleLevelCategory {
    var abbrev: String {
        switch self {
        case .ic: "IC"
        case .management: "Mgmt"
        case .executive: "Exec"
        }
    }

    var tint: Color {
        switch self {
        case .ic: .blue
        case .management: .purple
        case .executive: .orange
        }
    }
}
