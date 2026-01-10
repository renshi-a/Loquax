//
//  AudioDataProcessor.swift
//  Loquax
//
//  Created by renshi-a on 2026/01/11.
//

import Foundation

struct AudioDataProcessor {

    static func convertPCMToWAV(
        pcmData: Data,
        sampleRate: UInt32 = 24000,
        channels: UInt16 = 1,
        bitsPerSample: UInt16 = 16
    ) -> Data {
        let bytesPerSample = bitsPerSample / 8
        let byteRate = sampleRate * UInt32(channels * bytesPerSample)
        let blockAlign = channels * bytesPerSample

        var wavData = Data()

        wavData.append("RIFF".data(using: .ascii)!)
        let fileSize = UInt32(36 + pcmData.count)
        wavData.append(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        wavData.append("WAVE".data(using: .ascii)!)

        wavData.append("fmt ".data(using: .ascii)!)
        let fmtChunkSize: UInt32 = 16
        wavData.append(withUnsafeBytes(of: fmtChunkSize.littleEndian) { Data($0) })
        let audioFormat: UInt16 = 1
        wavData.append(withUnsafeBytes(of: audioFormat.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: channels.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })

        wavData.append("data".data(using: .ascii)!)
        let dataSize = UInt32(pcmData.count)
        wavData.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        wavData.append(pcmData)

        return wavData
    }

    static func combineAndConvertPCMToWAV(
        base64DataArray: [String],
        sampleRate: UInt32 = 24000,
        channels: UInt16 = 1,
        bitsPerSample: UInt16 = 16
    ) -> Data? {
        var combinedPCMData = Data()

        for base64Data in base64DataArray {
            guard let pcmData = Data(base64Encoded: base64Data) else {
                continue
            }
            combinedPCMData.append(pcmData)
        }

        guard !combinedPCMData.isEmpty else {
            return nil
        }

        return convertPCMToWAV(
            pcmData: combinedPCMData,
            sampleRate: sampleRate,
            channels: channels,
            bitsPerSample: bitsPerSample
        )
    }
}
