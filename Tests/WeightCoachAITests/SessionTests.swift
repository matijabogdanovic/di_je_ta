import XCTest
import Foundation
@testable import WeightCoachAI

private final class MemoryCredentials:CredentialStoring,@unchecked Sendable {
    private let lock = NSLock()
    private var values:[String:Data] = [:]
    func read(_ key:String) throws -> Data? { lock.withLock { values[key] } }
    func write(_ data:Data,key:String) throws { lock.withLock { values[key] = data } }
    func remove(_ key:String) throws { _ = lock.withLock { values.removeValue(forKey:key) } }
}
private final class TokenFixture:URLProtocol,@unchecked Sendable {
    override class func canInit(with request:URLRequest) -> Bool { request.url?.host == "auth.openai.com" }
    override class func canonicalRequest(for request:URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body:Data
        if let value = request.httpBody { body = value }
        else if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating:0,count:4096); var data = Data()
            while true { let size = stream.read(&buffer,maxLength:buffer.count); if size <= 0 { break }; data.append(contentsOf:buffer.prefix(size)) }
            body = data
        } else { body = Data() }
        let expected = "client_id=oaiapp_saved&grant_type=refresh_token&refresh_token=old-refresh&resource=https%3A%2F%2Fapi.openai.com%2Fv1"
        let success = String(decoding:body,as:UTF8.self) == expected
        let payload = success ? "{\"access_token\":\"new-access\",\"refresh_token\":\"rotated-refresh\",\"token_type\":\"Bearer\",\"expires_in\":3600,\"scope\":\"chatgpt.tokens.use.direct offline_access\"}" : "{}"
        let response = HTTPURLResponse(url:request.url!,statusCode:success ? 200 : 400,httpVersion:nil,headerFields:["Content-Type":"application/json"])!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Data(payload.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class SessionTests:XCTestCase {
    private func seeded(expired:Bool) throws -> MemoryCredentials {
        let vault = MemoryCredentials()
        let account:[String:Any] = ["clientID":"oaiapp_saved","subject":"user","email":"person@example.test","accessToken":"cached-access","refreshToken":"old-refresh","idToken":"retained-id-token","scopes":["chatgpt.tokens.use.direct","offline_access"],"expiresAt":Date().addingTimeInterval(expired ? -60 : 3600).timeIntervalSinceReferenceDate]
        try vault.write(JSONSerialization.data(withJSONObject:account),key:"account"); try vault.write(Data("urn:uuid:stable-host".utf8),key:"host")
        return vault
    }
    func testCachedCredentialsAndDisconnect() async throws {
        let vault = try seeded(expired:false); let session = ChatGPTSession(credentials:vault)
        let label = try await session.accountLabel(); XCTAssertEqual(label,"person@example.test")
        let token = try await session.accessToken(); XCTAssertEqual(token,"cached-access")
        try await session.disconnect()
        XCTAssertNil(try vault.read("account")); XCTAssertNotNil(try vault.read("host"))
        do { _ = try await session.accessToken(); XCTFail("Disconnected credentials were accepted") } catch { }
    }
    func testRefreshUsesIssuedClientAndAtomicallyRotatesCredentials() async throws {
        let vault = try seeded(expired:true)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [TokenFixture.self]
        let session = ChatGPTSession(credentials:vault,session:URLSession(configuration:config))
        let token = try await session.accessToken(); XCTAssertEqual(token,"new-access")
        let record = try XCTUnwrap(JSONSerialization.jsonObject(with:XCTUnwrap(vault.read("account"))) as? [String:Any])
        XCTAssertEqual(record["refreshToken"] as? String,"rotated-refresh")
        XCTAssertEqual(record["clientID"] as? String,"oaiapp_saved")
        XCTAssertEqual(record["idToken"] as? String,"retained-id-token")
        XCTAssertTrue((record["expiresAt"] as! Double) > Date().timeIntervalSinceReferenceDate)
    }
}
