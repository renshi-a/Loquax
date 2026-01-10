//
//  GeminiLiveRealtimeInput.swift.swift
//  Loquax
//
//  Created by renshi-a on 2026/01/10.
//

import Foundation

struct GeminiLiveRealtimeInput: Encodable {
    public let realtimeInput: BidiGenerateContentRealtimeInput
    enum CodingKeys: String, CodingKey {
        case realtimeInput = "realtimeInput"
    }
}

struct BidiGenerateContentRealtimeInput: Encodable {
    public let audio: Blob?
    public let video: Blob?
    public let text: String?
    public let audioStreamEnd: Bool?
    public let activityStart: ActivityStart?
    public let activityEnd: ActivityEnd?

    public init(
        audio: Blob? = nil,
        video: Blob? = nil,
        text: String? = nil,
        audioStreamEnd: Bool? = nil,
        activityStart: ActivityStart? = nil,
        activityEnd: ActivityEnd? = nil
    ) {
        self.audio = audio
        self.video = video
        self.text = text
        self.audioStreamEnd = audioStreamEnd
        self.activityStart = activityStart
        self.activityEnd = activityEnd
    }

    enum CodingKeys: String, CodingKey {
        case audio
        case video
        case text
        case audioStreamEnd = "audioStreamEnd"
        case activityStart = "activityStart"
        case activityEnd = "activityEnd"
    }
}

extension BidiGenerateContentRealtimeInput {
    public static func audioInput(
        audioData: String,
        mimeType: String = "audio/pcm;rate=16000"
    ) -> BidiGenerateContentRealtimeInput {
        let blob = Blob(mimeType: mimeType, data: audioData)
        return BidiGenerateContentRealtimeInput(audio: blob)
    }
}

struct Blob: Encodable {
    public let mimeType: String
    public let data: String
    
    public init(mimeType: String, data: String) {
        self.mimeType = mimeType
        self.data = data
    }

    enum CodingKeys: String, CodingKey {
        case mimeType = "mimeType"
        case data
    }
}

struct ActivityStart: Encodable {
    public init() {}
}

struct ActivityEnd: Encodable {
    public init() {}
}
