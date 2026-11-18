import SwiftUI
import TrajectoryCore

struct ScenariosView: View {
  @EnvironmentObject private var store: Store
  @State private var name = ""
  @State private var draft: Draft?
  @State private var saved = 0

  struct Draft: Identifiable {
    var id: String
    var scenario: Scenario
  }

  var body: some View {
    Form {
      Section("Saved scenarios") {
        Picker("Saved baseline", selection: Binding(get: { store.profile.baseline }, set: { name in store.edit { $0.baseline = name } })) {
          ForEach(store.profile.scenarios.keys.sorted(), id: \.self) { Text($0).tag($0) }
        }
        ForEach(store.profile.scenarios.keys.sorted(), id: \.self) { key in
          Button {
            if let scenario = store.profile.scenarios[key] { draft = Draft(id: key, scenario: scenario) }
          } label: {
            LabeledContent(key, value: key == store.profile.active ? "Active" : "")
          }.swipeActions {
            if key != store.profile.baseline && key != store.profile.active {
              Button("Delete", role: .destructive) { store.edit { $0.scenarios.removeValue(forKey: key) } }
            }
          }
        }
      }
      Section("Duplicate active scenario") {
        TextField("Scenario name", text: $name)
        Button("Create scenario") {
          let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
          let source = store.scenario
          store.edit {
            $0.scenarios[key] = source
            $0.active = key
          }
          draft = Draft(id: key, scenario: source)
          name = ""
        }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                   store.profile.scenarios[name.trimmingCharacters(in: .whitespacesAndNewlines)] != nil)
      }
    }
    .trajectorySurface()
    .navigationTitle("Scenarios")
    .sensoryFeedback(.success, trigger: saved)
    .sheet(item: $draft) { draft in
      ScenarioEditor(draft: draft, baseline: store.profile.scenarios[store.profile.baseline] ?? Scenario()) { scenario in
        do {
          try store.update {
            $0.scenarios[draft.id] = scenario
            $0.active = draft.id
          }
          saved += 1
        } catch { store.error = error.localizedDescription }
      }
    }
  }
}

private struct ScenarioEditor: View {
  @Environment(\.dismiss) private var dismiss
  @FocusState private var focused: String?
  @State var draft: ScenariosView.Draft
  let baseline: Scenario
  let save: (Scenario) -> Void
  @State private var delta: Double?
  @State private var career = Career.base
  @State private var household = false
  @State private var firstBaseline: [ForecastYear] = []
  @State private var adjustmentKey: WritableKeyPath<Plan, Double>?

  private struct ImpactInput: Equatable {
    var plan: Plan
    var career: Career
    var household: Bool
  }

  private var impact: ImpactInput {
    ImpactInput(plan: draft.scenario.forecastPlan, career: career, household: household)
  }

  private func field(_ title: String, _ key: WritableKeyPath<Plan, Double>, currency: Bool = false) -> some View {
    AmountField(title: title, value: $draft.scenario.plan[dynamicMember: key], currency: currency)
      .focused($focused, equals: title)
      .onChange(of: focused) { _, next in if next == title { adjustmentKey = currency ? key : nil } }
  }

  private func retirement<Value>(_ key: WritableKeyPath<RetirementSettings, Value?>, default fallback: Value) -> Binding<Value> {
    Binding(get: { draft.scenario.plan.retirement?[keyPath: key] ?? fallback }, set: { value in
      var settings = draft.scenario.plan.retirement ?? RetirementSettings()
      settings[keyPath: key] = value
      draft.scenario.plan.retirement = settings
    })
  }

  private var retirementYears: Binding<[MajorExpense]> {
    Binding(get: { draft.scenario.plan.retirement?.expenses ?? [] }, set: { value in
      var settings = draft.scenario.plan.retirement ?? RetirementSettings()
      settings.expenses = value
      draft.scenario.plan.retirement = settings
    })
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Career") {
          field("Annual salary", \.salary, currency: true)
          field("Annual raise (%)", \.raise)
          Picker("Impact comparison", selection: $career) {
            Text("Current path").tag(Career.base)
            Text("Job change").tag(Career.change)
            Text("Extra saving").tag(Career.save)
          }
          DisclosureGroup("Job change & extra saving") {
            field("Job change age", \.switchAge)
            field("Salary change (%)", \.switchRaise)
            field("Transition cost", \.switchCost, currency: true)
            field("Months between jobs", \.switchGap)
            field("Extra monthly saving", \.extraSave, currency: true)
            field("Job loss probability (%)", \.jobRisk)
          }
        }
        Section("Household") {
          Toggle("Compare household net worth", isOn: $household)
          DisclosureGroup("Marriage & children") {
            field("Marriage age (0 for none)", \.marriage)
            field("Partner salary (% of yours)", \.spouseRatio)
            field("Household monthly housing", \.houseRent, currency: true)
            field("Wedding cost", \.wedding, currency: true)
            field("First child at age", \.firstChild)
            field("Second child at age", \.secondChild)
            field("Monthly cost per child under 5", \.youngCost, currency: true)
            field("Monthly cost per child 5–17", \.olderCost, currency: true)
            field("Partner monthly spending", \.spouseOther, currency: true)
            field("Partner contribution (%)", \.spouseContribution)
            field("Partner match (%)", \.spouseMatch)
            field("Partner job loss probability (%)", \.spouseRisk)
            Toggle("Partner backdoor Roth", isOn: $draft.scenario.plan.spouseBackdoor)
            Toggle("Partner uses Gold", isOn: $draft.scenario.plan.spouseGold)
          }
        }
        Section("Investment assumptions") {
          field("Expected annual return (%)", \.roi)
          field("Optimistic annual return (%)", \.optimistic)
          field("Annual volatility (%)", \.volatility)
          field("Inflation (%)", \.inflation)
          DisclosureGroup("Taxes & contributions") {
            field("State tax (%)", \.stateTax)
            field("Workplace contribution (%)", \.contribution)
            field("Full employer match (%)", \.matchFull)
            field("Half employer match (%)", \.matchHalf)
            field("Workplace contribution limit", \.kLimit, currency: true)
            field("IRA limit", \.iraLimit, currency: true)
            field("Limit growth (%)", \.limitGrowth)
            field("Cash return (%)", \.cashReturn)
            field("Tax drag (%)", \.taxDrag)
            field("Emergency fund months", \.emergencyMonths)
            field("Monthly health cost", \.health, currency: true)
            field("Annual Gold fee", \.goldFee, currency: true)
            field("Gold match (%)", \.goldMatch)
            field("Other MAGI", \.otherMagi, currency: true)
            field("Single Roth phase-out starts", \.singleLower, currency: true)
            field("Single Roth phase-out ends", \.singleUpper, currency: true)
            field("Joint Roth phase-out starts", \.jointLower, currency: true)
            field("Joint Roth phase-out ends", \.jointUpper, currency: true)
            Toggle("Backdoor Roth", isOn: $draft.scenario.plan.backdoor)
          }
        }
        retirementSection
      }
      .trajectorySurface()
      .safeAreaInset(edge: .bottom) {
        LabeledContent("10-year delta vs. saved baseline") {
          if let delta {
            Text(delta, format: dollars.sign(strategy: .always()))
              .font(.caption.weight(.medium)).monospacedDigit()
              .padding(.horizontal, 8).padding(.vertical, 4)
              .foregroundStyle(delta < 0 ? Color.negative : Color.positive)
              .background(Color(delta < 0 ? "DeltaNegativeBg" : "DeltaPositiveBg"), in: Capsule())
          } else { ProgressView() }
        }.padding(16).background(.regularMaterial)
      }
      .navigationTitle(draft.id)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) { Button("Save") { save(draft.scenario); dismiss() } }
        ToolbarItemGroup(placement: .keyboard) {
          if let key = adjustmentKey {
            Button("−$100") { draft.scenario.plan[keyPath: key] -= 100 }
            Button("+$100") { draft.scenario.plan[keyPath: key] += 100 }
          }
          Spacer()
          Button("Done") { focused = nil }
        }
      }
    }
    .task(id: impact) {
      let input = impact
      let old = baseline.forecastPlan
      let fixed = firstBaseline
      do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
      let output = await Task.detached(priority: .userInitiated) {
        let base = fixed.isEmpty ? Forecast.simulate(old, includeLifeEvents: true) : fixed
        let improved = Forecast.simulate(input.plan, career: input.career, includeLifeEvents: true)
        return (base, (improved.last?.series(household: input.household, real: false)[2] ?? 0)
                - (base.last?.series(household: input.household, real: false)[2] ?? 0))
      }.value
      guard !Task.isCancelled else { return }
      firstBaseline = output.0
      delta = output.1
    }
  }

  private var retirementSection: some View {
    Section("Retirement & major expenses") {
      DisclosureGroup("Retirement plan") {
        Stepper(value: retirement(\.retireAge, default: 65), in: 18...120) {
          Text("Retire at age \(retirement(\.retireAge, default: 65).wrappedValue)").monospacedDigit()
        }
        Stepper(value: retirement(\.throughAge, default: 95), in: 18...120) {
          Text("Project through age \(retirement(\.throughAge, default: 95).wrappedValue)").monospacedDigit()
        }
        AmountField(title: "Monthly spending", value: retirement(\.monthlySpend, default: 0))
        AmountField(title: "Monthly saving", value: retirement(\.monthlySave, default: defaultRetirementSaving))
        AmountField(title: "Starting assets override", value: retirement(\.startingAssets, default: draft.scenario.plan.assets))
        AmountField(title: "Monthly retirement income", value: Binding(get: { draft.scenario.plan.retirement?.monthlyIncome ?? 0 }, set: { value in
          var settings = draft.scenario.plan.retirement ?? RetirementSettings()
          settings.monthlyIncome = value
          draft.scenario.plan.retirement = settings
        }))
        Stepper(value: retirement(\.incomeAge, default: draft.scenario.plan.retirement?.retireAge ?? 65), in: 18...120) {
          Text("Retirement income starts at age \(draft.scenario.plan.retirement?.incomeAge ?? draft.scenario.plan.retirement?.retireAge ?? 65)").monospacedDigit()
        }
        AmountField(title: "Return before retiring (%)", value: retirement(\.beforeReturn, default: draft.scenario.plan.roi), currency: false)
        AmountField(title: "Volatility before retiring (%)", value: retirement(\.beforeVolatility, default: draft.scenario.plan.volatility), currency: false)
        AmountField(title: "Return after retiring (%)", value: retirement(\.afterReturn, default: draft.scenario.plan.retirement?.beforeReturn ?? draft.scenario.plan.roi), currency: false)
        AmountField(title: "Volatility after retiring (%)", value: retirement(\.afterVolatility, default: draft.scenario.plan.retirement?.beforeVolatility ?? draft.scenario.plan.volatility), currency: false)
        AmountField(title: "Retirement inflation (%)", value: retirement(\.inflation, default: draft.scenario.plan.inflation), currency: false)
      }
      ForEach(retirementYears) { $expense in
        DisclosureGroup(expense.name.isEmpty ? "Major expense" : expense.name) {
          TextField("Name", text: $expense.name)
          AmountField(title: "Annual cost", value: $expense.cost)
          Stepper("From age \(expense.startAge)", value: $expense.startAge, in: 18...120)
            .onChange(of: expense.startAge) { _, age in expense.endAge = max(age, expense.endAge) }
          Stepper("Through age \(expense.endAge)", value: $expense.endAge, in: expense.startAge...120)
          Button("Delete expense", role: .destructive) { retirementYears.wrappedValue.removeAll { $0.id == expense.id } }
        }
      }
      Button("Add major expense") {
        let age = Int(draft.scenario.plan.startAge) + 2
        retirementYears.wrappedValue.append(MajorExpense(name: "", cost: 0, startAge: age, endAge: age))
      }.disabled(retirementYears.wrappedValue.count >= 40)
    }
  }

  private var defaultRetirementSaving: Double {
    let budget = Forecast.budget(draft.scenario.forecastPlan)
    return max(0, budget.net - budget.spend) + (budget.contribution + budget.employerMatch) / 12
  }
}
