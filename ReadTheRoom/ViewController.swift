//
//  ViewController.swift
//  ReadTheRoom
//
//  Created by Weston Chambers on 6/15/19.
//  Copyright © 2019 Weston Chambers. All rights reserved.
//

import UIKit
import AVKit
import SoundAnalysis
import Speech

class ViewController: UIViewController {
    
    // MARK: IBOutlets
    @IBOutlet weak var textView: UITextView!
    
    // MARK: Sound classification
    let soundClassifier = ReadTheRoom()
    let engine = AVAudioEngine()
    var inputFormat: AVAudioFormat!
    var analyzer: SNAudioStreamAnalyzer!
    var resultsObserver = ReadTheRoomResults()
    let analysisQueue = DispatchQueue(label: "com.apple.AnalysisQueue")

    // MARK: Speech recognition
    var recognitionTask: SFSpeechRecognitionTask!
    let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

    override func viewDidLoad() {
        super.viewDidLoad()
        resultsObserver.delegate = self
        inputFormat = engine.inputNode.inputFormat(forBus: 0)
        analyzer = SNAudioStreamAnalyzer(format: inputFormat)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startCapturingAudio()
        startCapturingSpeech()
        
        do {
            try engine.start()
        } catch {
            print("Failed to start your engine")
        }
    }
    
    private func startCapturingSpeech() {
        recognitionRequest.shouldReportPartialResults = true
        recognitionTask = SFSpeechRecognizer()!.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                self.textView.text = result.bestTranscription.formattedString
            }

            if error != nil {
                print(error?.localizedDescription as Any)
            }
        }
    }
    
    private func startCapturingAudio() {
        do {
            let request = try SNClassifySoundRequest(mlModel: soundClassifier.model)
            try analyzer.add(request, withObserver: resultsObserver)
        } catch {
            print("Unable to prepare request: \(error.localizedDescription)")
            return
        }
       
        engine.inputNode.installTap(onBus: 0,
                                         bufferSize: 8192, // 8k buffer
        format: inputFormat) { buffer, time in
            let channelDataValue = buffer.floatChannelData!.pointee
            let channelDataValueArray = stride(from: 0,
                                               to: Int(buffer.frameLength),
                                               by: buffer.stride).map{ channelDataValue[$0] }

            let rms = sqrt(channelDataValueArray.map{ $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
            let avgPower = 20 * log10(rms)
            self.recognitionRequest.append(buffer)
            if avgPower > -30.0 {
                self.analysisQueue.async {
                    self.analyzer.analyze(buffer, atAudioFramePosition: time.sampleTime)
                }
            }
        }
    }

    func createAndAnimateSoundTypeLabel(soundType: String) {
        guard soundType != "silence", soundType != "speech" else { return }
        DispatchQueue.main.async {
            let label = UILabel(frame: CGRect(x: (self.view.frame.size.width / 2) - 150, y: self.view.frame.size.height - 50, width: 300, height: 50))
            label.text = "[\(soundType)]"
            label.font = .systemFont(ofSize: 40)
            label.textAlignment = .center
            
            self.view.addSubview(label)

            UIView.animate(withDuration: 5.0, animations: {
                label.frame = CGRect(x: label.frame.origin.x, y: -100, width: label.frame.size.width, height: label.frame.size.height)
            }) { (done) in
                label.removeFromSuperview()
            }
        }
    }
}

extension ViewController: ReadTheRoomResultsDelegate {
    func determinedSoundType(identifier: String, confidence: Double) {
        createAndAnimateSoundTypeLabel(soundType: identifier)
    }
}

class ReadTheRoomResults: NSObject, SNResultsObserving {
    var delegate: ReadTheRoomResultsDelegate?
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult,
            let classification = result.classifications.first else { return }

        let confidence = classification.confidence * 100.0
        if confidence > 90 {
            delegate?.determinedSoundType(identifier: classification.identifier, confidence: confidence)
        }
    }
}

protocol ReadTheRoomResultsDelegate {
    func determinedSoundType(identifier: String, confidence: Double)
}

