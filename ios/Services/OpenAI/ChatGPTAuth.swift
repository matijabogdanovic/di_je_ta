import Foundation
import Security
import CryptoKit

public enum OAuthEncoding {
    public static func base64URL(_ data:Data) -> String { data.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"") }
    public static func decode(_ string:String) -> Data? {
        let value = string.replacingOccurrences(of:"-",with:"+").replacingOccurrences(of:"_",with:"/")
        return Data(base64Encoded:value + String(repeating:"=",count:(4-value.count%4)%4))
    }
    public static func random() throws -> String {
        var bytes = [UInt8](repeating:0,count:32)
        guard SecRandomCopyBytes(kSecRandomDefault,bytes.count,&bytes) == errSecSuccess else { throw AIError.message("Unable to create a secure sign-in attempt.") }
        return base64URL(Data(bytes))
    }
    public static func form(_ values:[String:String]) -> Data {
        let allowed = CharacterSet(charactersIn:"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return Data(values.sorted { $0.key < $1.key }.map { "\($0.key.addingPercentEncoding(withAllowedCharacters:allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters:allowed)!)" }.joined(separator:"&").utf8)
    }
}
public struct OAuthAttempt: Sendable {
    public let state:String
    public let nonce:String
    public let verifier:String
    public let hostID:String
    public let clientID:String?
    public let redirect:URL
    public init(hostID:String,clientID:String?,redirect:URL) throws {
        self.hostID = hostID; self.clientID = clientID; self.redirect = redirect
        state = try OAuthEncoding.random(); nonce = try OAuthEncoding.random(); verifier = try OAuthEncoding.random()
    }
    public func authorizationURL(idTokenHint:String? = nil) -> URL {
        var url = URLComponents(string:"https://auth.openai.com/api/accounts/authorize")!
        var values = ["client_id":clientID ?? "dynamic_agent_client","ext_agent_host_id":hostID,"response_type":"code","redirect_uri":redirect.absoluteString,"scope":"openid profile email offline_access resource.invoke chatgpt.tokens.use.direct","resource":"https://api.openai.com/v1","state":state,"nonce":nonce,"code_challenge_method":"S256","code_challenge":OAuthEncoding.base64URL(Data(SHA256.hash(data:Data(verifier.utf8))))]
        if clientID == nil { values["agent_name_hint"] = "Weight Coach" }
        if let idTokenHint { values["id_token_hint"] = idTokenHint }
        url.queryItems = values.sorted { $0.key < $1.key }.map { URLQueryItem(name:$0.key,value:$0.value) }
        return url.url!
    }
    public func callback(_ url:URL) throws -> (code:String,clientID:String) {
        guard url.scheme == redirect.scheme, url.host == redirect.host, url.port == redirect.port, url.path == redirect.path,
              let items = URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems,
              Set(items.map(\.name)).count == items.count else { throw AIError.message("Invalid sign-in callback.") }
        let params = Dictionary(uniqueKeysWithValues:items.map { ($0.name,$0.value ?? "") })
        guard params["state"] == state else { throw AIError.message("Sign-in state did not match. Start again.") }
        if params["error"] != nil { throw AIError.message("ChatGPT sign-in was declined or could not complete.") }
        guard let code = params["code"], !code.isEmpty else { throw AIError.message("Sign-in returned no authorization code.") }
        let issued = params["client_id"] ?? clientID
        guard let issued, issued.hasPrefix("oaiapp_"), clientID == nil || issued == clientID else { throw AIError.message("Sign-in returned an unexpected client registration.") }
        return (code,issued)
    }
}
public struct VerifiedIdentity: Sendable {
    public let subject:String
    public let email:String?
}
public enum IDTokenValidator {
    public static func validate(_ token:String,jwks:Data,clientID:String,nonce:String?,now:Date = Date()) throws -> VerifiedIdentity {
        let parts = token.split(separator:".",omittingEmptySubsequences:false).map(String.init)
        guard parts.count == 3, let headerData = OAuthEncoding.decode(parts[0]), let claimsData = OAuthEncoding.decode(parts[1]), let signature = OAuthEncoding.decode(parts[2]),
              let header = try JSONSerialization.jsonObject(with:headerData) as? [String:Any], let claims = try JSONSerialization.jsonObject(with:claimsData) as? [String:Any],
              let kid = header["kid"] as? String, let algorithm = header["alg"] as? String,
              let keys = (try JSONSerialization.jsonObject(with:jwks) as? [String:Any])?["keys"] as? [[String:Any]],
              let key = keys.first(where: { $0["kid"] as? String == kid && ($0["use"] as? String ?? "sig") == "sig" && ($0["alg"] as? String ?? algorithm) == algorithm }) else { throw AIError.message("Could not validate ChatGPT account identity.") }
        let message = Data((parts[0]+"."+parts[1]).utf8)
        let signatureValid:Bool
        if algorithm == "RS256", key["kty"] as? String == "RSA", let n = key["n"] as? String, let e = key["e"] as? String, let modulus = OAuthEncoding.decode(n), let exponent = OAuthEncoding.decode(e) {
            let representation = der(0x30,derInteger(modulus)+derInteger(exponent))
            var error:Unmanaged<CFError>?
            guard let publicKey = SecKeyCreateWithData(representation as CFData,[kSecAttrKeyType:kSecAttrKeyTypeRSA,kSecAttrKeyClass:kSecAttrKeyClassPublic] as CFDictionary,&error) else { throw AIError.message("Invalid identity signing key.") }
            signatureValid = SecKeyVerifySignature(publicKey,.rsaSignatureMessagePKCS1v15SHA256,message as CFData,signature as CFData,&error)
        } else if algorithm == "ES256", key["kty"] as? String == "EC", key["crv"] as? String == "P-256", let x = key["x"] as? String, let y = key["y"] as? String, let xd = OAuthEncoding.decode(x), let yd = OAuthEncoding.decode(y) {
            let publicKey = try P256.Signing.PublicKey(x963Representation:Data([4])+xd+yd)
            signatureValid = publicKey.isValidSignature(try P256.Signing.ECDSASignature(rawRepresentation:signature),for:message)
        } else { throw AIError.message("Unsupported identity signing algorithm.") }
        let audience = (claims["aud"] as? String).map { [$0] } ?? (claims["aud"] as? [String] ?? [])
        guard signatureValid, claims["iss"] as? String == "https://auth.openai.com", audience.contains(clientID),
              audience.count <= 1 || claims["azp"] as? String == clientID,
              let expiration = claims["exp"] as? Double, expiration > now.timeIntervalSince1970,
              (claims["nbf"] as? Double ?? 0) <= now.timeIntervalSince1970 + 30,
              nonce == nil || claims["nonce"] as? String == nonce,
              let subject = claims["sub"] as? String, !subject.isEmpty else { throw AIError.message("ChatGPT account identity could not be verified. Start sign-in again.") }
        return VerifiedIdentity(subject:subject,email:claims["email"] as? String)
    }
    private static func derInteger(_ bytes:Data) -> Data {
        var value = Data(bytes.drop(while: { $0 == 0 })); if value.isEmpty { value = Data([0]) }
        if value.first! >= 128 { value.insert(0,at:0) }
        return der(2,value)
    }
    private static func der(_ tag:UInt8,_ bytes:Data) -> Data {
        var length = bytes.count; var encoded:[UInt8] = []
        if length < 128 { encoded = [UInt8(length)] } else {
            while length > 0 { encoded.insert(UInt8(length & 255),at:0); length >>= 8 }
            encoded.insert(0x80 | UInt8(encoded.count),at:0)
        }
        return Data([tag]+encoded)+bytes
    }
}
public protocol CredentialStoring: Sendable {
    func read(_ key:String) throws -> Data?
    func write(_ data:Data,key:String) throws
    func remove(_ key:String) throws
}
public struct KeychainCredentials: CredentialStoring {
    private let service:String
    public init(service:String = "personal.WeightCoach.ChatGPT") { self.service = service }
    private func query(_ key:String) -> [String:Any] { [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:key] }
    public func read(_ key:String) throws -> Data? {
        var q = query(key); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result:CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary,&result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw AIError.message("Could not read secure ChatGPT credentials. Unlock the phone and try again.") }
        return data
    }
    public func write(_ data:Data,key:String) throws {
        let q = query(key)
        let attributes:[String:Any] = [kSecValueData as String:data,kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(q as CFDictionary,attributes as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(q.merging(attributes) { _,new in new } as CFDictionary,nil) == errSecSuccess else { throw AIError.message("Could not save secure ChatGPT credentials.") }
        } else if status != errSecSuccess { throw AIError.message("Could not update secure ChatGPT credentials.") }
    }
    public func remove(_ key:String) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AIError.message("Could not remove ChatGPT credentials.") }
    }
}
private struct ChatGPTAccount: Codable, Sendable {
    var clientID:String
    var subject:String
    var email:String?
    var accessToken:String
    var refreshToken:String?
    var idToken:String
    var scopes:[String]
    var expiresAt:Date
}
public actor ChatGPTSession: AccessTokenProviding {
    private let credentials:any CredentialStoring
    private let session:URLSession
    private var renewal:Task<ChatGPTAccount,Error>?
    private var generation = 0
    public init(credentials:any CredentialStoring = KeychainCredentials(),session:URLSession? = nil) {
        self.credentials = credentials
        self.session = session ?? URLSession(configuration:.ephemeral)
    }
    private func account() throws -> ChatGPTAccount? {
        guard let data = try credentials.read("account") else { return nil }
        return try JSONDecoder().decode(ChatGPTAccount.self,from:data)
    }
    public func accountLabel() throws -> String? { try account().map { $0.email ?? "ChatGPT connected" } }
    public func attempt(redirect:URL) throws -> (OAuthAttempt,String?) {
        let host:String
        if let data = try credentials.read("host"), let saved = String(data:data,encoding:.utf8) { host = saved }
        else { host = "urn:uuid:"+UUID().uuidString.lowercased(); try credentials.write(Data(host.utf8),key:"host") }
        let existing = try account()
        return (try OAuthAttempt(hostID:host,clientID:existing?.clientID,redirect:redirect),existing?.idToken)
    }
    public func complete(attempt:OAuthAttempt,callback:URL) async throws {
        let version = generation
        let prior = try account()
        let value = try attempt.callback(callback)
        let result = try await tokenRequest(["grant_type":"authorization_code","client_id":value.clientID,"code":value.code,"code_verifier":attempt.verifier,"redirect_uri":attempt.redirect.absoluteString,"resource":"https://api.openai.com/v1"])
        guard let token = result["id_token"] as? String else { throw AIError.message("ChatGPT returned no identity token.") }
        let identity = try await validate(token:token,clientID:value.clientID,nonce:attempt.nonce)
        if let prior { guard prior.subject == identity.subject && prior.clientID == value.clientID else { throw AIError.message("The signed-in ChatGPT account does not match the saved account. Disconnect first to change accounts.") } }
        let account = try makeAccount(result:result,clientID:value.clientID,identity:identity,idToken:token,prior:nil)
        try Task.checkCancellation()
        guard version == generation else { throw CancellationError() }
        try credentials.write(JSONEncoder().encode(account),key:"account")
    }
    public func disconnect() throws {
        generation += 1; renewal?.cancel(); renewal = nil; try credentials.remove("account")
    }
    public func accessToken() async throws -> String {
        guard let current = try account(), current.scopes.contains("chatgpt.tokens.use.direct") else { throw AIError.message("Continue with ChatGPT in Settings and allow plan usage before analyzing a meal.") }
        if current.expiresAt > Date().addingTimeInterval(60) { return current.accessToken }
        if let renewal { return try await renewal.value.accessToken }
        guard let refresh = current.refreshToken else { throw AIError.message("Reconnect ChatGPT in Settings to renew your session.") }
        let version = generation
        let task = Task { () throws -> ChatGPTAccount in
            let result = try await self.tokenRequest(["grant_type":"refresh_token","client_id":current.clientID,"refresh_token":refresh,"resource":"https://api.openai.com/v1"])
            let identity:VerifiedIdentity
            let idToken = result["id_token"] as? String ?? current.idToken
            if result["id_token"] != nil {
                identity = try await self.validate(token:idToken,clientID:current.clientID,nonce:nil)
                guard identity.subject == current.subject else { throw AIError.message("Refreshed account identity changed. Reconnect ChatGPT.") }
            } else { identity = VerifiedIdentity(subject:current.subject,email:current.email) }
            let updated = try self.makeAccount(result:result,clientID:current.clientID,identity:identity,idToken:idToken,prior:current)
            try Task.checkCancellation()
            guard version == self.generation else { throw CancellationError() }
            try self.credentials.write(JSONEncoder().encode(updated),key:"account")
            return updated
        }
        renewal = task
        defer { if generation == version { renewal = nil } }
        return try await task.value.accessToken
    }
    private func tokenRequest(_ values:[String:String]) async throws -> [String:Any] {
        var request = URLRequest(url:URL(string:"https://auth.openai.com/api/accounts/oauth/token")!)
        request.httpMethod = "POST"; request.httpBody = OAuthEncoding.form(values); request.setValue("application/x-www-form-urlencoded",forHTTPHeaderField:"Content-Type")
        let (data,response) = try await session.data(for:request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), let object = try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw AIError.message("ChatGPT could not authorize or renew this session. Start sign-in again.") }
        return object
    }
    private func validate(token:String,clientID:String,nonce:String?) async throws -> VerifiedIdentity {
        let (keys,response) = try await session.data(from:URL(string:"https://auth.openai.com/.well-known/jwks.json")!)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw AIError.message("Unable to obtain ChatGPT identity signing keys.") }
        return try IDTokenValidator.validate(token,jwks:keys,clientID:clientID,nonce:nonce)
    }
    private func makeAccount(result:[String:Any],clientID:String,identity:VerifiedIdentity,idToken:String,prior:ChatGPTAccount?) throws -> ChatGPTAccount {
        let scopes = (result["scope"] as? String).map { $0.split(separator:" ").map(String.init) } ?? prior?.scopes ?? []
        guard scopes.contains("chatgpt.tokens.use.direct"), let access = result["access_token"] as? String, !access.isEmpty,
              (result["token_type"] as? String)?.lowercased() == "bearer", let seconds = result["expires_in"] as? Double, seconds.isFinite, seconds > 0 else { throw AIError.message("ChatGPT plan permission was not granted or credentials are incomplete. Reconnect and allow plan usage.") }
        return ChatGPTAccount(clientID:clientID,subject:identity.subject,email:identity.email,accessToken:access,refreshToken:result["refresh_token"] as? String ?? prior?.refreshToken,idToken:idToken,scopes:scopes,expiresAt:Date().addingTimeInterval(seconds))
    }
}
