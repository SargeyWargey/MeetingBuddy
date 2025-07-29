import Foundation
import NaturalLanguage

// MARK: - On-Device AI Service

class OnDeviceAIService: AIServiceProtocol {
    
    // MARK: - Constants
    
    private let maxInputLengthValue = 10000 // Characters
    private let sentenceMinLength = 10
    private let sentenceMaxLength = 200
    
    // MARK: - Properties
    
    private let tokenizer: NLTokenizer
    private let tagger: NLTagger
    
    // MARK: - Initialization
    
    init() {
        self.tokenizer = NLTokenizer(unit: .sentence)
        self.tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType])
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
        
        // Extract and rank sentences
        let sentences = extractSentences(from: text)
        guard !sentences.isEmpty else {
            throw SummaryError.unknownError("No sentences found in text")
        }
        
        let rankedSentences = await rankSentencesByImportance(sentences, originalText: text)
        
        // Select top sentences based on desired length
        let selectedSentences = selectTopSentences(rankedSentences, for: length)
        
        // Format summary based on type
        let summaryText = formatSummary(selectedSentences, type: type)
        
        // Calculate processing time
        let processingTime = Date().timeIntervalSince(startTime)
        
        // Calculate confidence based on sentence coverage and quality
        let confidence = calculateConfidence(
            selectedSentences: selectedSentences,
            totalSentences: sentences.count,
            originalWordCount: text.split(separator: " ").count
        )
        
        return SummaryResult(
            text: summaryText,
            confidence: confidence,
            provider: .onDevice,
            processingTime: processingTime,
            wordCount: summaryText.split(separator: " ").count,
            metadata: [
                "method": "extractive",
                "sentences_analyzed": String(sentences.count),
                "sentences_selected": String(selectedSentences.count),
                "compression_ratio": String(format: "%.2f", Double(summaryText.count) / Double(text.count))
            ]
        )
    }
    
    func isAvailable() -> Bool {
        // On-device processing is always available
        return true
    }
    
    func estimatedCost(for text: String) -> Double? {
        // On-device processing is free
        return 0.0
    }
    
    func maxInputLength() -> Int {
        return maxInputLengthValue
    }
    
    // MARK: - Private Methods
    
    private func extractSentences(from text: String) -> [String] {
        tokenizer.string = text
        var sentences: [String] = []
        
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
            let sentence = String(text[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Filter out very short or very long sentences
            if sentence.count >= sentenceMinLength && sentence.count <= sentenceMaxLength {
                sentences.append(sentence)
            }
            
            return true
        }
        
        return sentences
    }
    
    private func rankSentencesByImportance(_ sentences: [String], originalText: String) async -> [(String, Double)] {
        return await withTaskGroup(of: (String, Double).self, returning: [(String, Double)].self) { group in
            
            // Calculate TF-IDF scores for each sentence
            let wordFrequencies = calculateWordFrequencies(in: originalText)
            
            for sentence in sentences {
                group.addTask {
                    let score = self.calculateSentenceScore(
                        sentence: sentence,
                        wordFrequencies: wordFrequencies,
                        originalText: originalText
                    )
                    return (sentence, score)
                }
            }
            
            var rankedSentences: [(String, Double)] = []
            for await result in group {
                rankedSentences.append(result)
            }
            
            // Sort by score (highest first)
            return rankedSentences.sorted { $0.1 > $1.1 }
        }
    }
    
    private func calculateWordFrequencies(in text: String) -> [String: Int] {
        let words = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .compactMap { word in
                let cleaned = word.trimmingCharacters(in: .punctuationCharacters)
                return cleaned.isEmpty ? nil : cleaned
            }
        
        var frequencies: [String: Int] = [:]
        for word in words {
            frequencies[word, default: 0] += 1
        }
        
        return frequencies
    }
    
    private func calculateSentenceScore(
        sentence: String,
        wordFrequencies: [String: Int],
        originalText: String
    ) -> Double {
        let words = sentence.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .compactMap { word in
                let cleaned = word.trimmingCharacters(in: .punctuationCharacters)
                return cleaned.isEmpty ? nil : cleaned
            }
        
        guard !words.isEmpty else { return 0.0 }
        
        // Calculate TF-IDF-like score
        var score = 0.0
        let totalWords = originalText.split(separator: " ").count
        
        for word in words {
            if let frequency = wordFrequencies[word] {
                // Term frequency
                let tf = Double(frequency) / Double(totalWords)
                
                // Simple inverse document frequency approximation
                let idf = log(Double(totalWords) / Double(frequency))
                
                score += tf * idf
            }
        }
        
        // Normalize by sentence length
        score = score / Double(words.count)
        
        // Boost score for sentences with important linguistic features
        score += calculateLinguisticBoost(sentence: sentence)
        
        // Penalize very short or very long sentences
        score *= calculateLengthPenalty(sentence: sentence)
        
        return score
    }
    
    private func calculateLinguisticBoost(sentence: String) -> Double {
        var boost = 0.0
        
        tagger.string = sentence
        
        // Boost sentences with named entities
        tagger.enumerateTags(in: sentence.startIndex..<sentence.endIndex, unit: .word, scheme: .nameType) { tag, tokenRange in
            if let tag = tag {
                switch tag {
                case .personalName, .placeName, .organizationName:
                    boost += 0.1
                default:
                    break
                }
            }
            return true
        }
        
        // Boost sentences with numbers (often contain important facts)
        let numberRegex = try? NSRegularExpression(pattern: "\\d+", options: [])
        let numberMatches = numberRegex?.numberOfMatches(in: sentence, options: [], range: NSRange(location: 0, length: sentence.count)) ?? 0
        boost += Double(numberMatches) * 0.05
        
        // Boost sentences that start with important words
        let importantStarters = ["however", "therefore", "consequently", "importantly", "notably", "significantly"]
        let lowercaseSentence = sentence.lowercased()
        for starter in importantStarters {
            if lowercaseSentence.hasPrefix(starter) {
                boost += 0.15
                break
            }
        }
        
        return boost
    }
    
    private func calculateLengthPenalty(sentence: String) -> Double {
        let wordCount = sentence.split(separator: " ").count
        
        // Optimal sentence length for summaries is around 15-25 words
        let optimalLength = 20.0
        let lengthDifference = abs(Double(wordCount) - optimalLength)
        
        // Apply penalty that increases with distance from optimal length
        let penalty = max(0.5, 1.0 - (lengthDifference / optimalLength) * 0.5)
        
        return penalty
    }
    
    private func selectTopSentences(_ rankedSentences: [(String, Double)], for length: SummaryLength) -> [String] {
        let targetWordCount = length.targetWordCount
        let maxWordCount = length.maxWordCount
        
        var selectedSentences: [String] = []
        var currentWordCount = 0
        
        for (sentence, _) in rankedSentences {
            let sentenceWordCount = sentence.split(separator: " ").count
            
            // Check if adding this sentence would exceed the maximum
            if currentWordCount + sentenceWordCount > maxWordCount {
                break
            }
            
            selectedSentences.append(sentence)
            currentWordCount += sentenceWordCount
            
            // Stop if we've reached a good target length
            if currentWordCount >= targetWordCount {
                break
            }
        }
        
        // Ensure we have at least one sentence
        if selectedSentences.isEmpty && !rankedSentences.isEmpty {
            selectedSentences.append(rankedSentences[0].0)
        }
        
        return selectedSentences
    }
    
    private func formatSummary(_ sentences: [String], type: SummaryType) -> String {
        guard !sentences.isEmpty else {
            return "No summary could be generated."
        }
        
        switch type {
        case .brief, .detailed:
            // For brief and detailed, just join sentences with proper spacing
            return sentences.joined(separator: " ")
            
        case .bulletPoints:
            // Format as bullet points
            return sentences.map { "• \($0)" }.joined(separator: "\n")
            
        case .keyInsights:
            // Format as numbered insights
            return sentences.enumerated().map { index, sentence in
                "\(index + 1). \(sentence)"
            }.joined(separator: "\n")
        }
    }
    
    private func calculateConfidence(
        selectedSentences: [String],
        totalSentences: Int,
        originalWordCount: Int
    ) -> Double {
        guard !selectedSentences.isEmpty && totalSentences > 0 else {
            return 0.0
        }
        
        // Base confidence starts at 0.6 for on-device processing
        var confidence = 0.6
        
        // Boost confidence based on sentence coverage
        let coverageRatio = Double(selectedSentences.count) / Double(totalSentences)
        confidence += coverageRatio * 0.2
        
        // Boost confidence based on word coverage
        let summaryWordCount = selectedSentences.joined(separator: " ").split(separator: " ").count
        let compressionRatio = Double(summaryWordCount) / Double(originalWordCount)
        
        // Optimal compression ratio is around 0.1-0.3
        if compressionRatio >= 0.1 && compressionRatio <= 0.3 {
            confidence += 0.1
        }
        
        // Cap confidence at 0.8 for on-device processing
        return min(confidence, 0.8)
    }
}

// MARK: - Extensions

extension OnDeviceAIService {
    
    /// Provides a quick quality assessment of the input text for summarization
    func assessTextQuality(_ text: String) -> TextQualityAssessment {
        let sentences = extractSentences(from: text)
        let wordCount = text.split(separator: " ").count
        
        var quality: TextQuality = .good
        var issues: [String] = []
        
        // Check word count
        if wordCount < 50 {
            quality = .poor
            issues.append("Text too short for effective summarization")
        } else if wordCount < 100 {
            quality = .fair
            issues.append("Short text may result in limited summary")
        }
        
        // Check sentence count
        if sentences.count < 3 {
            quality = .poor
            issues.append("Too few sentences for effective summarization")
        }
        
        // Check average sentence length
        let avgSentenceLength = sentences.isEmpty ? 0 : sentences.map { $0.count }.reduce(0, +) / sentences.count
        if avgSentenceLength < 20 {
            quality = quality == .good ? .fair : quality
            issues.append("Very short sentences may affect summary quality")
        }
        
        return TextQualityAssessment(
            quality: quality,
            wordCount: wordCount,
            sentenceCount: sentences.count,
            averageSentenceLength: avgSentenceLength,
            issues: issues
        )
    }
}

// MARK: - Supporting Types

enum TextQuality {
    case excellent
    case good
    case fair
    case poor
    
    var displayName: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        }
    }
    
    var color: String {
        switch self {
        case .excellent: return "green"
        case .good: return "blue"
        case .fair: return "orange"
        case .poor: return "red"
        }
    }
}

struct TextQualityAssessment {
    let quality: TextQuality
    let wordCount: Int
    let sentenceCount: Int
    let averageSentenceLength: Int
    let issues: [String]
    
    var canSummarize: Bool {
        return quality != .poor && wordCount >= 50
    }
    
    var recommendedProvider: AIProvider {
        switch quality {
        case .excellent, .good:
            return .openAI // High quality text benefits from advanced AI
        case .fair, .poor:
            return .onDevice // Lower quality text may work better with extractive summarization
        }
    }
}