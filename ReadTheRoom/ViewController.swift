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
    
    @IBOutlet weak var textView: UITextView!
    // let soundClassifier = ReadTheRoomSoundClassifier()
    let soundClassifier = ReadTheRoom_1_1()
    
    let engine = AVAudioEngine()
    var inputFormat: AVAudioFormat!
    var analyzer: SNAudioStreamAnalyzer!
    
    var resultsObserver = ReadTheRoomResults()

    let analysisQueue = DispatchQueue(label: "com.apple.AnalysisQueue")
    
    var capturingAudio = false
    
    var lastClassification: String!
    var lastLabelSent = Date()
    var lastVolume: Double!
    
    var recognitionTask: SFSpeechRecognitionTask!
    let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
    
    var lastSpokenWord = ""
    
    

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        resultsObserver.delegate = self
        inputFormat = engine.inputNode.inputFormat(forBus: 0)
        analyzer = SNAudioStreamAnalyzer(format: inputFormat)
//        let audioSession = AVAudioSession.sharedInstance()
//        try! audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
//        try! audioSession.setActive(true, options: .notifyOthersOnDeactivation)
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
       // recognitionRequest.requiresOnDeviceRecognition = true
      //  let recordingFormat = engine.inputNode.outputFormat(forBus: 1)
//        engine.inputNode.installTap(onBus: 1, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
//            self.recognitionRequest.append(buffer)
//        }
        
        recognitionTask = SFSpeechRecognizer()!.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                self.textView.text = result.bestTranscription.formattedString
            }

            if error != nil {
                print(error?.localizedDescription as Any)
            }
        }
        
    }

    private func stopCapturingSpeech() {
        engine.inputNode.removeTap(onBus: 1)
        startCapturingAudio()
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
            // 4
            let channelDataValueArray = stride(from: 0,
                                               to: Int(buffer.frameLength),
                                               by: buffer.stride).map{ channelDataValue[$0] }
            // 5
            let rms = sqrt(channelDataValueArray.map{ $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
            // 6
            let avgPower = 20 * log10(rms)
            // 7
           // let meterLevel = self.scaledPower(power: avgPower)
            // Analyze the current audio buffer.
            
           // print(avgPower)
            self.recognitionRequest.append(buffer)
            if avgPower > -30.0 {
                self.analysisQueue.async {
                    self.analyzer.analyze(buffer, atAudioFramePosition: time.sampleTime)
                    
                }
            }
        }
        
       
    }
    
    private func stopCapturingAudio() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
    }
    
    // MARK: IBActions
    @IBAction func pressedTheButton(_ sender: Any) {
        if capturingAudio {
          //  stopCapturingAudio()
            view.backgroundColor = .white
            engine.stop()
        } else {
            startCapturingAudio()
            startCapturingSpeech()
            view.backgroundColor = .green
          
            
        }
        capturingAudio = !capturingAudio
    }
    
    func sendLabel(copy: String, confidence: Double, isSound: Bool) {
//        guard copy != lastClassification, lastLabelSent.addingTimeInterval(5) < Date() else {
//            return
//        }
        guard copy != "silence" else { return }
        guard copy != "speech" else { return }
//        guard copy != "speech" else {
//            startCapturingSpeech()
//            return
//        }
        
     //   stopCapturingSpeech()
        var newCopy = copy
        if isSound {
            newCopy = "[\(copy)]"
        }
        DispatchQueue.main.async {
            let label = UILabel(frame: CGRect(x: self.determineX(), y: self.view.frame.size.height - 50, width: 300, height: 50))
            label.text = newCopy
            label.font = .systemFont(ofSize: 40)
            label.textColor = .black
            label.textAlignment = .center
            
            self.view.addSubview(label)
        
            UIView.animate(withDuration: 5.0, animations: {
                label.frame = CGRect(x: label.frame.origin.x, y: -100, width: label.frame.size.width, height: label.frame.size.height)
            }) { (done) in
                label.removeFromSuperview()
            }
        }
        // Pick random X
        lastClassification = copy
        lastLabelSent = Date()
    }
    
    func determineX() -> CGFloat {
        return (self.view.frame.size.width / 2) - 80
    }
}

extension ViewController: ReadTheRoomResultsDelegate {
    func soundAnalyzed(identifier: String, confidence: Double) {
        sendLabel(copy: identifier, confidence: confidence, isSound: true)
    }
    
    
}

class ReadTheRoomResults: NSObject, SNResultsObserving {
    
    var delegate: ReadTheRoomResultsDelegate?
    
    func request(_ request: SNRequest, didProduce result: SNResult) {
        // Get the top classification.
        guard let result = result as? SNClassificationResult,
            let classification = result.classifications.first else { return }
        
        // Determine the time of this result.
       // let formattedTime = String(format: "%.2f", result.timeRange.start.seconds)
       // print("Analysis result for audio at time: \(formattedTime)")
        
        let confidence = classification.confidence * 100.0
        let percent = String(format: "%.2f%%", confidence)
        
        if confidence > 90 {
        // Print the result as Instrument: percentage confidence.
           // print("\(classification.identifier): \(percent) confidence.\n")
            delegate?.soundAnalyzed(identifier: classification.identifier, confidence: confidence)
        }
    }
    
    func request(_ request: SNRequest, didFailWithError error: Error) {
        print("The the analysis failed: \(error.localizedDescription)")
    }
    
    func requestDidComplete(_ request: SNRequest) {
        print("The request completed successfully!")
    }
}

protocol ReadTheRoomResultsDelegate {
    func soundAnalyzed(identifier: String, confidence: Double)
}

