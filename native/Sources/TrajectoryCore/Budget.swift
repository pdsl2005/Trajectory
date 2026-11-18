import Foundation

public enum Allocation: String, CaseIterable, Codable {
  case needs = "Needs", wants = "Wants", savings = "Savings & Debt"
}

public struct Target: Codable, Identifiable, Equatable {
  public var id: String { name }
  public var name: String, amount: Double, allocation: Allocation
  public init(_ name: String, _ amount: Double, _ allocation: Allocation) {
    self.name = name
    self.amount = amount
    self.allocation = allocation
  }
}

public struct Scenario: Codable, Equatable {
  public var plan: Plan
  public var targets: [Target]
  public init(plan: Plan = Plan()) {
    self.plan = plan
    let needs = ["Housing", "Food", "Utilities", "Transport", "Medical", "Renters insurance"]
    targets = Plan.spending.map { name, key in Target(name, plan[keyPath: key], needs.contains(name) ? .needs : .wants) }
    targets.append(Target("Savings & Debt", 0, .savings))
  }
  public var forecastPlan: Plan {
    var result = plan
    for (name, key) in Plan.spending {
      if let target = targets.first(where: { $0.name == name }) { result[keyPath: key] = target.amount }
    }
    // Savings/debt is an allocation of the surplus the forecast already invests or uses to repay debt.
    return result
  }
}

public enum EntryKind: String, Codable, CaseIterable, Identifiable {
  case income, expense
  public var id: Self { self }
}

public struct ManualEntry: Codable, Identifiable, Equatable {
  public var id: String, day: String, name: String, category: String, kind: EntryKind, amount: Double
  public var matchedCharge: String?
  public init(id: String = UUID().uuidString, day: String, name: String, category: String, kind: EntryKind, amount: Double) {
    self.id = id
    self.day = day
    self.name = name
    self.category = category
    self.kind = kind
    self.amount = amount
  }
}

public struct RecurringRule: Codable, Identifiable, Equatable {
  public var id: String { entry.id }
  public var entry: ManualEntry
  public init(entry: ManualEntry) { self.entry = entry }
}

public struct Charge: Codable, Identifiable, Equatable {
  public var id: String, day: String, name: String, category: String
  public var amount: Double, pending: Bool, excluded: Bool
  public var pendingID: String?
  public init(id: String, day: String, name: String, category: String, amount: Double, pending: Bool, excluded: Bool, pendingID: String? = nil) {
    self.id = id
    self.day = day
    self.name = name
    self.category = category
    self.amount = amount
    self.pending = pending
    self.excluded = excluded
    self.pendingID = pendingID
  }
}

public struct CardLedger: Codable, Equatable {
  public var cursor: String?
  public var lastSync: Date?
  public var charges: [String: Charge] = [:]
  public init() {}
}

public struct BudgetSummary {
  public var income = 0.0, pending = 0.0
  public var spending: [String: Double] = [:]
  public var spent: Double { spending.values.reduce(0, +) }
  public var net: Double { income - spent }
}

public enum BudgetDate {
  public static func day(_ date: Date) -> String {
    let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 1, parts.month ?? 1, parts.day ?? 1)
  }
}

public enum ImportError: LocalizedError {
  case invalidBackup
  public var errorDescription: String? { "This file does not contain a supported Trajectory backup." }
}

public struct Profile: Codable, Equatable {
  public private(set) var version = 1
  public var active = "Baseline"
  public var baseline = "Baseline"
  public var scenarios = ["Baseline": Scenario()]
  public var manual: [ManualEntry] = []
  public var recurring: [RecurringRule] = []
  public var skippedOccurrences: Set<String> = []
  public var cards: [String: CardLedger] = [:]
  public var categoryOverrides: [String: String] = [:]
  public init() {}

  public mutating func importBackup(_ data: Data) throws {
    let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    if raw?["version"] != nil {
      let imported = try JSONDecoder().decode(Profile.self, from: data)
      guard imported.version == 1, imported.scenarios[imported.active] != nil,
            imported.scenarios[imported.baseline] != nil,
            imported.scenarios.values.allSatisfy({ scenario in
              (18...100).contains(scenario.plan.startAge) && (1900...2200).contains(scenario.plan.startYear)
                && Set(scenario.targets.map(\.id)).count == scenario.targets.count
                && (scenario.plan.retirement?.expenses.allSatisfy { expense in
                  (18...120).contains(expense.startAge) && (expense.startAge...120).contains(expense.endAge)
                } ?? true)
                && (scenario.plan.retirement.map { settings in
                  [settings.retireAge, settings.throughAge, settings.incomeAge].compactMap { $0 }
                    .allSatisfy { (18...120).contains($0) }
                } ?? true)
            }) else { throw ImportError.invalidBackup }
      self = imported
      return
    }
    guard let active = raw?["active"] as? String, let plans = raw?["plans"] as? [String: Any],
          plans[active] != nil else { throw ImportError.invalidBackup }
    let imported = try plans.mapValues { value -> Scenario in
      guard let plan = value as? [String: Any] else { throw ImportError.invalidBackup }
      return Scenario(plan: Plan(web: plan))
    }
    guard imported.keys.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
      throw ImportError.invalidBackup
    }
    self.active = active
    baseline = active
    scenarios = imported
  }

  public func backup() throws -> Data { try JSONEncoder().encode(self) }

  public mutating func generate(through day: String) {
    let calendar = Calendar(identifier: .gregorian)
    var existing = Set(manual.map(\.id)).union(skippedOccurrences)
    for rule in recurring where rule.entry.day <= day {
      let parts = rule.entry.day.split(separator: "-").compactMap { Int($0) }
      guard parts.count == 3, let first = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: 1)) else { continue }
      var month = first
      while let range = calendar.range(of: .day, in: .month, for: month),
            (1...31).contains(parts[2]),
            let occurrence = calendar.date(byAdding: .day, value: min(parts[2], range.count) - 1, to: month) {
        let date = BudgetDate.day(occurrence)
        if date > day { break }
        let id = "\(rule.id)/\(date.prefix(7))"
        if existing.insert(id).inserted {
          var entry = rule.entry
          entry.id = id
          entry.day = date
          manual.append(entry)
        }
        guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
        month = next
      }
    }
  }

  public func chargeKey(connection: String, id: String) -> String { "\(connection)/\(id)" }

  public mutating func apply(connection: String, from cursor: String?, to next: String, changes: [Charge], removed: [String], now: Date = Date()) {
    var card = cards[connection] ?? CardLedger()
    guard card.cursor == cursor else { return }
    for id in removed { card.charges.removeValue(forKey: id) }
    for change in changes {
      let key = chargeKey(connection: connection, id: change.id)
      if let pendingID = change.pendingID {
        let pendingKey = chargeKey(connection: connection, id: pendingID)
        if categoryOverrides[key] == nil { categoryOverrides[key] = categoryOverrides[pendingKey] }
        for index in manual.indices where manual[index].matchedCharge == pendingKey { manual[index].matchedCharge = key }
        card.charges.removeValue(forKey: pendingID)
      }
      card.charges[change.id] = change
    }
    card.cursor = next
    card.lastSync = now
    cards[connection] = card
  }

  public func summary(month: String) -> BudgetSummary {
    var result = BudgetSummary()
    var posted = Set<String>()
    for (connection, card) in cards {
      for charge in card.charges.values where !charge.excluded {
        let key = chargeKey(connection: connection, id: charge.id)
        if !charge.pending { posted.insert(key) }
        guard charge.day.hasPrefix(month + "-") else { continue }
        if charge.pending { result.pending += charge.amount }
        else { result.spending[categoryOverrides[key] ?? charge.category, default: 0] += charge.amount }
      }
    }
    for entry in manual where entry.day.hasPrefix(month + "-") {
      if entry.kind == .income { result.income += entry.amount }
      else if !posted.contains(entry.matchedCharge ?? "") { result.spending[entry.category, default: 0] += entry.amount }
    }
    return result
  }
}
