import XCTest
@testable import LorreCore

final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            stream.close()
            body = data
        }
        Self.lastBody = body
        do {
            let (response, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class OllamaTextGeneratorTests: XCTestCase {
    private func generator(model: String = "gemma4:e4b") -> OllamaTextGenerator {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return OllamaTextGenerator(model: model, session: URLSession(configuration: configuration), timeout: 42)
    }

    private func reply(_ status: Int, _ json: String, for request: URLRequest) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        StubURLProtocol.lastBody = nil
    }

    func testRequestBodyAndResponse() async throws {
        var seen: URLRequest?
        StubURLProtocol.handler = { request in
            seen = request
            return self.reply(200, #"{"message":{"role":"assistant","content":"{\"items\":[]}"},"done":true}"#, for: request)
        }
        let text = try await generator().generate(system: "S", prompt: "P", json: true)
        XCTAssertEqual(text, #"{"items":[]}"#)
        XCTAssertEqual(seen?.url?.absoluteString, "http://localhost:11434/api/chat")
        XCTAssertEqual(seen?.httpMethod, "POST")
        XCTAssertEqual(seen?.timeoutInterval, 42)

        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(StubURLProtocol.lastBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "gemma4:e4b")
        XCTAssertEqual(body["stream"] as? Bool, false)
        XCTAssertEqual(body["format"] as? String, "json")
        XCTAssertEqual((body["options"] as? [String: Any])?["temperature"] as? Double, 0)
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages, [["role": "system", "content": "S"], ["role": "user", "content": "P"]])
    }

    func testNoFormatWhenJSONIsNotAsked() async throws {
        StubURLProtocol.handler = { self.reply(200, #"{"message":{"content":"hoi"}}"#, for: $0) }
        let text = try await generator().generate(system: "S", prompt: "P", json: false)
        XCTAssertEqual(text, "hoi")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(StubURLProtocol.lastBody)) as? [String: Any])
        XCTAssertNil(body["format"])
    }

    func testIdentifier() {
        XCTAssertEqual(generator(model: "qwen3.5:9b").identifier, "ollama:qwen3.5:9b")
    }

    func testMissingModelIsReported() async {
        StubURLProtocol.handler = { self.reply(404, #"{"error":"model 'nope' not found"}"#, for: $0) }
        do {
            _ = try await generator(model: "nope").generate(system: "S", prompt: "P", json: true)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? OllamaError, .modelMissing("nope"))
            XCTAssertTrue(error.localizedDescription.contains("ollama pull nope"))
        }
    }

    func testServerErrorIsReportedWithItsMessage() async {
        StubURLProtocol.handler = { self.reply(500, #"{"error":"out of memory"}"#, for: $0) }
        do {
            _ = try await generator().generate(system: "S", prompt: "P", json: true)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? OllamaError, .http(status: 500, message: "out of memory"))
        }
    }

    func testUnreachableServerIsReported() async {
        StubURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        do {
            _ = try await generator().generate(system: "S", prompt: "P", json: true)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? OllamaError, .notReachable(baseURL: "http://localhost:11434"))
            XCTAssertTrue(error.localizedDescription.contains("not reachable"))
        }
    }

    func testTimeoutIsReported() async {
        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }
        do {
            _ = try await generator().generate(system: "S", prompt: "P", json: true)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? OllamaError, .timedOut)
        }
    }

    func testUnreadableAnswerIsReported() async {
        StubURLProtocol.handler = { self.reply(200, "<html>", for: $0) }
        do {
            _ = try await generator().generate(system: "S", prompt: "P", json: true)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? OllamaError, .unreadableResponse)
        }
    }
}
