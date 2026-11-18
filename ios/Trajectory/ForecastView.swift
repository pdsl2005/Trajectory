import Charts
import SwiftUI
import TrajectoryCore

struct ForecastView: View {
  @EnvironmentObject private var store: Store
  @AppStorage("householdForecast") private var household = false
  @State private var real = false
  @State private var overlay = ""
  @State private var career = Career.base
  @State private var optimistic = false
  @State private var selected: Int?
  @State private var activeYears: [ForecastYear] = []
  @State private var overlayYears: [ForecastYear] = []
  @State private var retirement: RetirementProjection?

  private struct Inputs: Equatable {
    let plan: Plan
    let comparison: Plan?
    let career: Career
    let optimistic: Bool
  }

  private var inputs: Inputs {
    Inputs(plan: store.scenario.forecastPlan, comparison: store.profile.scenarios[overlay]?.forecastPlan,
           career: career, optimistic: optimistic)
  }
  private var selectedYear: ForecastYear? {
    guard let last = activeYears.last else { return nil }
    let year = selected ?? last.year
    return activeYears.min { abs($0.year - year) < abs($1.year - year) }
  }
  private func series(_ row: ForecastYear) -> [Double] { row.series(household: household, real: real) }

  var body: some View {
    Form {
      Section {
        Picker("Scenario", selection: Binding(get: { store.profile.active }, set: { name in store.edit { $0.active = name } })) {
          ForEach(store.profile.scenarios.keys.sorted(), id: \.self) { Text($0).tag($0) }
        }
        Picker("Compare with", selection: $overlay) {
          Text("None").tag("")
          ForEach(store.profile.scenarios.keys.sorted(), id: \.self) { Text($0).tag($0) }
        }
        DisclosureGroup("Projection settings") {
          Toggle("Household", isOn: $household)
          Toggle("Inflation-adjusted dollars", isOn: $real)
          Toggle("Optimistic deterministic return", isOn: $optimistic)
          Picker("Career", selection: $career) {
            Text("Current path").tag(Career.base)
            Text("Job change").tag(Career.change)
            Text("Extra saving").tag(Career.save)
          }
        }
      }
      Section("Projected net worth") {
        if let headline = selectedYear {
          VStack(alignment: .leading, spacing: 8) {
            Text(series(headline)[2], format: dollars)
              .font(.largeTitle.bold()).monospacedDigit().contentTransition(.numericText())
            Text("Year \(headline.year.formatted(.number.grouping(.never))) · Age \(headline.age)")
              .foregroundStyle(.secondary).monospacedDigit()
          }
          projectionChart
            .padding(12)
            .background(Color.elevated, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color("BorderHairline"), lineWidth: 0.5) }
          ShareLink(item: csvFile, preview: SharePreview("Trajectory forecast")) { Label("Export forecast CSV", systemImage: "square.and.arrow.up") }
        } else { ProgressView("Calculating forecast") }
      }
      Section("Milestones") {
        NavigationLink("Compare career paths") {
          CareerReport(plan: store.scenario.forecastPlan, household: household, real: real)
        }
        if let final = activeYears.last {
          Figure(label: "Year 10 downside (P10)", amount: series(final)[0])
          Figure(label: "Year 10 upside (P90)", amount: series(final)[4])
        }
        if let retirement {
          NavigationLink("Retirement & major expenses") {
            RetirementReport(result: retirement, expenses: store.scenario.plan.retirement?.expenses ?? [])
          }
        }
      }
    }
    .trajectorySurface()
    .navigationTitle("Trajectory")
    .task(id: inputs) {
      let input = inputs
      let output = await Task.detached(priority: .userInitiated) {
        let main = Forecast.simulate(input.plan, count: input.optimistic ? 1 : 1500, career: input.career,
                                     deterministic: input.optimistic, returnOverride: input.optimistic ? input.plan.optimistic : nil, includeLifeEvents: true)
        let comparison = input.comparison.map { Forecast.simulate($0, includeLifeEvents: true) } ?? []
        return (main, comparison, Retirement.project(input.plan))
      }.value
      guard !Task.isCancelled else { return }
      activeYears = output.0
      overlayYears = output.1
      retirement = output.2
      selected = nil
    }
    .sensoryFeedback(.selection, trigger: selected)
    .animation(.snappy(duration: 0.25), value: store.profile.active)
  }

  private var csvFile: ExportFile {
    ExportFile(text: Forecast.csv(activeYears, household: household, real: real), name: "trajectory-forecast.csv")
  }

  private func axisAmount(_ amount: Double) -> String {
    if #available(iOS 18, *) { return amount.formatted(.currency(code: "USD").notation(.compactName)) }
    for (scale, unit) in [(1_000_000_000.0, "B"), (1_000_000, "M"), (1_000, "K")] where abs(amount) >= scale {
      return (amount / scale).formatted(dollars.precision(.fractionLength(0...1))) + unit
    }
    return amount.formatted(dollars.precision(.fractionLength(0)))
  }

  private var yearDomain: ClosedRange<Int> {
    let years = activeYears + overlayYears
    return (years.map(\.year).min() ?? 2027)...(years.map(\.year).max() ?? 2037)
  }

  private var projectionChart: some View {
    Chart {
      ForEach(activeYears) { row in
        AreaMark(x: .value("Year", row.year), yStart: .value("P10", series(row)[0]), yEnd: .value("P90", series(row)[4]))
          .foregroundStyle(Color.brand.opacity(0.15))
        LineMark(x: .value("Year", row.year), y: .value("Median", series(row)[2]), series: .value("Scenario", "Active"))
          .foregroundStyle(Color.brand).lineStyle(StrokeStyle(lineWidth: 2.5))
      }
      ForEach(overlayYears) { row in
        LineMark(x: .value("Year", row.year), y: .value("Median", series(row)[2]), series: .value("Scenario", "Comparison"))
          .foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
      }
      if let selected {
        RuleMark(x: .value("Selected year", selected)).foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }
    }
    .chartXAxis {
      AxisMarks(values: .automatic(desiredCount: 4)) { value in
        AxisTick()
        AxisValueLabel { if let year = value.as(Int.self) { Text(String(year)).monospacedDigit() } }
      }
    }
    .chartYAxis {
      AxisMarks(values: .automatic(desiredCount: 4)) { value in
        AxisGridLine()
        AxisValueLabel {
          if let amount = value.as(Double.self) { Text(axisAmount(amount)).monospacedDigit() }
        }
      }
    }
    .chartXScale(domain: yearDomain)
    .chartXSelection(value: $selected)
    .frame(minHeight: 210)
    .accessibilityLabel("Net worth by year")
  }
}

private struct RetirementReport: View {
  let result: RetirementProjection
  let expenses: [MajorExpense]
  var body: some View {
    Form {
      Section("Retirement projection · today's dollars") {
        if result.hasRetirement {
          LabeledContent("Runs without a shortfall") { Text(result.coverage, format: .percent).monospacedDigit() }
          LabeledContent("Without major expenses") { Text(result.baselineCoverage, format: .percent).monospacedDigit() }
        }
        if let balance = result.retirementStart.dropFirst(2).first {
          Figure(label: "Median at retirement", amount: balance)
        }
        Chart(result.periods) { row in
          AreaMark(x: .value("Age", row.age), yStart: .value("P10", row.balance[0]), yEnd: .value("P90", row.balance[4]))
            .foregroundStyle(Color.brand.opacity(0.15))
          LineMark(x: .value("Age", row.age), y: .value("Median", row.balance[2]))
            .foregroundStyle(Color.brand)
        }.frame(minHeight: 200)
        ShareLink(item: ExportFile(text: result.csv, name: "trajectory-retirement.csv"), preview: SharePreview("Trajectory retirement forecast")) {
          Label("Export retirement CSV", systemImage: "square.and.arrow.up")
        }
      }
      Section("Major expense funding") {
        ForEach(Array(zip(expenses, result.expenseFunding)), id: \.0.id) { expense, funding in
          LabeledContent(expense.name) {
            if let funding { Text(funding, format: .percent).monospacedDigit() }
            else { Text("Outside projection") }
          }
        }
      }
    }.trajectorySurface().navigationTitle("Retirement")
  }
}

private struct CareerReport: View {
  let plan: Plan
  let household: Bool
  let real: Bool
  @State private var results: [Career: [ForecastYear]] = [:]

  private func label(_ career: Career) -> String {
    switch career {
    case .base: "Current path"
    case .change: "Job change"
    case .save: "Extra saving"
    }
  }

  private func values(_ row: ForecastYear) -> [Double] { row.series(household: household, real: real) }

  var body: some View {
    Form {
      if let base = results[.base]?.last {
        Section("Median net worth") {
          Chart {
            ForEach(Career.allCases) { career in
              ForEach(results[career] ?? []) { row in
                LineMark(x: .value("Year", row.year), y: .value("Median", values(row)[2]))
                  .foregroundStyle(by: .value("Career", label(career)))
                  .lineStyle(by: .value("Career", label(career)))
              }
            }
          }
          .chartXScale(domain: (base.year - 10)...base.year)
          .chartForegroundStyleScale([label(.base): Color.brand, label(.change): Color.positive, label(.save): Color.secondary])
          .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
              AxisTick()
              AxisValueLabel { if let year = value.as(Int.self) { Text(String(year)).monospacedDigit() } }
            }
          }
          .frame(minHeight: 220)
          ShareLink(item: export, preview: SharePreview("Trajectory career comparisons")) {
            Label("Export career CSV", systemImage: "square.and.arrow.up")
          }
        }
        Section("Year 10 outcomes") {
          ForEach(Career.allCases) { career in
            if let row = results[career]?.last {
              let outcome = values(row)
              DisclosureGroup {
                Figure(label: "Downside (P10)", amount: outcome[0])
                Figure(label: "Upside (P90)", amount: outcome[4])
                if career != .base {
                  Figure(label: "Median vs. current path", amount: outcome[2] - values(base)[2])
                }
              } label: {
                Figure(label: label(career), amount: outcome[2])
              }
            }
          }
        }
      } else {
        ProgressView("Comparing career paths")
      }
    }
    .trajectorySurface()
    .navigationTitle("Career comparisons")
    .task {
      let plan = plan
      let output = await Task.detached(priority: .userInitiated) {
        Dictionary(uniqueKeysWithValues: Career.allCases.map { career in
          (career, Forecast.simulate(plan, career: career, includeLifeEvents: true))
        })
      }.value
      if !Task.isCancelled { results = output }
    }
  }

  private var export: ExportFile {
    let careers = Career.allCases
    let header = ["Year", "Age"] + careers.map { label($0) + " median" }
    let rows = (results[.base] ?? []).enumerated().map { index, row in
      ([String(row.year), String(row.age)] + careers.map { career in
        results[career].map { String(values($0[index])[2]) } ?? ""
      }).joined(separator: ",")
    }
    let text = ([header.joined(separator: ",")] + rows).joined(separator: "\n")
    return ExportFile(text: text, name: "trajectory-career.csv")
  }
}
