import AuthenticationServices
import Foundation
import Security
import SwiftUI
import TrajectoryCore
import UIKit
#if canImport(LinkKit)
import LinkKit
#endif

struct CardConnection: Decodable, Identifiable {
  let id: String
  let name: String
}

private struct CardAPI {
  struct Token: Decodable { let token: String }
  struct Nonce: Codable { let nonce: String }
  struct Apple: Encodable { let identity_token: String; let nonce: String }
  struct Link: Decodable { let link_token: String }
  struct Exchange: Encodable { let public_token: String; let name: String }
  struct Cursor: Encodable { let cursor: String? }
  struct Changes: Decodable { let cursor: String; let changes: [Charge]; let removed: [String] }
  struct Failure: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
  }

  let base: URL
  let token: String?

  func request<Result: Decodable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Result {
    let data = try await send(path, method: method, body: body)
    return try JSONDecoder().decode(Result.self, from: data)
  }

  @discardableResult
  func send(_ path: String, method: String, body: Data? = nil) async throws -> Data {
    var request = URLRequest(url: base.appending(path: path), timeoutInterval: 120)
    request.httpMethod = method
    request.httpBody = body
    if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    guard (200..<300).contains(response.statusCode) else {
      struct Detail: Decodable { let detail: String }
      let detail = try? JSONDecoder().decode(Detail.self, from: data).detail
      throw Failure(status: response.statusCode, message: detail ?? "The card server could not complete the request.")
    }
    return data
  }
}

@MainActor
final class CardImports: NSObject, ObservableObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
  @Published private var token: String?
  @Published private(set) var connections: [CardConnection] = []
  @Published private(set) var syncing = false
  @Published private(set) var authenticating = false
  @Published var presentingLink = false
  #if canImport(LinkKit)
  private var linkSession: PlaidLinkSession?
  var linkSheet: some View { linkSession?.sheet() }
  #endif

  private var authorization: ASAuthorizationController?
  private var onAuthorization: ((Result<ASAuthorizationAppleIDCredential, Error>) -> Void)?
  private let base: URL?
  var configured: Bool { base != nil }
  var signedIn: Bool { token != nil }
  private var key: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: "Trajectory Plaid Session",
     kSecAttrAccount as String: base?.absoluteString ?? ""]
  }

  override init() {
    let raw = Bundle.main.object(forInfoDictionaryKey: "TrajectoryAPIURL") as? String ?? ""
    if let url = URL(string: raw), url.scheme == "https", url.host != nil { base = url }
    else { base = nil }
    super.init()
    if base != nil {
      var query = key
      query[kSecReturnData as String] = true
      var result: CFTypeRef?
      if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
        token = String(data: data, encoding: .utf8)
      }
    }
  }

  private func setToken(_ value: String?) throws {
    if let value {
      var item = key
      item[kSecValueData as String] = Data(value.utf8)
      item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      var status = SecItemAdd(item as CFDictionary, nil)
      if status == errSecDuplicateItem {
        status = SecItemUpdate(key as CFDictionary, [kSecValueData as String: Data(value.utf8)] as CFDictionary)
      }
      guard status == errSecSuccess else { throw CocoaError(.fileWriteNoPermission) }
    } else {
      let status = SecItemDelete(key as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else { throw CocoaError(.fileWriteNoPermission) }
      connections = []
    }
    token = value
  }

  func signIn(_ store: Store) async {
    guard let base, !authenticating else { return }
    authenticating = true
    defer { authenticating = false }
    do {
      let api = CardAPI(base: base, token: nil)
      let challenge: CardAPI.Nonce = try await api.request("auth/nonce", method: "POST")
      let credential = try await appleCredential(nonce: challenge.nonce)
      guard let data = credential.identityToken, let identity = String(data: data, encoding: .utf8) else {
        throw CardAPI.Failure(status: 401, message: "Apple did not return an identity token.")
      }
      let payload = CardAPI.Apple(identity_token: identity, nonce: challenge.nonce)
      let session: CardAPI.Token = try await api.request("auth/apple", method: "POST", body: JSONEncoder().encode(payload))
      try setToken(session.token)
      await refresh(store)
    } catch let error as ASAuthorizationError where error.code == .canceled {
      return
    } catch { report(error, store: store) }
  }

  func signOut(_ store: Store) async {
    guard let base, let token else { return }
    do {
      do { try await CardAPI(base: base, token: token).send("auth/session", method: "DELETE") }
      catch let error as CardAPI.Failure where error.status == 401 { }
      try setToken(nil)
    } catch { report(error, store: store) }
  }

  private func appleCredential(nonce: String) async throws -> ASAuthorizationAppleIDCredential {
    try await withCheckedThrowingContinuation { continuation in
      onAuthorization = { continuation.resume(with: $0) }
      let request = ASAuthorizationAppleIDProvider().createRequest()
      request.nonce = nonce
      let controller = ASAuthorizationController(authorizationRequests: [request])
      controller.delegate = self
      controller.presentationContextProvider = self
      authorization = controller
      controller.performRequests()
    }
  }

  func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
    UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
  }

  func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization result: ASAuthorization) {
    if let credential = result.credential as? ASAuthorizationAppleIDCredential {
      onAuthorization?(.success(credential))
    } else {
      onAuthorization?(.failure(ASAuthorizationError(.failed)))
    }
    onAuthorization = nil
    authorization = nil
  }

  func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
    onAuthorization?(.failure(error))
    onAuthorization = nil
    authorization = nil
  }

  func refresh(_ store: Store) async {
    guard let base, let token, !syncing else { return }
    syncing = true
    defer { syncing = false }
    let api = CardAPI(base: base, token: token)
    do {
      let list: [CardConnection] = try await api.request("connections")
      guard self.token == token else { return }
      connections = list
      var failures: [String] = []
      for connection in list {
        guard self.token == token, connections.contains(where: { $0.id == connection.id }) else { continue }
        let cursor = store.profile.cards[connection.id]?.cursor
        do {
          let batch: CardAPI.Changes = try await api.request("connections/\(connection.id)/sync", method: "POST",
                                                            body: JSONEncoder().encode(CardAPI.Cursor(cursor: cursor)))
          guard self.token == token, connections.contains(where: { $0.id == connection.id }) else { continue }
          try store.update { $0.apply(connection: connection.id, from: cursor, to: batch.cursor, changes: batch.changes, removed: batch.removed) }
        } catch let error as CardAPI.Failure where error.status == 401 { throw error }
        catch { failures.append("\(connection.name): \(error.localizedDescription)") }
      }
      if !failures.isEmpty { store.error = failures.joined(separator: "\n") }
    } catch where self.token == token { report(error, store: store) }
    catch { }
  }

  func link(in store: Store, connection: CardConnection? = nil) async {
    #if canImport(LinkKit)
    guard let base, let token, !presentingLink else { return }
    let api = CardAPI(base: base, token: token)
    do {
      let path = connection.map { "connections/\($0.id)/reconnect" } ?? "connections/link-token"
      let link: CardAPI.Link = try await api.request(path, method: "POST")
      guard self.token == token else { return }
      let configuration = LinkTokenConfiguration(token: link.link_token, onSuccess: { [weak self] result in
        let publicToken = result.publicToken
        let name = result.metadata.institution.name
        Task { @MainActor in
          guard let self else { return }
          self.presentingLink = false
          guard self.token == token else { return }
          do {
            if connection == nil {
              let payload = CardAPI.Exchange(public_token: publicToken, name: name)
              let _: CardConnection = try await api.request("connections/exchange", method: "POST", body: JSONEncoder().encode(payload))
            }
            while self.syncing { try await Task.sleep(for: .milliseconds(200)) }
            await self.refresh(store)
          } catch { self.report(error, store: store) }
        }
      }, onExit: { [weak self] exit in
        let failed = exit.error != nil
        Task { @MainActor in
          self?.presentingLink = false
          if failed { store.error = "Plaid Link could not complete the connection." }
        }
      }, onEvent: nil, onLoad: nil)
      linkSession = try Plaid.createPlaidLinkSession(configuration: configuration)
      presentingLink = true
    } catch { report(error, store: store) }
    #else
    store.error = "This build does not include Plaid Link."
    #endif
  }

  func disconnect(_ connection: CardConnection, store: Store) async {
    guard let base, let token else { return }
    do {
      try await CardAPI(base: base, token: token).send("connections/\(connection.id)", method: "DELETE")
      connections.removeAll { $0.id == connection.id }
    } catch { report(error, store: store) }
  }

  private func report(_ error: Error, store: Store) {
    if let failure = error as? CardAPI.Failure, failure.status == 401 { try? setToken(nil) }
    store.error = error.localizedDescription
  }
}
