/*
 See LICENSE folder for this sample’s licensing information.
 
 Abstract:
 The root view controller that provides a button to start and stop recording, and which displays the speech recognition results.
 */

import UIKit
import Speech
import AVFoundation

public class ViewController: UIViewController, SFSpeechRecognizerDelegate {
    // MARK: Properties
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private let audioSession = AVAudioSession.sharedInstance()
    
    private let audioEngine = AVAudioEngine()
    
    private let player = AVAudioPlayerNode()
    
    private var speechBuffer: AVAudioPCMBuffer?
    
    @IBOutlet var textView: UITextView!
    
    @IBOutlet var recordButton: UIButton!
    
    // MARK: View Controller Lifecycle
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        // Disable the record buttons until authorization has been granted.
        recordButton.isEnabled = false
    }
    
    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Configure the SFSpeechRecognizer object already
        // stored in a local member variable.
        speechRecognizer.delegate = self
        
        // Asynchronously make the authorization request.
        SFSpeechRecognizer.requestAuthorization { authStatus in
            
            // Divert to the app's main thread so that the UI
            // can be updated.
            OperationQueue.main.addOperation {
                switch authStatus {
                case .authorized:
                    self.recordButton.isEnabled = true
                    
                case .denied:
                    self.recordButton.isEnabled = false
                    self.recordButton.setTitle("User denied access to speech recognition", for: .disabled)
                    
                case .restricted:
                    self.recordButton.isEnabled = false
                    self.recordButton.setTitle("Speech recognition restricted on this device", for: .disabled)
                    
                case .notDetermined:
                    self.recordButton.isEnabled = false
                    self.recordButton.setTitle("Speech recognition not yet authorized", for: .disabled)
                    
                default:
                    self.recordButton.isEnabled = false
                }
            }
        }
        
    }
    
    private func getBuffer(fileURL: URL) -> AVAudioPCMBuffer? {
        let file: AVAudioFile!
        do {
            try file = AVAudioFile(forReading: fileURL)
        } catch {
            print("Could not load file: \(error)")
            return nil
        }
        file.framePosition = 0
        let bufferCapacity = AVAudioFrameCount(file.length)
            + AVAudioFrameCount(file.processingFormat.sampleRate * 0.1) // add 100ms to capacity
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: bufferCapacity) else { return nil }
        do {
            try file.read(into: buffer)
        } catch {
            print("Could not load file into buffer: \(error)")
            return nil
        }
        file.framePosition = 0
        return buffer
    }
    
    // Start listening to the mic sending the data to the voice recognition service
    private func installTap() {
        let recordingFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        audioEngine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
            self.recognitionRequest?.append(buffer)
            
        }
    }
    
    private func startRecording() throws {
        
        // Cancel the previous task if it's running.
        recognitionTask?.cancel()
        self.recognitionTask = nil
        
        // Input and Output audio run through the audioengine with an optional mixer for playback
        let mainMixer = audioEngine.mainMixerNode
        let inputNode = audioEngine.inputNode
        let outputNode = audioEngine.outputNode
        
        // Configure the audio session for playback
        do {
            // Setup duplex playback and recording and switch the default audio output to the loud speaker
            try audioSession.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            // Load up the sample wav file
            let sourceFileURL = Bundle.main.url(forResource: "f8e0a23a3d99d36f32fd7c0d33709b66", withExtension: "wav")!
            let sourceFile = try AVAudioFile(forReading: sourceFileURL)
            let format = sourceFile.processingFormat
            speechBuffer = getBuffer(fileURL: sourceFileURL)
            
            // Link up the audio player to first play through the mixer and then the speaker
            audioEngine.attach(player)
            audioEngine.connect(player, to:mainMixer, format: format)
            audioEngine.connect(mainMixer, to: outputNode, format: format)
        } catch {
            print(error)
        }
        
        // Create and configure the speech recognition request.
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { fatalError("Unable to create a SFSpeechAudioBufferRecognitionRequest object") }
        recognitionRequest.shouldReportPartialResults = true
        
        // Keep speech recognition data on device
        if #available(iOS 13, *) {
            recognitionRequest.requiresOnDeviceRecognition = false
        }
        
        // Create a recognition task for the speech recognition session.
        // Keep a reference to the task so that it can be canceled.
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
            var isFinal = false
            
            if let result = result {
                // Update the text view with the results.
                self.textView.text = result.bestTranscription.formattedString
                isFinal = result.isFinal
                print("Text \(result.bestTranscription.formattedString)")
            }
            
            if error != nil || isFinal {
                // Stop recognizing speech if there is a problem.
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                
                self.recognitionRequest = nil
                self.recognitionTask = nil
                
                self.recordButton.isEnabled = true
                self.recordButton.setTitle("Start Recording", for: [])
            }
        }
        
        // Configure the microphone input.
        installTap()
        
        audioEngine.prepare()
        try audioEngine.start()
        
        // Let the user know to start talking.
        textView.text = "(Go ahead, I'm listening)"
    }
    
    // MARK: SFSpeechRecognizerDelegate
    
    public func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if available {
            recordButton.isEnabled = true
            recordButton.setTitle("Start Recording", for: [])
        } else {
            recordButton.isEnabled = false
            recordButton.setTitle("Recognition Not Available", for: .disabled)
        }
    }
    
    // MARK: Interface Builder actions
    
    @IBAction func recordButtonTapped() {
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
            recordButton.isEnabled = false
            recordButton.setTitle("Stopping", for: .disabled)
        } else {
            do {
                try startRecording()
                recordButton.setTitle("Stop Recording", for: [])
            } catch {
                recordButton.setTitle("Recording Not Available", for: [])
            }
        }
    }
    
    @IBAction func playAudio(_ sender: UIButton) {
        print("Pressed play")
        print(player)
        if let speechBuffer = speechBuffer  {
            // First stop the mic from listening so the playback doesn't get recognized
            print("Removing tap during playback")
            audioEngine.inputNode.removeTap(onBus: 0)
            
            // Play the audio
            player.scheduleBuffer(speechBuffer, at:nil, completionHandler: {
                print("Re-installing Tap")
                self.installTap() // After done playing, re-enable the mic
            })
            player.play()
        } else {
            print("Start recording first to initialize the sound system")
        }
    }
}

