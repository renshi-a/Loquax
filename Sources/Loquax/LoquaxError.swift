//
//  LoquaxError.swift
//  Loquax
//
//  Created by renshi-a on 2026/01/10.
//

import Foundation

public enum LoquaxError: Error {
    case invalidURL
    case notConnected
    case jsonSerializationFailed
    case setupNotFound
    case connectionClosed(reason: String, code: UInt16)
    case connectionCancelled
    case peerClosed
    case setVoiceProcessingEnabledFaield
    case createAVAudioFormatFailed
    case createAVAudioConverterFailed
    case invalidSampleFormat
    case unknownError
}
