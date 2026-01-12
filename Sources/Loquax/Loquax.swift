//
//  Loquax.swift
//  Loquax
//
//  Created by renshi-a on 2026/01/10.
//

import AVFoundation
import Foundation
import Starscream

public struct AudioTranscription: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let text: String
    init(id: UUID, text: String) {
        self.id = id
        self.text = text
    }
}

public enum BlockingStream {
    case all
    case threshold(Int)
}

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
    private var playerNode: AVAudioPlayerNode?
    private var isPlaying: Bool = false
    private var currentVolume: Float = 0.8
    
    // Stream
    public var inputAudioStream: AsyncStream<AudioTranscription>?
    public var outputAudioStream: AsyncStream<AudioTranscription>?
    public var usageMetadataStream: AsyncStream<UsageMetadata>?
    
    private var inputAudioContinuation: AsyncStream<AudioTranscription>.Continuation?
    private var outputAudioContinuation: AsyncStream<AudioTranscription>.Continuation?
    private var usageContinuation: AsyncStream<UsageMetadata>.Continuation?
    
    private var isContinuingInput: Bool = false
    private var inputId: UUID?
    private var isContinuingOutput: Bool = false
    private var outputId: UUID?
    
    private let blocking: BlockingStream
    
    public init(
        model: SupportedAIModel,
        needTranscription: Bool = false,
        blocking: BlockingStream = .all
    ) {
        var responseModalities = [model.responseModalities]
        let bidiSetup = BidiGenerateContentSetup(
            model: model,
            generationConfig: .init(responseModalities: responseModalities),
            inputAudioTranscription: needTranscription ? .init() : nil,
            outputAudioTranscription: needTranscription ? .init() : nil
        )
        self.setup = .init(setup: bidiSetup)
        self.blocking = blocking
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
        
        let (inputSteam, inputContinuation) = AsyncStream<AudioTranscription>.makeStream()
        self.inputAudioStream = inputSteam
        self.inputAudioContinuation = inputContinuation
        
        let (outputSteam, outputContinuation) = AsyncStream<AudioTranscription>.makeStream()
        self.outputAudioStream = outputSteam
        self.outputAudioContinuation = outputContinuation
        
        let (usageSteam, usageContinuation) = AsyncStream<UsageMetadata>.makeStream()
        self.usageMetadataStream = usageSteam
        self.usageContinuation = usageContinuation
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

            if let usageMetadata = response.usageMetadata {
                usageContinuation?.yield(usageMetadata)
            }
            
            if let serverContent = response.serverContent {
                if serverContent.modelTurn != nil {
                    turns.append(response)
                }
                
                if let input = serverContent.inputTranscription?.text {
                    if !isContinuingInput {
                        isContinuingInput = true
                        self.inputId = .init()
                    }
                    
                    if isContinuingOutput { // 出力から入力へ切り替わったとき
                        isContinuingOutput = false
                        guard let outputId else {
                            assert(false)
                            return
                        }
                        outputAudioContinuation?.yield(.init(id: outputId, text: ""))
                        self.outputId = nil
                    }
                    
                    guard let inputId else {
                        assert(false)
                        return
                    }
                    inputAudioContinuation?.yield(.init(id: inputId, text: input))
                }
                
                if let output = serverContent.outputTranscription?.text {
                    if !isContinuingOutput {
                        isContinuingOutput = true
                        self.outputId = .init()
                    }
                    
                    if isContinuingInput {
                        isContinuingInput = false
                        guard let inputId else {
                            assert(false)
                            return
                        }
                        inputAudioContinuation?.yield(.init(id: inputId, text: ""))
                        self.inputId = nil
                    }
                    
                    guard let outputId else {
                        assert(false)
                        return
                    }
                    outputAudioContinuation?.yield(.init(id: outputId, text: output))
                }
                
                switch blocking {
                case let .threshold(threshold):
                    if turns.count >= threshold {
                        flushMessages()
                    }
                    
                case .all:
                    return
                }

                if serverContent.turnComplete != nil {
                    isContinuingInput = false
                    isContinuingOutput = false
                    inputId = nil
                    outputId = nil
                    flushMessages()
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
        if let audioEngine {
            if audioEngine.isRunning {
                audioEngine.stop()
            }
            audioEngine.inputNode.removeTap(onBus: 0)
            self.audioEngine = nil
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
        let playerNode = AVAudioPlayerNode()
        let mixer = audioEngine.mainMixerNode
        
        audioEngine.attach(playerNode)
        let playerFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24000,
            channels: 1,
            interleaved: false
        )
        audioEngine.connect(playerNode, to: mixer, format: playerFormat)
        self.playerNode = playerNode
        
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
    }
    
    func flushMessages() {
        var audioDataArray: [String] = []
        for turn in turns {
            turn.serverContent?.modelTurn?.parts.forEach { part in
                if let inlineData = part.inlineData,
                   inlineData.mimeType.contains("audio") {
                    audioDataArray.append(inlineData.data)
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
        turns.removeAll()
    }
    
    private func playAudioWithVolume(_ data: Data, _ volume: Float) {
        let pcmData = skipWAVHeader(data)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24000,
            channels: 1,
            interleaved: false)
        
        guard let format else {
            assert(false)
            return
        }
        scheduleAudioBuffer(pcmData: pcmData, format: format, volume: volume)
    }
    
    private func scheduleAudioBuffer(pcmData: Data, format: AVAudioFormat, volume: Float) {
        guard let playerNode = playerNode, let audioEngine = audioEngine else {
            return
        }

        let frameCount = AVAudioFrameCount(pcmData.count / 2)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return
        }

        buffer.frameLength = frameCount

        pcmData.withUnsafeBytes { bytes in
            let int16Pointer = bytes.bindMemory(to: Int16.self)
            let channelData = buffer.floatChannelData![0]
            for i in 0..<Int(frameCount) {
                channelData[i] = Float(int16Pointer[i]) / 32768.0
            }
        }

        setVolume(volume)

        if !playerNode.isPlaying {
            playerNode.play()
            isPlaying = true
        }

        playerNode.scheduleBuffer(buffer) { [weak self] in
            guard let self = self else { return }
            self.checkPlayingStatus()
        }
    }
    
    private func checkPlayingStatus() {
        if !(playerNode?.isPlaying ?? false) {
            isPlaying = false
        }
    }
    
    private func setVolume(_ volume: Float) {
        currentVolume = min(1.0, max(0.0, volume))
        playerNode?.volume = currentVolume
    }
    
    private func skipWAVHeader(_ data: Data) -> Data {
        guard data.count > 44,
              data.subdata(in: 0..<4) == "RIFF".data(using: .ascii),
              data.subdata(in: 8..<12) == "WAVE".data(using: .ascii) else {
            return data
        }
        return data.subdata(in: 44..<data.count)
    }
}
