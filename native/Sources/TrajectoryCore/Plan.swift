import Foundation
import CoreFoundation

public struct Plan: Codable, Equatable {
  public var startAge: Double = 30
  public var startYear: Double = 2027
  public var startMonths: Double = 12
  public var salary: Double = 0
  public var assets: Double = 0
  public var cashShare: Double = 100
  public var rothShare: Double = 0
  public var workplaceShare: Double = 0
  public var rent: Double = 0
  public var food: Double = 0
  public var utilities: Double = 0
  public var transport: Double = 0
  public var goods: Double = 0
  public var entertainment: Double = 0
  public var medical: Double = 0
  public var renters: Double = 0
  public var travel: Double = 0
  public var misc: Double = 0
  public var goldFee: Double = 0
  public var goldMatch: Double = 0
  public var contribution: Double = 0
  public var matchFull: Double = 0
  public var matchHalf: Double = 0
  public var raise: Double = 3
  public var roi: Double = 7
  public var optimistic: Double = 10
  public var volatility: Double = 16
  public var inflation: Double = 2.5
  public var limitGrowth: Double = 2.5
  public var cashReturn: Double = 2
  public var taxDrag: Double = 0.5
  public var stateTax: Double = 0
  public var marriage: Double = 0
  public var spouseRatio: Double = 0
  public var spouseContribution: Double = 0
  public var spouseMatch: Double = 0
  public var spouseAssets: Double = 0
  public var houseRent: Double = 0
  public var spouseOther: Double = 0
  public var health: Double = 0
  public var wedding: Double = 0
  public var firstChild: Double = 0
  public var secondChild: Double = 0
  public var youngCost: Double = 0
  public var olderCost: Double = 0
  public var emergencyMonths: Double = 3
  public var jobRisk: Double = 3
  public var spouseRisk: Double = 3
  public var switchAge: Double = 32
  public var switchRaise: Double = 15
  public var switchCost: Double = 0
  public var switchGap: Double = 0
  public var extraSave: Double = 100
  public var backdoor: Bool = false
  public var spouseBackdoor: Bool = false
  public var spouseGold: Bool = false
  public var iraLimit: Double = 7500
  public var kLimit: Double = 25500
  public var singleLower: Double = 158000
  public var singleUpper: Double = 173000
  public var jointLower: Double = 250000
  public var jointUpper: Double = 260000
  public var otherMagi: Double = 0
  public var seed: Double = 91520
  public var retirement: RetirementSettings?
  public var startingDebt: Double?
  public init() {}

  init(web raw: [String: Any]) {
    startAge = 22
    startYear = 2027
    cashShare = 25
    rothShare = 25
    workplaceShare = 5
    matchFull = 3
    matchHalf = 2
    stateTax = 5
    if let value = raw["startAge"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { startAge = value.doubleValue }
    if let value = raw["startYear"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { startYear = value.doubleValue }
    if let value = raw["startMonths"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { startMonths = value.doubleValue }
    if let value = raw["salary"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { salary = value.doubleValue }
    if let value = raw["assets"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { assets = value.doubleValue }
    if let value = raw["cashShare"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { cashShare = value.doubleValue }
    if let value = raw["rothShare"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { rothShare = value.doubleValue }
    if let value = raw["workplaceShare"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { workplaceShare = value.doubleValue }
    if let value = raw["rent"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { rent = value.doubleValue }
    if let value = raw["food"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { food = value.doubleValue }
    if let value = raw["utilities"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { utilities = value.doubleValue }
    if let value = raw["transport"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { transport = value.doubleValue }
    if let value = raw["goods"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { goods = value.doubleValue }
    if let value = raw["entertainment"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { entertainment = value.doubleValue }
    if let value = raw["medical"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { medical = value.doubleValue }
    if let value = raw["renters"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { renters = value.doubleValue }
    if let value = raw["travel"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { travel = value.doubleValue }
    if let value = raw["misc"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { misc = value.doubleValue }
    if let value = raw["goldFee"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { goldFee = value.doubleValue }
    if let value = raw["goldMatch"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { goldMatch = value.doubleValue }
    if let value = raw["contribution"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { contribution = value.doubleValue }
    if let value = raw["matchFull"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { matchFull = value.doubleValue }
    if let value = raw["matchHalf"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { matchHalf = value.doubleValue }
    if let value = raw["raise"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { raise = value.doubleValue }
    if let value = raw["roi"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { roi = value.doubleValue }
    if let value = raw["optimistic"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { optimistic = value.doubleValue }
    if let value = raw["volatility"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { volatility = value.doubleValue }
    if let value = raw["inflation"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { inflation = value.doubleValue }
    if let value = raw["limitGrowth"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { limitGrowth = value.doubleValue }
    if let value = raw["cashReturn"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { cashReturn = value.doubleValue }
    if let value = raw["taxDrag"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { taxDrag = value.doubleValue }
    if let value = raw["stateTax"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { stateTax = value.doubleValue }
    if let value = raw["marriage"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { marriage = value.doubleValue }
    if let value = raw["spouseRatio"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { spouseRatio = value.doubleValue }
    if let value = raw["spouseContribution"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { spouseContribution = value.doubleValue }
    if let value = raw["spouseMatch"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { spouseMatch = value.doubleValue }
    if let value = raw["spouseAssets"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { spouseAssets = value.doubleValue }
    if let value = raw["houseRent"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { houseRent = value.doubleValue }
    if let value = raw["spouseOther"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { spouseOther = value.doubleValue }
    if let value = raw["health"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { health = value.doubleValue }
    if let value = raw["wedding"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { wedding = value.doubleValue }
    if let value = raw["firstChild"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { firstChild = value.doubleValue }
    if let value = raw["secondChild"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { secondChild = value.doubleValue }
    if let value = raw["youngCost"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { youngCost = value.doubleValue }
    if let value = raw["olderCost"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { olderCost = value.doubleValue }
    if let value = raw["emergencyMonths"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { emergencyMonths = value.doubleValue }
    if let value = raw["jobRisk"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { jobRisk = value.doubleValue }
    if let value = raw["spouseRisk"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { spouseRisk = value.doubleValue }
    if let value = raw["switchAge"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { switchAge = value.doubleValue }
    if let value = raw["switchRaise"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { switchRaise = value.doubleValue }
    if let value = raw["switchCost"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { switchCost = value.doubleValue }
    if let value = raw["switchGap"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { switchGap = value.doubleValue }
    if let value = raw["extraSave"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { extraSave = value.doubleValue }
    if let value = raw["backdoor"] as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() { backdoor = value.boolValue }
    if let value = raw["spouseBackdoor"] as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() { spouseBackdoor = value.boolValue }
    if let value = raw["spouseGold"] as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() { spouseGold = value.boolValue }
    if let value = raw["iraLimit"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { iraLimit = value.doubleValue }
    if let value = raw["kLimit"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { kLimit = value.doubleValue }
    if let value = raw["singleLower"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { singleLower = value.doubleValue }
    if let value = raw["singleUpper"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { singleUpper = value.doubleValue }
    if let value = raw["jointLower"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { jointLower = value.doubleValue }
    if let value = raw["jointUpper"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { jointUpper = value.doubleValue }
    if let value = raw["otherMagi"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { otherMagi = value.doubleValue }
    if let value = raw["seed"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite { seed = value.doubleValue }
    startAge = clamp(floor(startAge + 0.5), 18, 100)
    startYear = clamp(floor(startYear + 0.5), 1900, 2200)
    cashShare = clamp(cashShare, 0, 100)
    rothShare = clamp(rothShare, 0, 100 - cashShare)
    workplaceShare = clamp(workplaceShare, 0, 100 - cashShare - rothShare)
    if let settings = raw["retirement"] as? [String: Any] {
      retirement = RetirementSettings(web: settings)
    }
  }

  public static let spending: [(String, WritableKeyPath<Plan, Double>)] = [
    ("Housing", \.rent), ("Food", \.food), ("Utilities", \.utilities),
    ("Transport", \.transport), ("Goods", \.goods), ("Entertainment", \.entertainment),
    ("Medical", \.medical), ("Renters insurance", \.renters), ("Travel", \.travel),
    ("Miscellaneous", \.misc)
  ]
  public var living: Double { Self.spending.reduce(0) { $0 + self[keyPath: $1.1] } }
}

func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
  min(upper, max(lower, value))
}

struct SeededRandom {
  var state: UInt32
  init(_ seed: Double) {
    let wrapped = seed.rounded(.towardZero).truncatingRemainder(dividingBy: 4_294_967_296)
    state = wrapped.isFinite ? UInt32(wrapped < 0 ? wrapped + 4_294_967_296 : wrapped) : 0
  }
  mutating func next() -> Double {
    state = state &* 1_664_525 &+ 1_013_904_223
    return (Double(state) + 0.5) / 4_294_967_296
  }
  mutating func normal() -> Double {
    let radius = sqrt(-2 * log(next()))
    return radius * cos(2 * .pi * next())
  }
}

func quantiles(_ values: [Double]) -> [Double] {
  guard !values.isEmpty else { return [] }
  let sorted = values.sorted()
  return [0.1, 0.25, 0.5, 0.75, 0.9].map { sorted[Int(Double(sorted.count - 1) * $0)] }
}
