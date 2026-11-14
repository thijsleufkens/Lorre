import Foundation

public enum OllamaError: Error, Equatable, LocalizedError {
    case notReachable(baseURL: String)
    case modelMissing(String)
    case http(status: Int, message: String)
    case unreadableResponse
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .notReachable(let url):
            "Ollama is not reachable at \(url). Start it (`ollama serve`, or open the Ollama app) and try again."
        case .modelMissing(let model):
            "Ollama does not have the model \(model). Download it with `ollama pull \(model)`."
        case .http(let status, let message):
            "Ollama answered with an error (\(status)): \(message)"
        case .unreadableResponse:
            "Ollama sent an answer Lorre cannot read."
        case .timedOut:
            "Ollama took too long to answer."
        }
    }
}

/// A local model behind Ollama's chat endpoint. Temperature 0, no streaming.
public struct OllamaTextGenerator: TextGenerator {
    public static let defaultBaseURL = URL(string: "http://localhost:11434")!

    public let model: String
    public let baseURL: URL
    public let timeout: TimeInterval
    /// Context window asked of the model; Ollama's own default is too small for a consolidation request.
    public let contextTokens: Int
    private let session: URLSession

    public var identifier: String { "ollama:\(model)" }

    public init(
        model: String,
        baseURL: URL = OllamaTextGenerator.defaultBaseURL,
        session: URLSession = .shared,
        timeout: TimeInterval = 900,
        contextTokens: Int = 8192
    ) {
        self.model = model
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
        self.contextTokens = contextTokens
    }

    struct ChatRequest: Encodable {
        struct Message: Encodable { var role: String; var content: String }
        struct Options: Encodable { var temperature: Double; var num_ctx: Int }
        var model: String
        var messages: [Message]
        var stream: Bool
        var format: String?
        var options: Options
    }

    struct ChatResponse: Decodable {
        struct Message: Decodable { var content: String }
        var message: Message?
        var error: String?
    }

    func makeRequest(system: String, prompt: String, json: Bool) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ChatRequest(
            model: model,
            messages: [.init(role: "system", content: system), .init(role: "user", content: prompt)],
            stream: false,
            format: json ? "json" : nil,
            options: .init(temperature: 0, num_ctx: contextTokens)
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    public func generate(system: String, prompt: String, json: Bool) async throws -> String {
        let request = try makeRequest(system: system, prompt: prompt, json: json)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .timedOut: throw OllamaError.timedOut
            case .cancelled: throw error
            default: throw OllamaError.notReachable(baseURL: baseURL.absoluteString)
            }
        }
        let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = decoded?.error ?? String(decoding: data.prefix(300), as: UTF8.self)
            if http.statusCode == 404 || message.lowercased().contains("not found") {
                throw OllamaError.modelMissing(model)
            }
            throw OllamaError.http(status: http.statusCode, message: message)
        }
        if let error = decoded?.error { throw OllamaError.http(status: 200, message: error) }
        guard let content = decoded?.message?.content else { throw OllamaError.unreadableResponse }
        return content
    }
}
