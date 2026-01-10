//
//  Loquax.swift
//  Loquax
//
//  Created by renshi-a on 2026/01/10.
//

import AVFoundation
import Foundation
import Starscream

public class Loquax: WebSocketDelegate {
    enum Const {
        static let SERVICE_URL = """
        wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent
        """
    }
    
    // WebCocket
    private var socket: WebSocket?
    private var isConnected = false
    private var hasSetupCompleted = false
    private var turns: [GeminiLiveResponse] = []
    private let setup: GeminiLiveSetup
    
    // Audio
    private var audioEngine: AVAudioEngine?
    private var audioPlayer: AVAudioPlayer?
    
    public init(model: SupportedAIModel) {
        self.setup = .init(model: model)
    }
    
    public func connect(
        apiKey: String,
        bundleIdentifier: String? = nil
    ) throws {
        let urlString = Const.SERVICE_URL + "?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw LoquaxError.invalidURL
        }
        
        let socket = WebSocket(request: URLRequest(url: url))
        if let bundleIdentifier = bundleIdentifier {
            socket.request.addValue(
                bundleIdentifier,
                forHTTPHeaderField: "X-Ios-Bundle-Identifier"
            )
        }
        socket.delegate = self
        socket.connect()
        
        self.socket = socket
    }
    
    public func disconnect() {
        self.socket?.disconnect()
        self.socket = nil
        self.isConnected = false
        self.hasSetupCompleted = false
        stopAudioEngine()
    }
    
    public func startLiveChat() async throws {
        guard isConnected else {
            throw LoquaxError.notConnected
        }
        
        let hasAudioAccess: Bool
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            hasAudioAccess = true
        } else {
            hasAudioAccess = await requestAudioAccess()
        }
        
        guard hasAudioAccess else {
            return
        }
        
        stopAudioEngine()
        try configureAudioSession()
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        try startAudioStream()
    }
}

extension Loquax {
    public func didReceive(event: Starscream.WebSocketEvent, client: Starscream.WebSocketClient) {
        switch event {
        case .connected(_):
            self.isConnected = true
            sendSetupMessage()

        case .binary(let data):
            guard let response = try? JSONDecoder().decode(GeminiLiveResponse.self, from: data) else {
                return
            }
            
            if response.setupComplete != nil, !hasSetupCompleted {
                hasSetupCompleted = true
            }
            
            guard hasSetupCompleted else { return }

            if let serverContent = response.serverContent {
                if serverContent.modelTurn != nil {
                    turns.append(response)
                }

                if serverContent.turnComplete != nil {
                    onTurnCompleted()
                    turns.removeAll()
                }
            }

        case .disconnected, .cancelled, .peerClosed:
            disconnect()
            
        default:
            break
        }
    }
    
    private func sendSetupMessage() {
        guard let socket else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .withoutEscapingSlashes
            let data = try encoder.encode(setup)
            guard let message = String(data: data, encoding: .utf8) else {
                return
            }
            socket.write(string: message)
        } catch {
            print(error)
        }
    }
    
    private func sendAudio(_ audioData: String) {
        let input = BidiGenerateContentRealtimeInput.audioInput(audioData: audioData)
        sendRealtimeInput(.init(realtimeInput: input))
    }
    
    private func sendRealtimeInput(
        _ realtimeInput: GeminiLiveRealtimeInput
    ) {
        guard let socket else { return }
        do {
            let data = try JSONEncoder().encode(realtimeInput)
            guard let message = String(data: data, encoding: .utf8) else {
                return
            }
            socket.write(string: message)
        } catch {
            print(error)
        }
    }
}

private extension Loquax {
    private func requestAudioAccess() async -> Bool {
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    private func stopAudioEngine() {
        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
            engine.inputNode.removeTap(onBus: 0)
            audioEngine = nil
        }
    }
    
    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
         )
        try audioSession.setPreferredSampleRate(24000)
        try audioSession.setPreferredIOBufferDuration(0.02)
        try audioSession.setActive(true)
    }
    
    func startAudioStream() throws {
        let audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        
        do {
            try inputNode.setVoiceProcessingEnabled(true)
        } catch {
            throw LoquaxError.setVoiceProcessingEnabledFaield
        }
        
        let duckingConfig = AVAudioVoiceProcessingOtherAudioDuckingConfiguration(
            enableAdvancedDucking: false,
            duckingLevel: .min
        )
        inputNode.voiceProcessingOtherAudioDuckingConfiguration = duckingConfig
        
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw LoquaxError.invalidSampleFormat
        }
        
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw LoquaxError.createAVAudioFormatFailed
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            guard buffer.frameLength > 0 else { return }
            
            let count = Double(buffer.frameLength) * targetFormat.sampleRate / inputFormat.sampleRate
            let frameCount = AVAudioFrameCount(count)
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat, frameCapacity: frameCount
            ) else { return }
            
            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            if status == .haveData && error == nil,
               let channelData = convertedBuffer.int16ChannelData {
                let frameLength = Int(convertedBuffer.frameLength)
                let audioData = Data(bytes: channelData[0], count: frameLength * 2)
                self.sendAudio(audioData.base64EncodedString())
            }
        }
        
        audioEngine.prepare()
        if !audioEngine.isRunning {
            try audioEngine.start()
        }
        
        self.audioEngine = audioEngine
        
        print("Loquax startAudioStream end")
    }
    
    func onTurnCompleted() {
        var message: String = ""
        var audioDataArray: [String] = []
        for turn in turns {
            turn.serverContent?.modelTurn?.parts.forEach { part in
                if let inlineData = part.inlineData,
                   inlineData.mimeType.contains("audio") {
                    audioDataArray.append(inlineData.data)
                }
                if let text = part.text {
                    message.append(text)
                }
            }
        }
        
        if !audioDataArray.isEmpty {
            if let combinedAudioData = AudioDataProcessor.combineAndConvertPCMToWAV(
                base64DataArray: audioDataArray,
                sampleRate: 24000,
                channels: 1,
                bitsPerSample: 16
            ) {
                playAudioWithVolume(combinedAudioData, 0.9)
            }
        }
    }
    
    private func playAudioWithVolume(_ data: Data, _ volume: Float) {
        self.audioPlayer?.stop()
        self.audioPlayer = try? AVAudioPlayer(data: data)
        self.audioPlayer?.volume = min(1.0, max(0.0, volume))
        self.audioPlayer?.prepareToPlay()
        self.audioPlayer?.play()
    }
}
