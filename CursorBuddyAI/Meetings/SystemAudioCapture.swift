//
//  SystemAudioCapture.swift
//  CursorBuddyAI
//
//  System audio capture using ScreenCaptureKit
//

import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import os.log

/// Handles system audio capture via ScreenCaptureKit
class SystemAudioCapture: NSObject, SCStreamOutput {
    private let outputURL: URL
    private var audioFile: AVAudioFile?
    private var audioFormat: AVAudioFormat?
    
    init(outputURL: URL) {
        self.outputURL = outputURL
        super.init()
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Only process audio buffers
        guard type == .audio else { return }
        
        // Get audio format
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return
        }
        
        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        guard let basicDescription = asbd?.pointee else {
            return
        }
        
        // Create audio format if needed
        if audioFormat == nil {
            audioFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: basicDescription.mSampleRate,
                channels: basicDescription.mChannelsPerFrame,
                interleaved: false
            )
        }
        
        guard let format = audioFormat else { return }
        
        // Create audio file if needed
        if audioFile == nil {
            do {
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: format.sampleRate,
                    AVNumberOfChannelsKey: format.channelCount,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                ]
                audioFile = try AVAudioFile(forWriting: outputURL, settings: settings)
                Log.app.info("✓ System audio file created")
            } catch {
                Log.app.error("Failed to create system audio file: \(error)")
                return
            }
        }
        
        // Convert CMSampleBuffer to AVAudioPCMBuffer
        var audioBufferList = AudioBufferList()
        var blockBuffer: CMBlockBuffer?
        
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        guard status == noErr else {
            return
        }
        
        let numFrames = CMSampleBufferGetNumSamples(sampleBuffer)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(numFrames)) else {
            return
        }
        
        buffer.frameLength = AVAudioFrameCount(numFrames)
        
        // Copy audio data
        let bufferListPointer = UnsafeMutableAudioBufferListPointer(&audioBufferList)
        for (index, sourceBuffer) in bufferListPointer.enumerated() where index < Int(format.channelCount) {
            guard let sourceData = sourceBuffer.mData,
                  let destData = buffer.floatChannelData?[index] else {
                continue
            }
            memcpy(destData, sourceData, Int(sourceBuffer.mDataByteSize))
        }
        
        // Write to file
        do {
            try audioFile?.write(from: buffer)
        } catch {
            Log.app.error("Failed to write system audio: \(error)")
        }
    }
}
