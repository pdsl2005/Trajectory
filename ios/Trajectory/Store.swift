import Foundation
import SwiftUI
import TrajectoryCore

@MainActor
final class Store: ObservableObject {
  @Published private(set) var profile = Profile()
  @Published var error: String?
  private let url: URL
  private var readable = true

  init() {
    url = URL.applicationSupportDirectory.appending(path: "Trajectory/profile.json")
    do {
      let data = try Data(contentsOf: url)
      try profile.importBackup(data)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      // The profile is created on the first edit.
    } catch {
      readable = false
      self.error = "The local profile could not be opened. Restore a backup to continue."
    }
  }

  func update(_ change: (inout Profile) throws -> Void, replacing: Bool = false) throws {
    guard readable || replacing else { throw ImportError.invalidBackup }
    var next = profile
    try change(&next)
    guard next != profile || !readable else { return }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try next.backup().write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    profile = next
    readable = true
  }

  func edit(_ change: (inout Profile) -> Void) {
    do { try update(change) }
    catch { self.error = error.localizedDescription }
  }

  var scenario: Scenario { profile.scenarios[profile.active] ?? Scenario() }

  func scenarioField<Value>(_ key: WritableKeyPath<Scenario, Value>) -> Binding<Value> {
    Binding(get: { self.scenario[keyPath: key] }, set: { value in
      self.edit { $0.scenarios[$0.active]?[keyPath: key] = value }
    })
  }

  func generate() { edit { $0.generate(through: BudgetDate.day(Date())) } }
}
