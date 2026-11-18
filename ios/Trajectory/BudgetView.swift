import SwiftUI
import TrajectoryCore

struct BudgetView: View {
  @EnvironmentObject private var store: Store
  @EnvironmentObject private var imports: CardImports
  @State private var chosenMonth = Date()
  @State private var editor: ManualEntry?
  @State private var editingRule = false
  @State private var categoryEditor: ChargeRow?

  private var month: String { String(BudgetDate.day(chosenMonth).prefix(7)) }
  private var summary: BudgetSummary { store.profile.summary(month: month) }
  private var targets: [Target] { store.scenario.targets }
  private var planned: Double { targets.reduce(store.scenario.plan.goldFee / 12) { $0 + $1.amount } }
  private var remaining: Double {
    let reserved = targets.filter { $0.allocation == .savings }
    let reservedTargets = reserved.reduce(0.0) { $0 + $1.amount }
    let reservedActual = reserved.reduce(0.0) { $0 + summary.spending[$1.name, default: 0] }
    return planned - reservedTargets - (summary.spent - reservedActual)
  }
  private let calendar = Calendar(identifier: .gregorian)

  struct ChargeRow: Identifiable {
    let id: String
    let charge: Charge
  }

  private var charges: [ChargeRow] {
    store.profile.cards.flatMap { connection, card in
      card.charges.values.filter { $0.day.hasPrefix(month + "-") }.map {
        ChargeRow(id: store.profile.chargeKey(connection: connection, id: $0.id), charge: $0)
      }
    }.sorted { ($0.charge.day, $0.id) > ($1.charge.day, $1.id) }
  }

  var body: some View {
    Form {
      Section {
        HStack {
          Button { move(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous month")
          Spacer()
          Text(chosenMonth, format: .dateTime.month(.wide).year()).font(.headline)
          Spacer()
          Button { move(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next month")
        }.buttonStyle(.borderless)
        let net = Forecast.budget(store.scenario.forecastPlan).net
        Figure(label: "Planned take-home income", amount: net)
        Figure(label: "Planned allocations", amount: planned)
        Figure(label: "Planned cash flow", amount: net - planned)
        Figure(label: "Actual income", amount: summary.income)
        Figure(label: "Actual spending", amount: summary.spent)
        Figure(label: "Actual cash flow", amount: summary.net)
        Figure(label: "Remaining spending", amount: remaining)
          .foregroundStyle(remaining < 0 ? Color.negative : Color.primary)
        Figure(label: "Pending card charges", amount: summary.pending)
        allocationBar
      }
      Section("Monthly targets · \(store.profile.active)") {
        AmountField(title: "Annual gross income", value: store.scenarioField(\.plan.salary))
        ForEach(targets) { target in
          let actual = summary.spending[target.name, default: 0]
          DisclosureGroup {
            AmountField(title: "Monthly target", value: Binding(get: { target.amount }, set: { amount in
              store.edit { profile in
                guard let index = profile.scenarios[profile.active]?.targets.firstIndex(where: { $0.id == target.id }) else { return }
                profile.scenarios[profile.active]?.targets[index].amount = max(0, amount)
              }
            }))
            Figure(label: "Remaining", amount: target.amount - actual)
          } label: {
            VStack(alignment: .leading, spacing: 8) {
              Figure(label: target.name, amount: actual)
              let total = target.amount > 0 ? target.amount : 1
              ProgressView(value: min(max(0, actual), total), total: total)
                .tint(actual > target.amount ? .negative : .brand)
                .accessibilityLabel("\(target.name) target progress")
            }
          }
        }
      }
      Section("Manual entries") {
        Button("Add income or expense") { newEntry(recurring: false) }
        ForEach(store.profile.manual.filter { $0.day.hasPrefix(month + "-") }.sorted { $0.day > $1.day }) { entry in
          Button {
            editingRule = false
            editor = entry
          } label: {
            VStack(alignment: .leading) {
              Figure(label: entry.name, amount: entry.kind == .income ? entry.amount : -entry.amount)
              Text(entry.day + (entry.matchedCharge == nil ? "" : " · Matched")).font(.caption).foregroundStyle(.secondary)
            }
          }.swipeActions {
            Button("Delete", role: .destructive) {
              store.edit {
                $0.manual.removeAll { $0.id == entry.id }
                if entry.id.contains("/") { $0.skippedOccurrences.insert(entry.id) }
              }
            }
          }
        }
      }
      Section("Recurring entries") {
        Button("Add monthly entry") { newEntry(recurring: true) }
        ForEach(store.profile.recurring) { rule in
          Button {
            editingRule = true
            editor = rule.entry
          } label: { Figure(label: rule.entry.name, amount: rule.entry.amount) }
            .swipeActions {
              Button("Delete rule", role: .destructive) { store.edit { $0.recurring.removeAll { $0.id == rule.id } } }
            }
        }
      }
      Section("Card activity") {
        ForEach(charges) { row in
          Button { categoryEditor = row } label: {
            VStack(alignment: .leading) {
              Figure(label: row.charge.name, amount: row.charge.amount)
              Text(cardCaption(row)).font(.caption).foregroundStyle(.secondary)
            }
          }.disabled(row.charge.excluded)
        }
        if charges.isEmpty { Text("No imported activity this month.").foregroundStyle(.secondary) }
      }
    }
    .trajectorySurface()
    .refreshable { await imports.refresh(store) }
    .navigationTitle("Budget")
    .sheet(item: $editor) { entry in
      EntryEditor(entry: entry, recurring: editingRule, targets: targets, charges: allMatchable(for: entry)) { edited in
        store.edit { profile in
          if editingRule {
            profile.recurring.removeAll { $0.id == edited.id }
            profile.recurring.append(RecurringRule(entry: edited))
            profile.generate(through: BudgetDate.day(Date()))
          } else {
            profile.manual.removeAll { $0.id == edited.id }
            profile.manual.append(edited)
          }
        }
      }
    }
    .sheet(item: $categoryEditor) { row in
      NavigationStack {
        List {
          Button("Use imported category") {
            store.edit { $0.categoryOverrides.removeValue(forKey: row.id) }
            categoryEditor = nil
          }
          ForEach(targets) { target in
            Button(target.name) {
              store.edit { $0.categoryOverrides[row.id] = target.name }
              categoryEditor = nil
            }
          }
        }.navigationTitle("Charge category").toolbar { Button("Done") { categoryEditor = nil } }
      }
    }
  }

  private var allocationBar: some View {
    let items = Allocation.allCases.map { group in
      targets.filter { $0.allocation == group }.reduce(0.0) { $0 + max(0, $1.amount) }
    }
    let colors = [Color.brand, Color.brand.opacity(0.62), Color.positive]
    let total = items.reduce(0, +)
    return VStack(alignment: .leading, spacing: 8) {
      GeometryReader { geometry in
        HStack(spacing: 0) {
          ForEach(items.indices, id: \.self) { index in
            colors[index].frame(width: total > 0 ? geometry.size.width * (items[index] / total) : 0)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("BorderHairline"))
        .clipShape(Capsule())
      }
      .frame(height: 10)
      .accessibilityHidden(true)
      DisclosureGroup("Needs / Wants / Savings & Debt") {
        ForEach(items.indices, id: \.self) { index in
          Figure(label: Allocation.allCases[index].rawValue, amount: items[index])
        }
      }
    }
  }

  private func allMatchable(for entry: ManualEntry) -> [ChargeRow] {
    let used = Set(store.profile.manual.filter { $0.id != entry.id }.compactMap(\.matchedCharge))
    return store.profile.cards.flatMap { connection, card in
      card.charges.values.filter { !$0.excluded && $0.amount > 0 }.map {
        ChargeRow(id: store.profile.chargeKey(connection: connection, id: $0.id), charge: $0)
      }
    }.filter { !used.contains($0.id) }.sorted { ($0.charge.day, $0.id) > ($1.charge.day, $1.id) }
  }

  private func cardCaption(_ row: ChargeRow) -> String {
    let status = row.charge.excluded ? " · Excluded" : (row.charge.pending ? " · Pending" : "")
    return "\(row.charge.day) · \(store.profile.categoryOverrides[row.id] ?? row.charge.category)\(status)"
  }

  private func move(_ amount: Int) {
    chosenMonth = calendar.date(byAdding: .month, value: amount, to: chosenMonth) ?? chosenMonth
  }

  private func newEntry(recurring: Bool) {
    editingRule = recurring
    let day = month == String(BudgetDate.day(Date()).prefix(7)) ? BudgetDate.day(Date()) : month + "-01"
    editor = ManualEntry(day: day, name: "", category: "Miscellaneous", kind: .expense, amount: 0)
  }
}

private struct EntryEditor: View {
  @Environment(\.dismiss) private var dismiss
  @State var entry: ManualEntry
  let recurring: Bool
  let targets: [Target]
  let charges: [BudgetView.ChargeRow]
  let save: (ManualEntry) -> Void

  private var date: Binding<Date> {
    Binding(get: {
      let parts = entry.day.split(separator: "-").compactMap { Int($0) }
      guard parts.count == 3 else { return Date() }
      return Calendar(identifier: .gregorian).date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) ?? Date()
    }, set: { entry.day = BudgetDate.day($0) })
  }

  var body: some View {
    NavigationStack {
      Form {
        TextField("Description", text: $entry.name)
        DatePicker(recurring ? "First occurrence" : "Date", selection: date, displayedComponents: .date)
        Picker("Type", selection: $entry.kind) {
          Text("Expense").tag(EntryKind.expense)
          Text("Income").tag(EntryKind.income)
        }
        AmountField(title: "Amount", value: $entry.amount)
        if entry.kind == .expense {
          Picker("Category", selection: $entry.category) {
            ForEach(targets) { Text($0.name).tag($0.name) }
          }
          if !recurring {
            Picker("Match to card charge", selection: $entry.matchedCharge) {
              Text("None").tag(nil as String?)
              ForEach(charges) { row in
                Text("\(row.charge.day) · \(row.charge.name) · \(row.charge.amount.formatted(dollars))").tag(Optional(row.id))
              }
            }
          }
        }
      }
      .trajectorySurface()
      .navigationTitle(recurring ? "Monthly entry" : "Manual entry")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            if entry.kind == .income || recurring { entry.matchedCharge = nil }
            save(entry)
            dismiss()
          }.disabled(entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || entry.amount <= 0)
        }
      }
    }
  }
}
