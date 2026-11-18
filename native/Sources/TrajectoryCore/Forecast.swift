import Foundation

public enum Career: String, CaseIterable, Identifiable {
  case base, change, save
  public var id: Self { self }
}

public struct BudgetProjection {
  public let net, spend, contribution, employerMatch, taxes, ira, eligibility, emergencyTarget, brokerage: Double
}

public struct ForecastYear: Identifiable {
  public let year, age: Int
  public let values: [String: [Double]]
  public var id: Int { year }

  public func series(household: Bool, real: Bool) -> [Double] {
    values[household ? (real ? "houseReal" : "house") : (real ? "real" : "individual")] ?? []
  }
}

public enum Forecast {
  static func taxes(_ gross: Double, _ spouse: Double, _ contribution: Double, _ spouseContribution: Double,
                    _ joint: Bool, _ index: Double, _ stateRate: Double) -> Double {
    let factor: Double = joint ? 2 : 1
    let adjusted = gross + spouse - contribution - spouseContribution
    let taxable = max(0, adjusted - 16_600 * factor * index)
    let thresholds: [Double] = [12_800, 52_025, 109_125, 208_325, 264_550, 661_375, .infinity]
    let rates = [0.1, 0.12, 0.22, 0.24, 0.32, 0.35, 0.37]
    var last = 0.0
    var federal = 0.0
    for (i, threshold) in thresholds.enumerated() {
      let cap = joint && i == 5 ? 792_100 * index : threshold * factor * index
      federal += max(0, min(taxable, cap) - last) * rates[i]
      last = cap
    }
    let state = max(0, adjusted - 4_400 * factor - 3_600) * stateRate / 100
    let payroll = [gross, spouse].reduce(0.0) { sum, pay in
      let capped = min(pay, 184_500 * index)
      return sum + capped * 0.062 + pay * 0.0145 + capped * 0.0046
    }
    return federal + state + payroll + max(0, gross + spouse - (joint ? 250_000 : 200_000)) * 0.009
  }

  static func allowance(_ income: Double, _ low: Double, _ high: Double, _ limit: Double) -> Double {
    if income <= low { return limit }
    if income >= high { return 0 }
    return min(limit, max(200, ceil(limit * (high - income) / (high - low) / 10) * 10))
  }

  static func match(_ gross: Double, _ plan: Plan) -> Double {
    gross * (min(plan.contribution, plan.matchFull) +
      min(plan.matchHalf, max(0, plan.contribution - plan.matchFull)) * 0.5) / 100
  }

  public static func budget(_ plan: Plan) -> BudgetProjection {
    let gross = plan.salary
    let contribution = min(gross * plan.contribution / 100, plan.kLimit)
    let tax = taxes(gross, 0, contribution, 0, false, 1, plan.stateTax)
    let eligibility = allowance(gross - contribution + plan.otherMagi, plan.singleLower, plan.singleUpper, plan.iraLimit)
    let net = (gross - contribution - tax) / 12
    let spend = plan.living + plan.goldFee / 12
    let ira = min(max(0, (net - spend) * 12), plan.backdoor ? plan.iraLimit : eligibility)
    let essential = plan.rent + plan.food + plan.utilities + plan.transport + plan.medical + plan.renters
    return BudgetProjection(net: net, spend: spend, contribution: contribution, employerMatch: match(gross, plan),
                            taxes: tax, ira: ira, eligibility: eligibility, emergencyTarget: essential * plan.emergencyMonths,
                            brokerage: net - spend - ira / 12)
  }

  private struct Accounts {
    var cash = 0.0, roth = 0.0, workplace = 0.0, brokerage = 0.0, debt = 0.0
    var net: Double { cash + roth + workplace + brokerage - debt }
    var accessible: Double { cash + brokerage - debt }

    mutating func allocate(_ surplus: Double, target: Double, gross: Double, limit: Double,
                           eligibility: Double, bonus: Double) -> (ira: Double, direct: Double, brokerage: Double, tax: Double) {
      let fill = min(max(0, surplus), max(0, target - cash))
      cash += fill
      var remaining = surplus - fill
      let repayment = min(debt, max(0, remaining))
      debt -= repayment
      remaining -= repayment
      let ira = min(max(0, remaining), gross, limit)
      let direct = min(ira, eligibility)
      let tax = (ira - direct) * bonus * 0.29
      roth += ira * (1 + bonus)
      remaining -= ira + tax
      let brokerageContribution = max(0, remaining)
      brokerage += brokerageContribution
      if remaining < 0 {
        let cashDraw = min(cash, -remaining)
        cash -= cashDraw
        remaining += cashDraw
        let brokerageDraw = min(brokerage, -remaining)
        brokerage -= brokerageDraw
        remaining += brokerageDraw
        debt += max(0, -remaining)
      }
      return (ira, direct, brokerageContribution, tax)
    }

    mutating func grow(_ s: Plan, rate: Double, fraction: Double, contribution: Double, match: Double) {
      cash *= pow(1 + s.cashReturn / 100, fraction)
      let growth = pow(1 + rate, fraction)
      roth *= growth
      workplace = workplace * growth + contribution + match
      brokerage *= pow(max(0.05, 1 + rate - s.taxDrag / 100), fraction)
      debt *= pow(1.08, fraction)
    }
  }

  public static func simulate(_ s: Plan, count: Int = 1500, career: Career = .base,
                              deterministic: Bool = false, returnOverride: Double? = nil,
                              includeLifeEvents: Bool = false) -> [ForecastYear] {
    var random = SeededRandom(s.seed)
    var years = Array(repeating: [String: [Double]](), count: 11)
    let lifeEvents = includeLifeEvents ? s.retirement : nil
    let cash = clamp(s.cashShare, 0, 100)
    let roth = clamp(s.rothShare, 0, 100 - cash)
    let workplace = clamp(s.workplaceShare, 0, 100 - cash - roth)
    func monthsLost(_ risk: Double) -> Double {
      if deterministic || random.next() >= risk / 100 { return 0 }
      return 2 + floor(random.next() * 4)
    }
    for _ in 0..<max(1, count) {
      var own = Accounts(cash: s.assets * cash / 100, roth: s.assets * roth / 100,
                         workplace: s.assets * workplace / 100, brokerage: s.assets * (100 - cash - roth - workplace) / 100,
                         debt: max(0, s.startingDebt ?? 0))
      var spouse = Accounts()
      var salary = s.salary
      var spouseSalary = s.salary * s.spouseRatio / 100
      let rentFactor = deterministic ? 1 : 0.85 + random.next() * 0.45
      let childFactor = deterministic ? 1 : 0.65 + random.next() * 0.9
      let marriage = s.marriage + (deterministic ? 0 : floor(random.next() * 3) - 1)
      let weddingFactor = deterministic ? 1 : 0.5 + random.next()
      for i in years.indices {
        let age = s.startAge + Double(i)
        let inflation = pow(1 + s.inflation / 100, Double(i))
        let index = pow(1 + s.limitGrowth / 100, Double(i))
        let months = i == 0 ? s.startMonths : 12
        let fraction = months / 12
        let married = s.marriage > 0 && age >= marriage
        if i > 0 {
          let raise = deterministic ? s.raise / 100 : clamp(s.raise / 100 + random.normal() * 0.012, -0.05, 0.12)
          salary *= 1 + raise
          spouseSalary *= 1 + raise
        }
        let switched = career == .change && age == s.switchAge
        if switched { salary *= 1 + s.switchRaise / 100 }
        let rate = clamp((returnOverride ?? s.roi) / 100 + (deterministic ? 0 : random.normal() * s.volatility / 100), -0.85, 1.5)
        let lost = monthsLost(s.jobRisk)
        let spouseLost = monthsLost(s.spouseRisk)
        let retirementAge = Double(lifeEvents?.retireAge ?? 65)
        let retired = lifeEvents != nil && age >= retirementAge
        let gross = retired ? 0 : salary * max(0, months - lost - (switched ? s.switchGap : 0)) / 12
        let retirementIncome = retired && age >= Double(lifeEvents?.incomeAge ?? Int(retirementAge))
          ? (lifeEvents?.monthlyIncome ?? 0) * 12 * fraction * inflation : 0
        let partner = married ? spouseSalary * max(0, 12 - spouseLost) / 12 : 0
        let contribution = min(gross * s.contribution / 100, s.kLimit * index)
        let partnerContribution = min(partner * s.spouseContribution / 100, s.kLimit * index)
        let employer = match(gross, s)
        let partnerMatch = partner * min(s.spouseContribution, s.spouseMatch) / 100
        var child = 0.0
        for birth in [s.firstChild, s.secondChild] where married && birth > 0 && age >= birth && age - birth < 18 {
          child += (age - birth < 5 ? s.youngCost : s.olderCost) * childFactor * 12 * inflation
        }
        let housing = (married ? s.houseRent : s.rent) * rentFactor
        let individualCosts = housing + s.living - s.rent + (age >= 26 ? s.health : 0)
        let modeledCosts = retired ? lifeEvents?.monthlySpend ?? individualCosts : individualCosts
        let regular = (modeledCosts + (married ? s.spouseOther : 0)) * 12 * fraction * inflation
        let goals = lifeEvents?.expenses.filter {
          age >= Double($0.startAge) && age <= Double($0.endAge)
        }.reduce(0.0) { $0 + max(0, $1.cost) } ?? 0
        var expense = regular + child + s.goldFee + goals * inflation
        if married && s.spouseGold { expense += s.goldFee }
        if married && age == marriage { expense += s.wedding * weddingFactor }
        if switched { expense += s.switchCost }
        if career == .save { expense -= min(s.extraSave * 12 * fraction, regular * 0.25) }
        let tax = taxes(gross, partner, contribution, partnerContribution, married, index, s.stateTax)
        let magi = gross + partner - contribution - partnerContribution + s.otherMagi
        let limit = floor(s.iraLimit * index / 500 + 0.5) * 500
        let low = (married ? s.jointLower : s.singleLower) * index
        let high = (married ? s.jointUpper : s.singleUpper) * index
        let eligible = allowance(magi, low, high, limit)
        let totalIncome = gross + partner + retirementIncome
        let surplus = totalIncome - contribution - partnerContribution - tax - expense
        let share = married ? (totalIncome > 0 ? (gross + retirementIncome) / totalIncome : 1 / (1 + s.spouseRatio / 100)) : 1
        own.grow(s, rate: rate, fraction: fraction, contribution: contribution, match: employer)
        spouse.grow(s, rate: rate, fraction: 1, contribution: partnerContribution, match: partnerMatch)
        if married && (i == 0 || age == marriage) { spouse.brokerage += s.spouseAssets }
        let essential = housing + s.food + s.utilities + s.transport + s.medical + s.renters
        let target = (essential + (married ? s.spouseOther * 0.6 : 0) + child / 12 / inflation) * s.emergencyMonths * inflation
        let bonus = s.goldMatch / 100
        let partnerBonus = s.spouseGold ? bonus : 0.01
        let a = own.allocate(surplus * share, target: target * share, gross: gross,
                             limit: s.backdoor ? limit : eligible, eligibility: eligible, bonus: bonus)
        let b = spouse.allocate(surplus * (1 - share), target: target * (1 - share), gross: partner,
                               limit: married ? (s.spouseBackdoor ? limit : eligible) : 0, eligibility: eligible, bonus: partnerBonus)
        let household = own.net + spouse.net
        let row: [String: Double] = [
          "houseCash": own.cash + spouse.cash, "houseRoth": own.roth + spouse.roth,
          "houseWorkplace": own.workplace + spouse.workplace, "houseBroker": own.brokerage + spouse.brokerage,
          "houseIncome": totalIncome, "ownExpense": expense * share, "ownTax": tax * share,
          "surplus": surplus, "ownSurplus": surplus * share, "ownDebt": own.debt,
          "ownShortfall": max(0, -surplus * share), "ownWorkplaceContribution": contribution,
          "houseWorkplaceContribution": contribution + partnerContribution, "ownEmployerMatch": employer,
          "houseEmployerMatch": employer + partnerMatch, "houseIra": a.ira + b.ira,
          "houseBrokerageContribution": a.brokerage + b.brokerage, "houseDirect": a.direct + b.direct,
          "houseBackdoor": a.ira - a.direct + b.ira - b.direct,
          "individual": own.net, "house": household, "accessible": own.accessible,
          "houseAccessible": own.accessible + spouse.accessible, "real": own.net / inflation, "houseReal": household / inflation,
          "h": own.cash, "r": own.roth, "k": own.workplace, "b": own.brokerage,
          "sh": spouse.cash, "sr": spouse.roth, "sk": spouse.workplace, "sb": spouse.brokerage,
          "debt": own.debt + spouse.debt, "g": gross, "p": partner, "tax": tax, "expense": expense,
          "child": child, "regular": regular, "ira": a.ira, "pi": b.ira, "direct": a.direct,
          "backdoor": a.ira - a.direct, "eligible": eligible, "lo": low, "hi": high, "magi": magi,
          "brokerage": a.brokerage, "spBroker": b.brokerage, "em": employer,
          "contribution": surplus + contribution + partnerContribution + employer + partnerMatch + a.ira * bonus + b.ira * partnerBonus - a.tax - b.tax,
          "shortfall": max(0, -surplus)
        ]
        for (key, value) in row { years[i][key, default: []].append(value) }
      }
    }
    return years.enumerated().map { i, values in
      ForecastYear(year: Int(s.startYear) + i, age: Int(s.startAge) + i, values: values.mapValues(quantiles))
    }
  }

  public static func csv(_ years: [ForecastYear], household: Bool, real: Bool) -> String {
    (["Year,Age,P10,P25,P50,P75,P90"] + years.map { year in
      ([String(year.year), String(year.age)] + year.series(household: household, real: real).map { String($0) }).joined(separator: ",")
    }).joined(separator: "\n")
  }
}
