import Foundation
import CoreFoundation

public struct MajorExpense: Codable, Equatable, Identifiable {
  public var id: String, name: String, cost: Double, startAge: Int, endAge: Int
  public init(id: String = UUID().uuidString, name: String, cost: Double, startAge: Int, endAge: Int) {
    self.id = id
    self.name = name
    self.cost = cost
    self.startAge = startAge
    self.endAge = endAge
  }
}

public struct RetirementSettings: Codable, Equatable {
  public var startingAssets, monthlySpend, monthlySave, beforeReturn, beforeVolatility,
             afterReturn, afterVolatility, inflation: Double?
  public var retireAge, throughAge, incomeAge: Int?
  public var monthlyIncome = 0.0
  public var expenses: [MajorExpense] = []

  public init() {}

  init(web: [String: Any]) {
    func bound(_ raw: Any?, _ low: Double, _ high: Double) -> Double? {
      guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
            number.doubleValue.isFinite else { return nil }
      return clamp(number.doubleValue, low, high)
    }
    func age(_ raw: Any?) -> Int? { bound(raw, 18, 120).map { Int(floor($0 + 0.5)) } }
    startingAssets = bound(web["startingAssets"], 0, 100_000_000)
    retireAge = age(web["retireAge"])
    throughAge = age(web["throughAge"])
    monthlySpend = bound(web["monthlySpend"], 0, 1_000_000)
    monthlySave = bound(web["monthlySave"], 0, 1_000_000)
    monthlyIncome = bound(web["monthlyIncome"], 0, 1_000_000) ?? 0
    incomeAge = age(web["incomeAge"])
    beforeReturn = bound(web["beforeReturn"], -30, 25)
    afterReturn = bound(web["afterReturn"], -30, 25)
    beforeVolatility = bound(web["beforeVolatility"], 0, 60)
    afterVolatility = bound(web["afterVolatility"], 0, 60)
    inflation = bound(web["inflation"], 0, 15)
    var ids = Set<String>()
    for case let raw as [String: Any] in (web["expenses"] as? [Any] ?? []).prefix(40) {
      guard let name = raw["name"] as? String, let cost = bound(raw["cost"], 0, 100_000_000),
            cost > 0, let start = age(raw["startAge"]) else { continue }
      let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
      guard !trimmed.isEmpty else { continue }
      var id = raw["id"] as? String ?? ""
      if id.range(of: "^[a-zA-Z0-9_-]{1,80}$", options: .regularExpression) == nil { id = "" }
      var suffix = expenses.count
      while id.isEmpty || ids.contains(id) {
        id = "expense-\(suffix)"
        suffix += 1
      }
      ids.insert(id)
      expenses.append(MajorExpense(id: id, name: trimmed, cost: cost, startAge: start,
                                   endAge: max(start, age(raw["endAge"]) ?? start)))
    }
  }
}

public struct RetirementYear: Identifiable {
  public let age, year: Int
  public let save, spend, income, expenseCost, shortfall: Double
  public let balance, noExpenses: [Double]
  public let goalNames: [String]
  public var id: Int { year }
}

public struct RetirementProjection {
  public let periods: [RetirementYear]
  public let expenseFunding: [Double?]
  public let hasRetirement: Bool
  public let coverage, baselineCoverage: Double
  public let retirementStart: [Double]
  public let runs: Int

  public var csv: String {
    let header = "Year,Age,Annual saving,Retirement income,Retirement spending,Major expenses,Shortfall share,Balance P10,Balance P25,Balance median,Balance P75,Balance P90,Median without major expenses"
    let rows = periods.map { p in
      let flows = [p.save, p.income, p.spend, p.expenseCost].map { String(format: "%.0f", floor($0 + 0.5)) }
      let balances = (p.balance + [p.noExpenses[2]]).map { String(format: "%.0f", floor($0 + 0.5)) }
      return ([String(p.year), String(p.age)] + flows + [String(p.shortfall)] + balances).joined(separator: ",")
    }
    return ([header] + rows).joined(separator: "\n")
  }
}

public enum Retirement {
  private struct Period {
    var age: Int
    var save, spend, income, expense, mean, volatility: Double
    var goals: [Int]
    var balances: [Double] = [], baseline: [Double] = []
    var misses = 0
  }

  public static func project(_ plan: Plan, count: Int = 1000, seed: Double? = nil) -> RetirementProjection {
    let settings = plan.retirement ?? RetirementSettings()
    let budget = Forecast.budget(plan)
    let age = Int(plan.startAge)
    let retireAge = max(age, min(120, settings.retireAge ?? 65))
    let end = max(retireAge, min(120, settings.throughAge ?? 95))
    let incomeAge = settings.incomeAge ?? retireAge
    let saving = settings.monthlySave ?? floor(max(0, budget.net - budget.spend) + (budget.contribution + budget.employerMatch) / 12 + 0.5)
    let mean = settings.beforeReturn ?? clamp(plan.roi, -30, 25)
    let volatility = settings.beforeVolatility ?? clamp(plan.volatility, 0, 60)
    let inflation = 1 + (settings.inflation ?? clamp(plan.inflation, 0, 15)) / 100
    let assets = settings.startingAssets ?? clamp(plan.assets, 0, 100_000_000)
    var periods = (age...end).map { year in
      let retired = year >= retireAge
      let goals = settings.expenses.indices.filter { settings.expenses[$0].startAge <= year && settings.expenses[$0].endAge >= year }
      return Period(age: year, save: retired ? 0 : saving * 12,
                    spend: retired ? (settings.monthlySpend ?? 0) * 12 : 0,
                    income: retired && year >= incomeAge ? settings.monthlyIncome * 12 : 0,
                    expense: goals.reduce(0) { $0 + settings.expenses[$1].cost },
                    mean: retired ? settings.afterReturn ?? mean : mean,
                    volatility: retired ? settings.afterVolatility ?? volatility : volatility, goals: goals)
    }
    var random = SeededRandom(seed ?? plan.seed)
    let runs = max(1, count)
    var start: [Double] = []
    var funded = Array(repeating: 0, count: settings.expenses.count)
    var success = 0, baselineSuccess = 0
    for _ in 0..<runs {
      var balance = assets, baseline = assets
      var shortfall = false, baselineShortfall = false
      var missed = Set<Int>()
      for i in periods.indices {
        let period = periods[i]
        if period.age == retireAge { start.append(balance) }
        let growth = (1 + clamp((period.mean + random.normal() * period.volatility) / 100, -0.95, 1.5)) / inflation
        let cashFlow = period.save + period.income - period.spend
        let beforeExpenses = balance * growth + cashFlow
        let end = beforeExpenses - period.expense
        let baselineEnd = baseline * growth + cashFlow
        if period.expense > 0 && clamp(beforeExpenses / period.expense, 0, 1) < 1 - 1e-10 {
          missed.formUnion(period.goals)
        }
        if end < -1e-7 {
          periods[i].misses += 1
          shortfall = true
        }
        if baselineEnd < -1e-7 { baselineShortfall = true }
        balance = max(0, end)
        baseline = max(0, baselineEnd)
        periods[i].balances.append(balance)
        periods[i].baseline.append(baseline)
      }
      if !shortfall { success += 1 }
      if !baselineShortfall { baselineSuccess += 1 }
      for i in funded.indices where !missed.contains(i) { funded[i] += 1 }
    }
    let years = periods.map { p in
      RetirementYear(age: p.age, year: Int(plan.startYear) + p.age - age, save: p.save, spend: p.spend,
                     income: p.income, expenseCost: p.expense, shortfall: Double(p.misses) / Double(runs),
                     balance: quantiles(p.balances), noExpenses: quantiles(p.baseline),
                     goalNames: p.goals.map { settings.expenses[$0].name })
    }
    let funding = settings.expenses.enumerated().map { i, expense in
      max(expense.startAge, age) <= min(expense.endAge, end) ? Double(funded[i]) / Double(runs) : nil
    }
    return RetirementProjection(periods: years, expenseFunding: funding, hasRetirement: settings.monthlySpend != nil,
                                coverage: Double(success) / Double(runs), baselineCoverage: Double(baselineSuccess) / Double(runs),
                                retirementStart: quantiles(start), runs: runs)
  }
}
