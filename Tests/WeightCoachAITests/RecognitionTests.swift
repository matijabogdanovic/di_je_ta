import XCTest
import CryptoKit
@testable import WeightCoachAI
import WeightCoachCore

final class RecognitionTests:XCTestCase {
    private let valid = """
    {"foods":[{"name":"Bread","estimated_grams":70,"calories":180,"protein_g":6,"carbs_g":35,"fat_g":2,"confidence":0.7,"uncertainty":"Bread weight estimated."},{"name":"Butter","estimated_grams":10,"calories":72,"protein_g":0,"carbs_g":0,"fat_g":8,"confidence":0.9,"uncertainty":"Quantity supplied by user."}],"overall_confidence":"medium","assumptions":"Butter included from user context, not visible."}
    """
    func testNoteAndImageAreIncludedWithoutPersistentStorage() throws {
        let data = try MealRequest.body(jpeg:Data([0xff,0xd8,0xff]),note:"Butter under the vegetables, about 10 g",model:"account-selected-model")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        XCTAssertEqual(body["store"] as? Bool,false); XCTAssertEqual(body["stream"] as? Bool,true)
        XCTAssertNil(body["max_output_tokens"]); XCTAssertNil(body["previous_response_id"])
        let input = try XCTUnwrap(body["input"] as? [[String:Any]])
        let content = try XCTUnwrap(input[0]["content"] as? [[String:String]])
        XCTAssertTrue(content[0]["text"]!.contains("Butter under the vegetables, about 10 g"))
        XCTAssertEqual(content[1]["image_url"],"data:image/jpeg;base64,/9j/")
        let text = try XCTUnwrap(body["text"] as? [String:Any])
        let format = try XCTUnwrap(text["format"] as? [String:Any]); XCTAssertEqual(format["strict"] as? Bool,true)
        XCTAssertThrowsError(try MealRequest.body(jpeg:Data(),note:"",model:"model"))
        XCTAssertThrowsError(try MealRequest.body(jpeg:Data([1]),note:String(repeating:"x",count:2001),model:"model"))
    }
    func testStructuredFoodsValidateAndPreserveOriginalValues() throws {
        let result = try MealRecognition.decode(Data(valid.utf8))
        XCTAssertEqual(result.totals.calories,252); XCTAssertEqual(result.items[1].estimatedGrams,10)
        XCTAssertEqual(result.items[1].estimate?.fat,8)
        XCTAssertThrowsError(try MealRecognition.decode(Data(valid.replacingOccurrences(of:"\"confidence\":0.7",with:"\"confidence\":1.7").utf8)))
        XCTAssertThrowsError(try MealRecognition.decode(Data("{\"foods\":[],\"overall_confidence\":\"low\",\"assumptions\":\"No food\"}".utf8)))
    }
    private func completedEvent() throws -> String {
        let event:[String:Any] = ["type":"response.completed","response":["status":"completed","output":[["type":"message","content":[["type":"output_text","text":valid]]]]]]
        return String(decoding:try JSONSerialization.data(withJSONObject:event),as:UTF8.self)
    }
    func testStreamRequiresCompletedResponseAndRejectsFailures() throws {
        var stream = ResponseStream()
        try stream.receive(line:"event: response.completed")
        try stream.receive(line:"data: "+completedEvent()); try stream.receive(line:"")
        XCTAssertTrue(stream.isComplete)
        XCTAssertEqual(try MealRecognition.decode(stream.finish()).totals.calories,252)
        var interrupted = ResponseStream()
        try interrupted.receive(line:"data: {\"type\":\"response.output_text.delta\",\"delta\":\"partial\"}"); try interrupted.receive(line:"")
        XCTAssertThrowsError(try interrupted.finish())
        var failed = ResponseStream()
        try failed.receive(line:"data: {\"type\":\"response.failed\",\"response\":{\"error\":{\"code\":\"subscription_sharing_usage_limit_exceeded\"}}}")
        XCTAssertThrowsError(try failed.receive(line:""))
    }
    func testRefusalIsNeverTreatedAsNutrition() throws {
        var stream = ResponseStream()
        try stream.receive(line:"data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"output\":[{\"content\":[{\"type\":\"refusal\",\"refusal\":\"No\"}]}]}}")
        XCTAssertThrowsError(try stream.finish())
    }
    @MainActor func testAuditSurvivesCorrectionsAndBackupWithoutPhoto() throws {
        let result = AnalysisResult(recognition:try MealRecognition.decode(Data(valid.utf8)),model:"chosen-model",analyzedAt:Date())
        let audit = try result.audit(note:"Butter under vegetables, 10 g")
        let store = try TrackingStore(path:":memory:")
        var meal = Meal(notes:"Butter under vegetables, 10 g",items:result.recognition.items)
        meal.items[0].final.calories = 200
        try store.save(meal,audit:audit)
        var row = try XCTUnwrap(store.database.query("SELECT * FROM ai_estimates").first)
        let stored = try JSONDecoder().decode(MealEstimateAudit.self,from:Data(row["normalized_response"]!.utf8))
        XCTAssertEqual(stored.originalTotals.calories,252)
        XCTAssertTrue(stored.normalizedResponse.contains("Butter under vegetables, 10 g"))
        var delta = try JSONDecoder().decode(Nutrition.self,from:Data(row["user_correction_delta"]!.utf8))
        XCTAssertEqual(delta.calories,20)
        meal.items.removeLast(); try store.save(meal)
        row = try XCTUnwrap(store.database.query("SELECT * FROM ai_estimates").first)
        delta = try JSONDecoder().decode(Nutrition.self,from:Data(row["user_correction_delta"]!.utf8)); XCTAssertEqual(delta.calories,-52)
        let backup = try store.exportData()
        XCTAssertFalse(String(decoding:backup,as:UTF8.self).contains("base64"))
        let restored = try TrackingStore(path:":memory:"); try restored.importData(backup)
        XCTAssertEqual(try restored.database.query("SELECT * FROM ai_estimates"),try store.database.query("SELECT * FROM ai_estimates"))
    }
    func testPKCEAndCallbackValidation() throws {
        let redirect = URL(string:"http://127.0.0.1:1455/auth/callback")!
        let attempt = try OAuthAttempt(hostID:"urn:uuid:test",clientID:nil,redirect:redirect)
        let params = URLComponents(url:attempt.authorizationURL(),resolvingAgainstBaseURL:false)!.queryItems!
        let values = Dictionary(uniqueKeysWithValues:params.map { ($0.name,$0.value!) })
        XCTAssertEqual(values["client_id"],"dynamic_agent_client")
        XCTAssertEqual(values["code_challenge"],OAuthEncoding.base64URL(Data(SHA256.hash(data:Data(attempt.verifier.utf8)))))
        var url = URLComponents(url:redirect,resolvingAgainstBaseURL:false)!
        url.queryItems = [.init(name:"state",value:attempt.state),.init(name:"code",value:"code"),.init(name:"client_id",value:"oaiapp_issued")]
        XCTAssertEqual(try attempt.callback(url.url!).clientID,"oaiapp_issued")
        url.queryItems![0].value = "wrong"; XCTAssertThrowsError(try attempt.callback(url.url!))
        let returning = try OAuthAttempt(hostID:"urn:uuid:test",clientID:"oaiapp_saved",redirect:redirect)
        url.queryItems = [.init(name:"state",value:returning.state),.init(name:"code",value:"code"),.init(name:"client_id",value:"oaiapp_other")]
        XCTAssertThrowsError(try returning.callback(url.url!))
        url.queryItems!.removeLast(); XCTAssertEqual(try returning.callback(url.url!).clientID,"oaiapp_saved")
        url.queryItems!.append(.init(name:"state",value:returning.state)); XCTAssertThrowsError(try returning.callback(url.url!))
        XCTAssertNotEqual(attempt.state,returning.state)
    }
    func testIDTokenSignatureAudienceNonceAndExpiry() throws {
        let key = P256.Signing.PrivateKey()
        let publicKey = key.publicKey.x963Representation
        let jwks = try JSONSerialization.data(withJSONObject:["keys":[["kid":"test","alg":"ES256","kty":"EC","crv":"P-256","x":OAuthEncoding.base64URL(publicKey.subdata(in:1..<33)),"y":OAuthEncoding.base64URL(publicKey.subdata(in:33..<65))]]])
        let now = Date()
        func token(_ changes:[String:Any] = [:]) throws -> String {
            var claims:[String:Any] = ["iss":"https://auth.openai.com","aud":"oaiapp_test","sub":"user","nonce":"nonce","exp":now.addingTimeInterval(60).timeIntervalSince1970]
            claims.merge(changes) { _,new in new }
            let header = OAuthEncoding.base64URL(try JSONSerialization.data(withJSONObject:["kid":"test","alg":"ES256"]))
            let body = OAuthEncoding.base64URL(try JSONSerialization.data(withJSONObject:claims))
            let unsigned = header+"."+body
            return unsigned+"."+OAuthEncoding.base64URL(try key.signature(for:Data(unsigned.utf8)).rawRepresentation)
        }
        XCTAssertEqual(try IDTokenValidator.validate(token(),jwks:jwks,clientID:"oaiapp_test",nonce:"nonce",now:now).subject,"user")
        for claims in [["exp":now.addingTimeInterval(-1).timeIntervalSince1970] as [String:Any],["aud":"other"],["nonce":"wrong"],["iss":"https://other.example"],["aud":["oaiapp_test","other"]]] {
            XCTAssertThrowsError(try IDTokenValidator.validate(token(claims),jwks:jwks,clientID:"oaiapp_test",nonce:"nonce",now:now))
        }
        let good = try token(); let pieces = good.split(separator:".")
        let forged = String(pieces[0])+"."+String(pieces[1])+"."+OAuthEncoding.base64URL(Data(repeating:0,count:64))
        XCTAssertThrowsError(try IDTokenValidator.validate(forged,jwks:jwks,clientID:"oaiapp_test",nonce:"nonce",now:now))
    }
}
