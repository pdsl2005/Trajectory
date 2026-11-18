import Foundation
import XCTest
@testable import TrajectoryCore

final class ModelTests: XCTestCase {
  func testJavaScriptFixtures() throws {
    let data = try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "models", withExtension: "json")))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var profile = Profile()
    try profile.importBackup(JSONSerialization.data(withJSONObject: try XCTUnwrap(json["backup"])))
    let plan = try XCTUnwrap(profile.scenarios["Fixture"]).forecastPlan
    let budget = Forecast.budget(plan)
    let expectedBudget = try XCTUnwrap(json["budget"] as? [String: Double])
    for (key, actual) in ["net": budget.net, "spend": budget.spend, "tax": budget.taxes, "ira": budget.ira, "broker": budget.brokerage, "match": budget.employerMatch, "target": budget.emergencyTarget] {
      XCTAssertEqual(actual, try XCTUnwrap(expectedBudget[key]), accuracy: 0.000001, key)
    }
    for fixture in try XCTUnwrap(json["forecasts"] as? [[String: Any]]) {
      let options = try XCTUnwrap(fixture["options"] as? [String: Any])
      let career: Career = options["mode"] as? String == "switch" ? .change : options["mode"] as? String == "save" ? .save : .base
      let actual = Forecast.simulate(plan, count: try XCTUnwrap(options["n"] as? Int), career: career,
                                     deterministic: options["det"] as? Bool ?? false, returnOverride: options["returnOverride"] as? Double)
      let expected = try XCTUnwrap(fixture["output"] as? [[String: Any]])
      XCTAssertEqual(actual.count, expected.count)
      for (row, reference) in zip(actual, expected) {
        XCTAssertEqual(row.year, reference["year"] as? Int)
        XCTAssertEqual(row.age, reference["age"] as? Int)
        XCTAssertEqual(Set(row.values.keys), Set(reference.keys).subtracting(["year", "age"]))
        for (key, values) in row.values {
          for (a, b) in zip(values, try XCTUnwrap(reference[key] as? [Double])) {
            XCTAssertEqual(a, b, accuracy: 0.000001, "\(row.year) \(career) \(key)")
          }
        }
      }
    }
    let retirement = Retirement.project(plan, count: 100)
    let expected = try XCTUnwrap(json["retirement"] as? [String: Any])
    XCTAssertEqual(retirement.coverage, expected["coverage"] as? Double)
    XCTAssertEqual(retirement.baselineCoverage, expected["baselineCoverage"] as? Double)
    XCTAssertEqual(retirement.expenseFunding.compactMap { $0 }, expected["expenseFunding"] as? [Double])
    for (row, reference) in zip(retirement.periods, try XCTUnwrap(expected["periods"] as? [[String: Any]])) {
      XCTAssertEqual(row.age, reference["age"] as? Int)
      XCTAssertEqual(row.goalNames, reference["goalNames"] as? [String])
      XCTAssertEqual(row.shortfall, reference["shortfall"] as? Double)
      for (a, b) in zip(row.balance, try XCTUnwrap(reference["balance"] as? [Double])) {
        XCTAssertEqual(a, b, accuracy: 0.000001)
      }
    }
  }

  func testLegacyMigrationAndNativeRoundTrip() throws {
    var profile = Profile()
    profile.manual = [ManualEntry(day: "2027-01-31", name: "Store", category: "Food", kind: .expense, amount: 22)]
    try profile.importBackup(Data(#"{"active":"Old","plans":{"Old":{"rent":123,"cashShare":90,"rothShare":70,"startYear":2300,"backdoor":1,"retirement":{"expenses":[{"name":"Roof","cost":50,"startAge":40,"endAge":38}]}}}}"#.utf8))
    let plan = try XCTUnwrap(profile.scenarios["Old"]).forecastPlan
    XCTAssertEqual(plan.startAge, 22)
    XCTAssertEqual(plan.startYear, 2200)
    XCTAssertEqual(plan.cashShare, 90)
    XCTAssertEqual(plan.rothShare, 10)
    XCTAssertEqual(plan.workplaceShare, 0)
    XCTAssertEqual(plan.rent, 123)
    XCTAssertFalse(plan.backdoor)
    XCTAssertEqual(plan.retirement?.expenses.first?.endAge, 40)
    XCTAssertEqual(profile.manual.count, 1)
    var restored = Profile()
    try restored.importBackup(profile.backup())
    XCTAssertEqual(restored, profile)
  }

  func testRecurringMonthBoundariesAndStableForecast() throws {
    var profile = Profile()
    profile.scenarios["Baseline"]?.targets[0].amount = 50
    let before = try XCTUnwrap(profile.scenarios["Baseline"]).forecastPlan
    profile.recurring = [RecurringRule(entry: ManualEntry(day: "2028-01-31", name: "Rent", category: "Housing", kind: .expense, amount: 75))]
    profile.generate(through: "2028-02-28")
    XCTAssertEqual(profile.manual.map(\.day), ["2028-01-31"])
    profile.generate(through: "2028-03-01")
    profile.generate(through: "2028-03-01")
    XCTAssertEqual(profile.manual.map(\.day), ["2028-01-31", "2028-02-29"])
    XCTAssertEqual(profile.summary(month: "2028-02").net, -75)
    XCTAssertEqual(before.rent - profile.summary(month: "2028-02").spent, -25)
    XCTAssertEqual(before, profile.scenarios["Baseline"]?.forecastPlan)
    profile.recurring[0].entry.day = "2028-01-15"
    profile.generate(through: "2028-02-29")
    XCTAssertEqual(profile.manual.map(\.day), ["2028-01-31", "2028-02-29"])
  }

  func testNativeLifeEventsAffectTheTenYearProjection() throws {
    var plan = Plan()
    plan.assets = 100_000
    plan.salary = 45_000
    var settings = RetirementSettings()
    settings.expenses = [MajorExpense(name: "Repairs", cost: 10_000, startAge: 32, endAge: 32)]
    plan.retirement = settings
    let legacy = Forecast.simulate(plan, count: 1, deterministic: true)
    let withExpense = Forecast.simulate(plan, count: 1, deterministic: true, includeLifeEvents: true)
    XCTAssertEqual(legacy[1].values["individual"], withExpense[1].values["individual"])
    XCTAssertLessThan(try XCTUnwrap(withExpense[2].values["individual"]?[2]),
                      try XCTUnwrap(legacy[2].values["individual"]?[2]))
    settings.retireAge = 35
    settings.monthlyIncome = 1_000
    plan.retirement = settings
    let retired = Forecast.simulate(plan, count: 1, deterministic: true, includeLifeEvents: true)
    XCTAssertEqual(retired[5].values["g"]?[2], 0)
    XCTAssertGreaterThan(try XCTUnwrap(retired[5].values["houseIncome"]?[2]), 0)
  }

  func testCardReconciliation() {
    var profile = Profile()
    var entry = ManualEntry(day: "2028-01-31", name: "Store", category: "Food", kind: .expense, amount: 10)
    entry.matchedCharge = "card/pending"
    profile.manual = [entry]
    profile.categoryOverrides["card/pending"] = "Goods"
    let pending = Charge(id: "pending", day: "2028-01-31", name: "Store", category: "Food", amount: 10, pending: true, excluded: false)
    profile.apply(connection: "card", from: nil, to: "one", changes: [pending], removed: [])
    XCTAssertEqual(profile.summary(month: "2028-01").pending, 10)
    XCTAssertEqual(profile.summary(month: "2028-01").spent, 10)
    let posted = Charge(id: "posted", day: "2028-02-01", name: "Store", category: "Food", amount: 11, pending: false, excluded: false, pendingID: "pending")
    let refund = Charge(id: "refund", day: "2028-02-02", name: "Store", category: "Goods", amount: -3, pending: false, excluded: false)
    let payment = Charge(id: "payment", day: "2028-02-02", name: "Payment", category: "Goods", amount: -50, pending: false, excluded: true)
    profile.apply(connection: "card", from: "one", to: "two", changes: [posted, refund, payment], removed: ["pending"])
    profile.apply(connection: "card", from: "one", to: "bad", changes: [], removed: ["posted"])
    XCTAssertEqual(profile.cards["card"]?.cursor, "two")
    XCTAssertEqual(profile.manual.first?.matchedCharge, "card/posted")
    XCTAssertEqual(profile.summary(month: "2028-01").spent, 0)
    XCTAssertEqual(profile.summary(month: "2028-02").spending, ["Goods": 8])
  }
}
