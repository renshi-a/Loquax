//
//  GeminiLiveResponse.swift
//  Loquax
//
//  Created by renshi-a on 2026/01/10.
//

import Foundation

struct GeminiLiveResponse: Decodable, Sendable {
    public let setupComplete: SetupComplete?
    public let serverContent: ServerContent?

    enum CodingKeys: String, CodingKey {
        case setupComplete = "setupComplete"
        case serverContent = "serverContent"
    }

    public struct SetupComplete: Decodable, Sendable {}

    public struct ServerContent: Decodable, Sendable {
        public let modelTurn: ModelTurn?
        public let turnComplete: Bool?
        public let inputTranscription: BidiGenerateContentTranscription?
        public let outputTranscription: BidiGenerateContentTranscription?

        enum CodingKeys: String, CodingKey {
            case modelTurn = "modelTurn"
            case turnComplete = "turnComplete"
            case inputTranscription = "inputTranscription"
            case outputTranscription = "outputTranscription"
        }

        public struct ModelTurn: Decodable, Sendable {
            public let parts: [Part]

            public struct Part: Decodable, Sendable {
                public let text: String?
                public let inlineData: InlineData?

                enum CodingKeys: String, CodingKey {
                    case text
                    case inlineData = "inlineData"
                }

                public struct InlineData: Decodable, Sendable {
                    public let mimeType: String
                    public let data: String 

                    enum CodingKeys: String, CodingKey {
                        case mimeType = "mimeType"
                        case data
                    }
                }
            }
        }
        
        public struct BidiGenerateContentTranscription: Decodable, Sendable {
            public let text: String
            enum CodingKeys: String, CodingKey {
                case text
            }
        }
    }
}
