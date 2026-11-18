import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers
import TrajectoryCore

struct ExportFile: Transferable {
  let data: Data
  let name: String

  init(data: Data, name: String) {
    self.data = data
    self.name = name
  }

  init(text: String, name: String) {
    self.init(data: Data(text.utf8), name: name)
  }

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(exportedContentType: .data) { file in
      let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
      let url = directory.appending(path: file.name)
      try file.data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      return SentTransferredFile(url)
    }
  }
}

struct AccountsView: View {
  @EnvironmentObject private var store: Store
  @EnvironmentObject private var imports: CardImports
  @AppStorage("householdForecast") private var household = false
  @State private var importing = false
  @State private var backup: Data?
  @State private var disconnect: CardConnection?

  var body: some View {
    Form {
      Section("Opening balances · \(store.profile.active)") {
        AmountField(title: "Total starting assets", value: store.scenarioField(\.plan.assets))
        AmountField(title: "Starting liabilities", value: Binding(get: { store.scenario.plan.startingDebt ?? 0 }, set: { value in
          store.edit { $0.scenarios[$0.active]?.plan.startingDebt = max(0, value) }
        }))
        Toggle("Show partner in forecast", isOn: $household)
        if household {
          AmountField(title: "Partner starting assets", value: store.scenarioField(\.plan.spouseAssets))
        }
        DisclosureGroup("Account allocation") {
          AmountField(title: "Cash (%)", value: store.scenarioField(\.plan.cashShare), currency: false)
          AmountField(title: "Roth (%)", value: store.scenarioField(\.plan.rothShare), currency: false)
          AmountField(title: "Workplace (%)", value: store.scenarioField(\.plan.workplaceShare), currency: false)
          Text("The remaining assets are invested in brokerage.").font(.caption).foregroundStyle(.secondary)
        }
        DisclosureGroup("Forecast starting date") {
          Stepper(value: integer(\.startAge), in: 18...100) { LabeledContent("Starting age", value: String(Int(store.scenario.plan.startAge))) }
          Stepper(value: integer(\.startYear), in: 1900...2200) { LabeledContent("Starting year", value: String(Int(store.scenario.plan.startYear))) }
          Stepper(value: integer(\.startMonths, bounds: 1...12), in: 1...12) {
            LabeledContent("Months in first year", value: String(integer(\.startMonths, bounds: 1...12).wrappedValue))
          }
        }
      }
      cardSection
      Section("Local data") {
        Button("Import Trajectory JSON") { importing = true }
        if let data = try? store.profile.backup() {
          ShareLink(item: ExportFile(data: data, name: "trajectory-native.json"), preview: SharePreview("Trajectory backup")) {
            Label("Export native backup", systemImage: "square.and.arrow.up")
          }
        }
      }
    }
    .trajectorySurface()
    .refreshable { await imports.refresh(store) }
    .navigationTitle("Accounts & Data")
    #if canImport(LinkKit)
    .sheet(isPresented: $imports.presentingLink) { imports.linkSheet }
    #endif
    .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
      do {
        let url = try result.get()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        var validation = store.profile
        try validation.importBackup(data)
        backup = data
      } catch { store.error = error.localizedDescription }
    }
    .confirmationDialog("Import this backup?", isPresented: Binding(get: { backup != nil }, set: { if !$0 { backup = nil } }), titleVisibility: .visible) {
      Button("Import backup", role: .destructive) {
        guard let backup else { return }
        do {
          try store.update({ try $0.importBackup(backup) }, replacing: true)
          store.generate()
        } catch { store.error = error.localizedDescription }
        self.backup = nil
      }
    } message: {
      Text("Web backups replace saved scenarios and targets. Native backups also restore ledger history.")
    }
    .confirmationDialog("Disconnect this credit card?", isPresented: Binding(get: { disconnect != nil }, set: { if !$0 { disconnect = nil } }), titleVisibility: .visible) {
      Button("Disconnect", role: .destructive) {
        if let connection = disconnect { Task { await imports.disconnect(connection, store: store) } }
        disconnect = nil
      }
    } message: { Text("Imported activity stays in your local budget history.") }
  }

  private var cardSection: some View {
    Section("Credit cards") {
      if imports.configured {
        if imports.signedIn {
          Button("Link a credit card") { Task { await imports.link(in: store) } }
          ForEach(imports.connections) { cardRow($0) }
          Button("Sync cards") { Task { await imports.refresh(store) } }
          Button("Sign out") { Task { await imports.signOut(store) } }
        } else {
          Button {
            Task { await imports.signIn(store) }
          } label: {
            Label("Sign in with Apple", systemImage: "apple.logo")
              .frame(minHeight: 44)
          }.disabled(imports.authenticating)
        }
        if imports.syncing { ProgressView("Syncing cards") }
      } else {
        Text("Card imports require a configured Trajectory server.").foregroundStyle(.secondary)
      }
    }
  }

  private func cardRow(_ connection: CardConnection) -> some View {
    DisclosureGroup(connection.name) {
      if let last = store.profile.cards[connection.id]?.lastSync {
        LabeledContent("Last successful sync") {
          Text(last, format: .dateTime.month().day().hour().minute()).monospacedDigit()
        }
      } else {
        Text("Awaiting first sync").foregroundStyle(.secondary)
      }
      Button("Reconnect") { Task { await imports.link(in: store, connection: connection) } }
      Button("Disconnect", role: .destructive) { disconnect = connection }
    }
  }

  private func integer(_ key: WritableKeyPath<Plan, Double>, bounds: ClosedRange<Int> = 18...2200) -> Binding<Int> {
    Binding(get: { Int(min(Double(bounds.upperBound), max(Double(bounds.lowerBound), store.scenario.plan[keyPath: key]))) }, set: { value in
      store.edit { $0.scenarios[$0.active]?.plan[keyPath: key] = Double(value) }
    })
  }
}
