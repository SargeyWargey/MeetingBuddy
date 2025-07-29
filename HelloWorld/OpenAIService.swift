import Foundation
import Security

// MARK: - AI Service Protocol

protocol AIServiceProtocol {
    func generateSummary(
        from text: String,
        type: SummaryType,
        length: SummaryLength
    ) async throws -> SummaryResult
    
    func isAvailable() -> Bool
    func estimatedCost(for text: String) -> Double?
    func maxInputLength() -> Int
}

// MARK: - OpenAI Service

class OpenAIService: AIServiceProtocol {
    
    // MARK: - Constants
    
    private let baseURL = "https://api.openai.com/v1"
    private let model = "gpt-3.5-turbo"
    private let maxTokens = 4096
    private let costPerToken = 0.000002 // $0.002 per 1K tokens
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 1.0
    
    // MARK: - Properties
    
    private let session: URLSession
    private let networkMonitor: NetworkMonitor?
    private var usageTracker: OpenAIUsageTracker
    
    // MARK: - Initialization
    
    init(networkMonitor: NetworkMonitor? = nil) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        self.session = URLSession(configuration: config)
        self.networkMonitor = networkMonitor
        self.usageTracker = OpenAIUsageTracker()
    }
    
    // MARK: - AIServiceProtocol Implementation
    
    func generateSummary(
        from text: String,
        type: SummaryType,
        length: SummaryLength
    ) async throws -> SummaryResult {
        let startTime = Date()
        
        // Validate input
        guard !text.isEmpty else {
            throw SummaryError.unknownError("Empty text provided")
        }
        
        guard text.count <= maxInputLength() else {
            let wordCount = text.split(separator: " ").count
            throw SummaryError.contentTooLarge(wordCount: wordCount, maxWords: maxInputLength() / 4)
        }
        
        // Check API key
        guard let apiKey = getAPIKey() else {
            throw SummaryError.apiKeyMissing
        }
        
        // Check network availability
        if let networkMonitor = networkMonitor {
            let isConnected = await MainActor.run { networkMonitor.isConnected }
            if !isConnected {
                throw SummaryError.networkUnavailable
            }
        }
        
        // Build the prompt
        let prompt = buildPrompt(text: text, type: type, length: length)
        
        // Make API call with retries
        let response = try await makeAPICallWithRetries(prompt: prompt, apiKey: apiKey)
        
        // Parse response
        let summaryText = try parseSummaryResponse(response)
        
        // Calculate processing time
        let processingTime = Date().timeIntervalSince(startTime)
        
        // Track usage
        let tokenCount = estimateTokenCount(text + summaryText)
        usageTracker.recordUsage(tokens: tokenCount, cost: Double(tokenCount) * costPerToken)
        
        // Create result
        return SummaryResult(
            text: summaryText,
            confidence: 0.9, // OpenAI generally provides high-quality results
            provider: .openAI,
            processingTime: processingTime,
            wordCount: summaryText.split(separator: " ").count,
            metadata: [
                "model": model,
                "tokens_used": String(tokenCount),
                "cost_usd": String(format: "%.6f", Double(tokenCount) * costPerToken)
            ]
        )
    }
    
    func isAvailable() -> Bool {
        return getAPIKey() != nil
    }
    
    func estimatedCost(for text: String) -> Double? {
        let tokenCount = estimateTokenCount(text)
        return Double(tokenCount) * costPerToken
    }
    
    func maxInputLength() -> Int {
        return maxTokens * 3 // Rough estimate: 1 token ≈ 3-4 characters
    }
    
    // MARK: - Private Methods
    
    private func buildPrompt(text: String, type: SummaryType, length: SummaryLength) -> String {
        let lengthInstruction = getLengthInstruction(for: length)
        let typeInstruction = getTypeInstruction(for: type)
        
        return """
        Please provide a \(lengthInstruction) \(typeInstruction) of the following text. \(getAdditionalInstructions(for: type))
        
        Text to summarize:
        \(text)
        
        Summary:
        """
    }
    
    private func getLengthInstruction(for length: SummaryLength) -> String {
        switch length {
        case .short:
            return "concise (50-100 words)"
        case .medium:
            return "medium-length (100-200 words)"
        case .long:
            return "detailed (200-300 words)"
        }
    }
    
    private func getTypeInstruction(for type: SummaryType) -> String {
        switch type {
        case .brief:
            return "summary"
        case .detailed:
            return "comprehensive summary"
        case .bulletPoints:
            return "summary in bullet point format"
        case .keyInsights:
            return "summary focusing on key insights and takeaways"
        }
    }
    
    private func getAdditionalInstructions(for type: SummaryType) -> String {
        switch type {
        case .brief:
            return "Focus on the main points and key information."
        case .detailed:
            return "Include context, details, and supporting information."
        case .bulletPoints:
            return "Use bullet points (•) to organize the information clearly."
        case .keyInsights:
            return "Highlight the most important insights, conclusions, and actionable takeaways."
        }
    }
    
    private func makeAPICallWithRetries(prompt: String, apiKey: String) async throws -> OpenAIResponse {
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                return try await makeAPICall(prompt: prompt, apiKey: apiKey)
            } catch let error as SummaryError {
                lastError = error
                
                // Don't retry for certain errors
                switch error {
                case .apiKeyInvalid, .quotaExceeded, .contentTooLarge:
                    throw error
                default:
                    if attempt == maxRetries {
                        throw error
                    }
                }
            } catch {
                lastError = error
                if attempt == maxRetries {
                    throw SummaryError.unknownError(error.localizedDescription)
                }
            }
            
            // Wait before retrying with exponential backoff
            let delay = retryDelay * pow(2.0, Double(attempt - 1))
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        
        throw lastError ?? SummaryError.unknownError("Max retries exceeded")
    }
    
    private func makeAPICall(prompt: String, apiKey: String) async throws -> OpenAIResponse {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw SummaryError.unknownError("Invalid API URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = OpenAIRequest(
            model: model,
            messages: [
                OpenAIMessage(role: "user", content: prompt)
            ],
            maxTokens: 500, // Reasonable limit for summaries
            temperature: 0.3 // Lower temperature for more consistent summaries
        )
        
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            throw SummaryError.unknownError("Failed to encode request: \(error.localizedDescription)")
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SummaryError.networkUnavailable
            }
            
            // Handle HTTP errors
            switch httpResponse.statusCode {
            case 200:
                break // Success
            case 401:
                throw SummaryError.apiKeyInvalid
            case 429:
                throw SummaryError.rateLimitExceeded
            case 402:
                throw SummaryError.quotaExceeded(provider: .openAI)
            case 503:
                throw SummaryError.aiServiceUnavailable(provider: .openAI)
            default:
                throw SummaryError.invalidResponse(provider: .openAI)
            }
            
            // Parse response
            do {
                let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
                return openAIResponse
            } catch {
                throw SummaryError.invalidResponse(provider: .openAI)
            }
            
        } catch let error as SummaryError {
            throw error
        } catch {
            if error.localizedDescription.contains("network") {
                throw SummaryError.networkUnavailable
            } else {
                throw SummaryError.unknownError(error.localizedDescription)
            }
        }
    }
    
    private func parseSummaryResponse(_ response: OpenAIResponse) throws -> String {
        guard let choice = response.choices.first else {
            throw SummaryError.invalidResponse(provider: .openAI)
        }
        
        let content = choice.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw SummaryError.invalidResponse(provider: .openAI)
        }
        
        return content
    }
    
    private func estimateTokenCount(_ text: String) -> Int {
        // Rough estimation: 1 token ≈ 4 characters for English text
        return text.count / 4
    }
    
    // MARK: - API Key Management
    
    private func getAPIKey() -> String? {
        return KeychainManager.shared.getOpenAIAPIKey()
    }
    
    func setAPIKey(_ apiKey: String) throws {
        try KeychainManager.shared.setOpenAIAPIKey(apiKey)
    }
    
    func removeAPIKey() throws {
        try KeychainManager.shared.removeOpenAIAPIKey()
    }
    
    // MARK: - Usage Tracking
    
    func getUsageStats() -> OpenAIUsageStats {
        return usageTracker.getStats()
    }
    
    func resetUsageStats() {
        usageTracker.reset()
    }
}

// MARK: - OpenAI API Models

private struct OpenAIRequest: Codable {
    let model: String
    let messages: [OpenAIMessage]
    let maxTokens: Int
    let temperature: Double
    
    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case temperature
    }
}

private struct OpenAIMessage: Codable {
    let role: String
    let content: String
}

private struct OpenAIResponse: Codable {
    let choices: [OpenAIChoice]
    let usage: OpenAIUsage?
}

private struct OpenAIChoice: Codable {
    let message: OpenAIMessage
    let finishReason: String?
    
    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

private struct OpenAIUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    
    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

// MARK: - Usage Tracking

class OpenAIUsageTracker {
    private var dailyTokens: Int = 0
    private var dailyCost: Double = 0.0
    private var lastResetDate: Date = Date()
    
    func recordUsage(tokens: Int, cost: Double) {
        resetIfNewDay()
        dailyTokens += tokens
        dailyCost += cost
    }
    
    func getStats() -> OpenAIUsageStats {
        resetIfNewDay()
        return OpenAIUsageStats(
            dailyTokens: dailyTokens,
            dailyCost: dailyCost,
            lastResetDate: lastResetDate
        )
    }
    
    func reset() {
        dailyTokens = 0
        dailyCost = 0.0
        lastResetDate = Date()
    }
    
    private func resetIfNewDay() {
        let calendar = Calendar.current
        if !calendar.isDate(lastResetDate, inSameDayAs: Date()) {
            reset()
        }
    }
}

struct OpenAIUsageStats {
    let dailyTokens: Int
    let dailyCost: Double
    let lastResetDate: Date
    
    var formattedCost: String {
        return String(format: "$%.4f", dailyCost)
    }
}

// MARK: - Keychain Manager

class KeychainManager {
    static let shared = KeychainManager()
    
    private let service = "com.helloworld.openai"
    private let apiKeyAccount = "openai_api_key"
    
    private init() {}
    
    func setOpenAIAPIKey(_ apiKey: String) throws {
        let data = apiKey.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecValueData as String: data
        ]
        
        // Delete existing item
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw SummaryError.cacheError(operation: "storing API key")
        }
    }
    
    func getOpenAIAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return apiKey
    }
    
    func removeOpenAIAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SummaryError.cacheError(operation: "removing API key")
        }
    }
}