//
//  GeminiLiveSetup.swift
//  Loquax
//
//  Created by renshi-a on 2026/01/10.
//

import Foundation

struct GeminiLiveSetup: Encodable {
    public var setup: BidiGenerateContentSetup
    
    public init(model: SupportedAIModel) {
        let config = GenerationConfig(responseModalities: [model.responseModalities])
        self.setup = .init(model: model, generationConfig: config)
    }
    
    public init(setup: BidiGenerateContentSetup) {
        self.setup = setup
    }
}

struct BidiGenerateContentSetup: Encodable {
    public let model: String
    public let generationConfig: GenerationConfig?
    public let systemInstruction: SystemInstruction?
    public let tools: [Tool]?
    public let inputAudioTranscription: AudioTranscriptionConfig?
    public let outputAudioTranscription: AudioTranscriptionConfig?
    
    public init(
        model: SupportedAIModel,
        generationConfig: GenerationConfig? = nil,
        systemInstruction: SystemInstruction? = nil,
        tools: [Tool]? = nil,
        inputAudioTranscription: AudioTranscriptionConfig? = nil,
        outputAudioTranscription: AudioTranscriptionConfig? = nil
    ) {
        self.model = "models/\(model.modelName)"
        self.generationConfig = generationConfig
        self.systemInstruction = systemInstruction
        self.tools = tools
        self.inputAudioTranscription = inputAudioTranscription
        self.outputAudioTranscription = outputAudioTranscription
    }
}

public struct AudioTranscriptionConfig: Encodable {
    public init() {}
}

struct GenerationConfig: Encodable {
    public let responseModalities: [String]?
    public let maxOutputTokens: Int?
    public let temperature: Float?
    public let topP: Float?
    public let topK: Int?
    public let candidateCount: Int?
    public let frequencyPenalty: Float?
    public let presencePenalty: Float?
    public let speechConfig: SpeechConfig?
    
    public init(
        responseModalities: [String]? = ["TEXT"],
        maxOutputTokens: Int? = nil,
        temperature: Float? = nil,
        topP: Float? = nil,
        topK: Int? = nil,
        candidateCount: Int? = nil,
        frequencyPenalty: Float? = nil,
        presencePenalty: Float? = nil,
        speechConfig: SpeechConfig? = nil
    ) {
        self.responseModalities = responseModalities
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.candidateCount = candidateCount
        self.frequencyPenalty = frequencyPenalty
        self.presencePenalty = presencePenalty
        self.speechConfig = speechConfig
    }
}

struct SpeechConfig: Encodable {
    public let languageCode: String?
    
    
    public init(languageCode: String? = "ja-JP") {
        self.languageCode = languageCode
    }
    
    enum CodingKeys: String, CodingKey {
        case languageCode = "language_code"
    }
}


struct SystemInstruction: Encodable {
    public let parts: [Part]
    
    public init(text: String) {
        self.parts = [Part(text: text)]
    }
    
    public struct Part: Encodable {
        public let text: String
    }
}

struct Tool: Encodable {
    public let functionDeclarations: [FunctionDeclaration]
    
    public init(functionDeclarations: [FunctionDeclaration]) {
        self.functionDeclarations = functionDeclarations
    }
    
    enum CodingKeys: String, CodingKey {
        case functionDeclarations = "function_declarations"
    }
}

struct FunctionDeclaration: Encodable {
    public let name: String
    public let description: String
    public let parameters: Parameters
    
    public init(name: String, description: String, parameters: Parameters) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

struct Parameters: Encodable {
    public let type: String
    public let properties: [String: Property]
    public let required: [String]?
    
    public init(
        type: String = "OBJECT",
        properties: [String: Property],
        required: [String]? = nil
    ) {
        self.type = type
        self.properties = properties
        self.required = required
    }
    
    public struct Property: Encodable {
        public let type: String
        public let description: String
        public init(type: String, description: String) {
            self.type = type
            self.description = description
        }
    }
}

