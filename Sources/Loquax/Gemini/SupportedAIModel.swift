//
//  SupportedAIModel.swift
//  Loquax
//
//  Created by renshi-a on 2026/01/10.
//

import Foundation

public enum SupportedAIModel: Sendable {
    case gemini25flashNativeAudioPreview092025
    case gemini25flashNativeAudioPreview122025

    public var modelName: String {
        switch self {
        case .gemini25flashNativeAudioPreview092025:
            return "gemini-2.5-flash-native-audio-preview-09-2025"
        case .gemini25flashNativeAudioPreview122025:
            return "gemini-2.5-flash-native-audio-preview-12-2025"
        }
    }

    public var responseModalities: String {
        switch self {
        case .gemini25flashNativeAudioPreview092025:
            return "AUDIO"

        case .gemini25flashNativeAudioPreview122025:
            return "AUDIO"
        }
    }
}
