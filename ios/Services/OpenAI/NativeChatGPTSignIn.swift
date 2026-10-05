#if os(iOS)
import Foundation
import Network
import AuthenticationServices
import UIKit

// This listener is only for OAuth. It binds exclusively to IPv4 loopback and expires
// with the sign-in attempt. It never serves journal data or listens on LAN/Tailscale.
@MainActor
final class OAuthLoopback {
    private var listener:NWListener?
    private var ready:CheckedContinuation<URL,Error>?
    private var connections:[NWConnection] = []
    var callback:((URL) -> Void)?
    var failure:((Error) -> Void)?
    func start() async throws -> URL {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:.any)
        let listener = try NWListener(using:parameters); self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    if let port = listener.port {
                        self.ready?.resume(returning:URL(string:"http://127.0.0.1:\(port.rawValue)/auth/callback")!); self.ready = nil
                    }
                case .failed(let error):
                    self.ready?.resume(throwing:error); self.ready = nil; self.failure?(error)
                default: break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.receive(connection) }
        }
        return try await withCheckedThrowingContinuation { continuation in ready = continuation; listener.start(queue:.main) }
    }
    private func receive(_ connection:NWConnection) {
        guard connections.count < 10 else { connection.cancel(); return }
        connections.append(connection); connection.start(queue:.main)
        let deadline = Task { @MainActor in
            try? await Task.sleep(for:.seconds(10)); if !Task.isCancelled { connection.cancel() }
        }
        read(connection,buffer:Data(),deadline:deadline)
    }
    private func read(_ connection:NWConnection,buffer:Data,deadline:Task<Void,Never>) {
        connection.receive(minimumIncompleteLength:1,maximumLength:8192) { [weak self] data,_,complete,error in
            Task { @MainActor in
                guard let self else { deadline.cancel(); connection.cancel(); return }
                var buffer = buffer; buffer.append(data ?? Data())
                if error != nil || buffer.count > 16384 { deadline.cancel(); connection.cancel(); self.connections.removeAll { $0 === connection }; return }
                guard let text = String(data:buffer,encoding:.utf8), text.contains("\r\n\r\n") else {
                    if complete { deadline.cancel(); connection.cancel(); self.connections.removeAll { $0 === connection } } else { self.read(connection,buffer:buffer,deadline:deadline) }
                    return
                }
                let parts = text.components(separatedBy:"\r\n")[0].split(separator:" ").map(String.init)
                let port = self.listener?.port?.rawValue ?? 0
                let url = parts.count == 3 && parts[0] == "GET" ? URL(string:"http://127.0.0.1:\(port)"+parts[1]) : nil
                let isCallback = url?.path == "/auth/callback"
                let body = isCallback ? "Return to Weight Coach to finish connecting." : "Not found."
                let response = "HTTP/1.1 \(isCallback ? "200 OK" : "404 Not Found")\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'none'\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
                connection.send(content:Data(response.utf8),completion:.contentProcessed { _ in
                    Task { @MainActor in
                        deadline.cancel(); connection.cancel(); self.connections.removeAll { $0 === connection }
                        if isCallback, let url { self.callback?(url) }
                    }
                })
            }
        }
    }
    func stop() {
        ready?.resume(throwing:CancellationError()); ready = nil
        listener?.stateUpdateHandler = nil; listener?.newConnectionHandler = nil
        listener?.cancel(); listener = nil
        connections.forEach { $0.cancel() }; connections.removeAll(); callback = nil; failure = nil
    }
}

@MainActor @Observable
public final class ChatGPTConnection: NSObject, ASWebAuthenticationPresentationContextProviding {
    public private(set) var accountLabel:String?
    public private(set) var models:[AvailableModel] = []
    public private(set) var isConnecting = false
    public var selectedModel:String {
        didSet { UserDefaults.standard.set(selectedModel,forKey:"chatgpt.model") }
    }
    public let session:ChatGPTSession
    private var webSession:ASWebAuthenticationSession?
    private var loopback:OAuthLoopback?
    private var pending:CheckedContinuation<URL,Error>?
    private var signInTask:Task<Void,Never>?
    private var timeout:Task<Void,Never>?
    public var error:String?
    public override init() {
        session = ChatGPTSession(credentials:KeychainCredentials(service:(Bundle.main.bundleIdentifier ?? "personal.WeightCoach")+".ChatGPT"))
        selectedModel = UserDefaults.standard.string(forKey:"chatgpt.model") ?? ""
        super.init()
    }
    public var recognizer:OpenAIMealRecognizer { OpenAIMealRecognizer(tokens:session) }
    public func load() async {
        do {
            accountLabel = try await session.accountLabel()
            if accountLabel != nil { try await refreshModels() }
        } catch { self.error = error.localizedDescription }
    }
    public func refreshModels() async throws {
        models = try await recognizer.models()
        if !models.contains(where: { $0.slug == selectedModel }) { selectedModel = models.first?.slug ?? "" }
    }
    public func connect() {
        guard !isConnecting else { return }
        isConnecting = true; error = nil
        signInTask = Task { @MainActor in
            defer { cleanup(); isConnecting = false; signInTask = nil }
            do {
                let listener = OAuthLoopback(); loopback = listener
                let redirect = try await listener.start()
                try Task.checkCancellation()
                let (attempt,hint) = try await session.attempt(redirect:redirect)
                let callback = try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<URL,Error>) in
                    pending = continuation
                    listener.callback = { [weak owner = self] url in owner?.finish(.success(url)) }
                    listener.failure = { [weak owner = self] error in owner?.finish(.failure(error)) }
                    // The documented HTTP loopback is handled by our listener, not
                    // substituted with an unregistered custom-scheme redirect.
                    let web = ASWebAuthenticationSession(url:attempt.authorizationURL(idTokenHint:hint),callbackURLScheme:nil) { [weak owner = self] _,error in
                        Task { @MainActor in owner?.finish(.failure(error ?? CancellationError())) }
                    }
                    web.presentationContextProvider = self; webSession = web
                    timeout = Task { @MainActor [weak owner = self] in
                        try? await Task.sleep(for:.seconds(180))
                        if !Task.isCancelled { owner?.finish(.failure(AIError.message("Sign-in timed out. Please start again."))) }
                    }
                    if !web.start() { finish(.failure(AIError.message("The system could not open ChatGPT sign-in."))) }
                }
                webSession?.cancel(); webSession = nil; listener.stop()
                try Task.checkCancellation()
                try await session.complete(attempt:attempt,callback:callback)
                accountLabel = try await session.accountLabel()
                try await refreshModels()
            } catch is CancellationError { }
            catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin { }
            catch { self.error = error.localizedDescription }
        }
    }
    public func cancel() { signInTask?.cancel(); finish(.failure(CancellationError())); cleanup() }
    public func disconnect() async {
        cancel()
        do { try await session.disconnect(); accountLabel = nil; models = []; selectedModel = "" }
        catch { self.error = error.localizedDescription }
    }
    private func finish(_ result:Result<URL,Error>) {
        let continuation = pending; pending = nil; continuation?.resume(with:result)
    }
    private func cleanup() { timeout?.cancel(); timeout = nil; webSession?.cancel(); webSession = nil; loopback?.stop(); loopback = nil }
    public func presentationAnchor(for session:ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where:\.isKeyWindow) ?? ASPresentationAnchor()
    }
}
#endif
