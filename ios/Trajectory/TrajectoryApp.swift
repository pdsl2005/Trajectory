import SwiftUI
import TrajectoryCore

extension Color {
  static let brand = Color("BrandPrimary")
  static let canvas = Color("SurfaceCanvas")
  static let elevated = Color("SurfaceElevated")
  static let negative = Color("DeltaNegative")
  static let positive = Color("DeltaPositive")
}

let dollars = FloatingPointFormatStyle<Double>.Currency(code: "USD").precision(.fractionLength(0...2))

struct Figure: View {
  var label: String
  var amount: Double
  var body: some View {
    LabeledContent(label) {
      Text(amount, format: dollars).monospacedDigit().multilineTextAlignment(.trailing)
    }
  }
}

struct AmountField: View {
  let title: String
  @Binding var value: Double
  var currency = true
  var body: some View {
    LabeledContent(title) {
      if currency {
        TextField(title, value: $value, format: dollars)
          .keyboardType(.decimalPad).multilineTextAlignment(.trailing).monospacedDigit()
      } else {
        TextField(title, value: $value, format: .number)
          .keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).monospacedDigit()
      }
    }
  }
}

extension View {
  func trajectorySurface() -> some View {
    scrollContentBackground(.hidden).background(Color.canvas)
  }
}

@main
struct TrajectoryApp: App {
  @StateObject private var store = Store()
  @StateObject private var imports = CardImports()
  @Environment(\.scenePhase) private var scene

  var body: some Scene {
    WindowGroup {
      TabView {
        NavigationStack { ForecastView() }
          .tabItem { Label("Trajectory", systemImage: "chart.xyaxis.line") }
        NavigationStack { BudgetView() }
          .tabItem { Label("Budget", systemImage: "wallet.bifold") }
        NavigationStack { ScenariosView() }
          .tabItem { Label("Scenarios", systemImage: "arrow.triangle.branch") }
        NavigationStack { AccountsView() }
          .tabItem { Label("Accounts & Data", systemImage: "tray.full") }
      }
      .environmentObject(store)
      .environmentObject(imports)
      .tint(.brand)
      .task {
        store.generate()
        await imports.refresh(store)
      }
      .onChange(of: scene) { _, phase in
        if phase == .active {
          store.generate()
          Task { await imports.refresh(store) }
        }
      }
      .alert("Trajectory", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
        Button("OK") { store.error = nil }
      } message: { Text(store.error ?? "") }
    }
  }
}
