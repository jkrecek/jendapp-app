import SwiftUI

/// One of a module's declared views: rows from the module's own command, drawn by
/// column roles, with the module's operations as buttons. Claude is just one kind
/// of operation here; free chat stays in the toolbar as the fallback.
struct DataView: View {
    let module: ModuleInfo
    let spec: ViewSpec
    @Environment(AppModel.self) private var app
    @State private var month = Month.current
    @State private var data: ViewData?
    @State private var error: String?
    @State private var shown: Set<String>
    @State private var running: String? // operation id
    @State private var sheet: Sheet?
    @State private var afterSheet: (() -> Void)?
    @State private var confirming: Pending?
    @State private var outcome: Outcome?
    @State private var claudeJob: Job?

    init(module: ModuleInfo, spec: ViewSpec) {
        self.module = module
        self.spec = spec
        _shown = State(initialValue: Set(spec.filter?.default ?? []))
    }

    private var params: [String: String] { spec.params.contains("month") ? ["month": month] : [:] }
    private var moduleOps: [OperationSpec] { (spec.actions ?? []).compactMap(module.operation) }

    var body: some View {
        List {
            header
            ForEach(groups, id: \.key) { group in
                Section {
                    ForEach(group.rows, id: \.rowID) { row in
                        Button { sheet = .row(row) } label: { RowCell(spec: spec, row: row) }
                            .buttonStyle(.plain)
                            .contentShape(.rect)
                            .swipeActions { quickActions(row) }
                            .contextMenu { rowMenu(row) }
                    }
                } header: {
                    groupHeader(group)
                }
            }
            emptyState
        }
        .overlay { overlay }
        .navigationTitle(spec.title)
        .toolbar { toolbar }
        .task(id: month) { await load() }
        .refreshable { await load() }
        .sheet(item: $sheet, onDismiss: { afterSheet?(); afterSheet = nil }) { sheetContent($0) }
        .confirmationDialog(confirming?.op.title ?? "", isPresented: present($confirming), titleVisibility: .visible, presenting: confirming) { p in
            Button(p.op.title, role: p.op.destructive == true ? .destructive : nil) { perform(p) }
        } message: { p in
            Text(p.op.confirm ?? "")
        }
        .alert(outcome?.title ?? "", isPresented: present($outcome), presenting: outcome) { _ in
            Button("OK") {}
        } message: { o in
            Text(o.message)
        }
        .navigationDestination(item: $claudeJob) { job in
            ChatView(module: module, job: job)
        }
    }

    // MARK: Header: stats, notes, module operations

    @ViewBuilder private var header: some View {
        if data != nil || !moduleOps.isEmpty {
            Section {
                if let data, let stats = spec.stats, !stats.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), alignment: .topLeading)], alignment: .leading, spacing: 12) {
                        ForEach(stats, id: \.key) { s in
                            // Top-aligned: a label that wraps to two lines must not push its number down.
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ValueFormat.stat(data.summary?[s.key] ?? .null, type: s.type)).lineLimit(1).minimumScaleFactor(0.7)
                                    .font(.title3.weight(.semibold)).monospacedDigit()
                                Text(s.title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                    .padding(.vertical, 4)
                }
                if let data, data.stale {
                    Label("Showing data from \(data.fetchedAt.formatted(.relative(presentation: .named))). Refresh failed: \(data.error ?? "")",
                          systemImage: "exclamationmark.icloud")
                        .font(.caption).foregroundStyle(.orange)
                }
                ForEach(data?.notes ?? [], id: \.self) { note in
                    Label(note, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
                if !moduleOps.isEmpty {
                    // The view's first action is its main one: full width. The rest share an even grid.
                    VStack(spacing: 8) {
                        if let main = moduleOps.first {
                            opButton(main, main: true)
                        }
                        let rest = Array(moduleOps.dropFirst())
                        if !rest.isEmpty {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                                ForEach(rest) { op in opButton(op, main: false) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .disabled(running != nil)
                }
            }
        }
    }

    /// Equal-width buttons with the icon and a title that may wrap; Claude operations are tinted purple.
    @ViewBuilder private func opButton(_ op: OperationSpec, main: Bool) -> some View {
        let label = HStack(spacing: 6) {
            if running == op.id {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: op.icon ?? (op.kind == "claude" ? "sparkles" : "bolt"))
            }
            Text(op.title)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
        }
        .font(main ? .body.weight(.semibold) : .subheadline)
        .frame(maxWidth: .infinity, minHeight: main ? 28 : 36)

        if main {
            Button { trigger(op, row: nil) } label: { label }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(op.kind == "claude" ? .purple : nil)
        } else {
            Button { trigger(op, row: nil) } label: { label }
                .buttonStyle(.bordered)
                .tint(op.kind == "claude" ? .purple : nil)
        }
    }

    // MARK: Rows

    private var visibleRows: [Row] {
        guard let rows = data?.rows else { return [] }
        guard let f = spec.filter else { return rows }
        return rows.filter { shown.contains($0.value(f.key).text) }
    }

    private var groups: [(key: String, rows: [Row])] {
        guard let key = spec.groupBy else { return visibleRows.isEmpty ? [] : [("", visibleRows)] }
        var order: [String] = []
        var byKey: [String: [Row]] = [:]
        for row in visibleRows {
            let k = row.value(key).text
            if byKey[k] == nil { order.append(k) }
            byKey[k, default: []].append(row)
        }
        return order.map { ($0, byKey[$0]!) }
    }

    @ViewBuilder private func groupHeader(_ group: (key: String, rows: [Row])) -> some View {
        if let key = spec.groupBy, let column = spec.column(key) {
            HStack {
                Text(ValueFormat.text(.string(group.key), column))
                Spacer()
                if let total = spec.columns("trailing").first(where: { $0.type == "hours" }) {
                    Text(ValueFormat.hours(group.rows.compactMap { $0.value(total.key).number }.reduce(0, +))).monospacedDigit()
                }
            }
        }
    }

    private func rowOps(_ row: Row) -> [OperationSpec] {
        (spec.rowActions ?? []).compactMap(module.operation).filter { $0.applies(to: row) }
    }

    /// Swipe: only operations that need no input or confirmation.
    @ViewBuilder private func quickActions(_ row: Row) -> some View {
        ForEach(rowOps(row).filter { ($0.inputs ?? []).isEmpty && $0.confirm == nil }) { op in
            Button { trigger(op, row: row) } label: { Label(op.title, systemImage: op.icon ?? "bolt") }
                .tint(op.destructive == true ? .red : .gray)
        }
    }

    @ViewBuilder private func rowMenu(_ row: Row) -> some View {
        ForEach(rowOps(row)) { op in
            Button { trigger(op, row: row) } label: { Label(op.title, systemImage: op.icon ?? "bolt") }
        }
    }

    /// Covers the whole list only while there is nothing else to show (no header yet).
    @ViewBuilder private var overlay: some View {
        if let error, data == nil {
            ContentUnavailableView("Can't load \(spec.title)", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if data == nil {
            ProgressView()
        }
    }

    /// Below the header (stats, notes, operations stay usable), not over it.
    @ViewBuilder private var emptyState: some View {
        if let data, visibleRows.isEmpty {
            Section {
                ContentUnavailableView(data.rows.isEmpty ? "Nothing here" : "Nothing to show",
                                       systemImage: "tray",
                                       description: data.rows.isEmpty ? nil : Text("\(data.rows.count) rows are hidden by the filter."))
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if spec.params.contains("month") {
            ToolbarItem {
                Menu {
                    Picker("Month", selection: $month) {
                        ForEach(Month.recent, id: \.self) { Text(Month.label($0)).tag($0) }
                    }
                } label: {
                    Label(Month.label(month), systemImage: "calendar")
                }
            }
        }
        if let f = spec.filter, let column = spec.column(f.key), let options = column.options {
            ToolbarItem {
                Menu {
                    ForEach(options, id: \.value) { o in
                        Toggle(o.title, isOn: Binding(
                            get: { shown.contains(o.value) },
                            set: { if $0 { shown.insert(o.value) } else { shown.remove(o.value) } }
                        ))
                    }
                    Divider()
                    Button("Show all") { shown = Set(options.map(\.value)) }
                    Button("Default") { shown = Set(f.default) }
                } label: {
                    Label("Filter", systemImage: Set(f.default) == shown ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        ToolbarItem {
            NavigationLink(value: Route.chat(module, sessionID: nil)) {
                Label("Ask Claude", systemImage: "bubble.left")
            }
        }
    }

    // MARK: Sheets

    enum Sheet: Identifiable {
        case row(Row)
        case inputs(Pending)

        var id: String {
            switch self {
            case .row(let r): "row:" + r.rowID
            case .inputs(let p): "inputs:" + p.id
            }
        }
    }

    @ViewBuilder private func sheetContent(_ s: Sheet) -> some View {
        switch s {
        case .row(let row):
            RowDetail(spec: spec, row: row, operations: rowOps(row)) { op in
                afterSheet = { trigger(op, row: row) }
                sheet = nil
            }
        case .inputs(let pending):
            InputForm(pending: pending) { filled in
                afterSheet = { confirmOrPerform(filled) }
                sheet = nil
            }
        }
    }

    // MARK: Running operations

    struct Pending: Identifiable {
        let op: OperationSpec
        let row: Row?
        var inputs: [String: String]
        var id: String { op.id + ":" + (row?.rowID ?? "") }
    }

    struct Outcome {
        let title: String
        let message: String
    }

    private func trigger(_ op: OperationSpec, row: Row?) {
        var p = Pending(op: op, row: row, inputs: [:])
        if let inputs = op.inputs, !inputs.isEmpty {
            for i in inputs { p.inputs[i.key] = row.map { ValueFormat.fill(i.default ?? "", row: $0) } ?? (i.default ?? "") }
            sheet = .inputs(p)
        } else {
            confirmOrPerform(p)
        }
    }

    private func confirmOrPerform(_ p: Pending) {
        if p.op.confirm != nil { confirming = p } else { perform(p) }
    }

    private func perform(_ p: Pending) {
        guard let client = app.client, running == nil else { return }
        running = p.op.id
        Task {
            defer { running = nil }
            do {
                let body = OperationRequest(view: spec.id, params: params, rowID: p.row?.rowID, inputs: p.inputs)
                let job = try await client.run(module: module.id, operation: p.op.id, body)
                if p.op.kind == "claude" {
                    claudeJob = job // its chat refreshes nothing here; .task reloads when we come back
                    return
                }
                if job.status == "failed" {
                    outcome = Outcome(title: "\(p.op.title) failed", message: Self.tail([job.error, job.result].compactMap { $0 }.joined(separator: "\n\n")))
                } else if p.row == nil {
                    outcome = Outcome(title: p.op.title, message: Self.tail(job.result ?? "Done"))
                }
            } catch {
                outcome = Outcome(title: "\(p.op.title) failed", message: error.localizedDescription)
            }
            await load()
        }
    }

    /// Commands put their summary last.
    private static func tail(_ s: String) -> String {
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.count > 12 ? "…\n" + lines.suffix(12).joined(separator: "\n") : s
    }

    private func load() async {
        guard let client = app.client else { return }
        do {
            data = try await client.viewData(module: module.id, view: spec.id, params: params)
            error = nil
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch {
            self.error = error.localizedDescription
            data = nil
        }
    }

    private func present<T>(_ item: Binding<T?>) -> Binding<Bool> {
        Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
    }
}

// MARK: - Building blocks

struct RowCell: View {
    let spec: ViewSpec
    let row: Row

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                title
                if let line = joined("subtitle") {
                    Text(line).font(.subheadline).foregroundStyle(.secondary)
                }
                if let line = joined("caption") {
                    Text(line).font(.caption).foregroundStyle(.secondary)
                }
                if let line = joined("warning") {
                    Label(line, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                if let line = joined("trailing") {
                    Text(line).monospacedDigit()
                }
                ForEach(spec.columns("badge"), id: \.key) { c in
                    let value = row.value(c.key).text
                    if !value.isEmpty { Badge(text: ValueFormat.text(.string(value), c), color: c.option(value)?.color) }
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var title: some View {
        if let c = spec.columns("title").first {
            let text = ValueFormat.text(row.value(c.key), c)
            if !text.isEmpty {
                Text(text).lineLimit(3)
            } else if let fb = c.fallback, !row.value(fb).text.isEmpty {
                Text(row.value(fb).text).italic().foregroundStyle(.secondary).lineLimit(2)
            } else {
                Text("No \((c.title ?? c.key).lowercased())").italic().foregroundStyle(.tertiary)
            }
        }
    }

    private func joined(_ role: String) -> String? {
        let parts = spec.columns(role).map { ValueFormat.text(row.value($0.key), $0) }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct Badge: View {
    let text: String
    let color: String?

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tint.opacity(0.15), in: .capsule)
            .foregroundStyle(tint)
    }

    private var tint: Color {
        switch color {
        case "green": .green
        case "orange": .orange
        case "red": .red
        case "blue": .blue
        case "purple": .purple
        case "yellow": .yellow
        default: .secondary
        }
    }
}

private struct RowDetail: View {
    let spec: ViewSpec
    let row: Row
    let operations: [OperationSpec]
    let run: (OperationSpec) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(spec.columns, id: \.key) { c in
                        let text = ValueFormat.text(row.value(c.key), c)
                        if !text.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.title ?? c.key).font(.caption).foregroundStyle(.secondary)
                                Text(text).textSelection(.enabled)
                            }
                        }
                    }
                }
                if !operations.isEmpty {
                    Section {
                        ForEach(operations) { op in
                            Button(role: op.destructive == true ? .destructive : nil) { run(op) } label: {
                                Label(op.title, systemImage: op.icon ?? "bolt")
                            }
                        }
                    }
                }
            }
            .navigationTitle(spec.columns("title").first.map { ValueFormat.text(row.value($0.key), $0) }.flatMap { $0.isEmpty ? nil : $0 } ?? "Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct InputForm: View {
    @State var pending: DataView.Pending
    let submit: (DataView.Pending) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                ForEach(pending.op.inputs ?? [], id: \.key) { input in
                    Section(input.title) {
                        TextField(input.title, text: Binding(
                            get: { pending.inputs[input.key] ?? "" },
                            set: { pending.inputs[input.key] = $0 }
                        ), axis: .vertical)
                        .lineLimit(input.type == "multiline" ? 4...12 : 1...6)
                    }
                }
            }
            .navigationTitle(pending.op.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { submit(pending) }
                        .disabled((pending.op.inputs ?? []).contains { (pending.inputs[$0.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// The `month` param: "YYYY-MM".
enum Month {
    static var current: String { id(.now) }

    /// This month and the five before it.
    static var recent: [String] {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: .now))!
        return (0..<6).map { id(cal.date(byAdding: .month, value: -$0, to: start)!) }
    }

    static func id(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: d)
        return String(format: "%04d-%02d", c.year!, c.month!)
    }

    static func label(_ id: String) -> String {
        let parts = id.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, let d = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1])) else { return id }
        return d.formatted(.dateTime.month(.wide).year())
    }
}
