//
//  ViewController.swift
//  boop
//
//  Created by ariel anders on 2/26/16.
//  Copyright © 2016 ArielAnders. All rights reserved.
//

import UIKit
import AudioToolbox
import AVFoundation
import Darwin

// two finger scrub to toggle vibrate enable on or off

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate{
    
    @IBOutlet weak var vibrate_label: UILabel!
    @IBOutlet weak var previewView: UIView!
    @IBOutlet weak var do_vibrate: UISwitch!
    @IBOutlet weak var luminance: UILabel!
    
    var mySound: AVAudioPlayer?
    var captureSession: AVCaptureSession?
    var stillImageOutput: AVCaptureStillImageOutput?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var SwiftTimer : Timer?

    var audioEngine : AVAudioEngine?
    var updater: Timer?
    var setup: Bool?
    
    //pixel callbacks
    var pixelBuffer: CVPixelBuffer?
    var context: CIContext?
    var cameraImage: CIImage?
    var cgImg: CGImage?
    var pixelData:CFData?
    var pixels: UnsafePointer<UInt8>?
    
    
    var backCamera: AVCaptureDevice?

    var lastBuzz: Double?
    
    var prev_lum: Double?
    var prev_lum1: Double?
    
    var sampler:AVAudioUnitSampler?
    var mixer:AVAudioMixerNode?
    
    let tap = UITapGestureRecognizer()
    
    var lock : Bool?
    var processImgLock : Bool?
    
    var loaded:Bool?
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        NSLog("View did load")
        self.prev_lum1 = 0.0
        self.prev_lum = 0.0
        self.lastBuzz =   NSDate().timeIntervalSince1970
        
        
    }
    override func viewWillAppear(_ animated: Bool) {
        
        NSLog("view will appear")
        super.viewWillAppear(animated)
        setup = false
        self.loaded = true
        
        
        captureSession = AVCaptureSession()
        var error: NSError?
        
        backCamera = getDevice(position: .back)
        if backCamera == nil {
            self.loaded=false
            return
        }
        
        var input: AVCaptureDeviceInput!
        do {
            input = try AVCaptureDeviceInput(device: backCamera!)
        } catch let error1 as NSError {
            error = error1
            input = nil
            NSLog("Camera error")
            self.loaded = false
        }
        let videoOutput = AVCaptureVideoDataOutput()
        
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sample buffer delegate"))
        
        
        
        if error == nil && captureSession!.canAddInput(input) {
            captureSession!.addInput(input)
            
            stillImageOutput = AVCaptureStillImageOutput()
            stillImageOutput!.outputSettings = [AVVideoCodecKey: AVVideoCodecJPEG]
            if captureSession!.canAddOutput(stillImageOutput!) {
                
                captureSession!.addOutput(stillImageOutput!)
                previewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
                //previewLayer!.videoGravity = AVLayerVideoGravity.resizeAspect
                previewLayer!.connection?.videoOrientation = AVCaptureVideoOrientation.portrait
                previewView.layer.addSublayer(previewLayer!)
                
                captureSession!.addOutput(videoOutput)
                captureSession!.startRunning()
                setup = true
            }
        }
        
        NSLog("Hello world! Loaded Program!")
        self.audioEngine = AVAudioEngine()
        AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
        AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
        AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
        
        
        self.lastBuzz =   NSDate().timeIntervalSince1970
        self.lock = false
        self.processImgLock = false
        
        mixer = self.audioEngine?.mainMixerNode
        sampler = AVAudioUnitSampler()
        self.audioEngine?.attach(sampler!)
        self.audioEngine?.connect(sampler!, to: mixer!, format: sampler!.outputFormat(forBus: 0))
        do{
            try   self.audioEngine?.start()
        }catch let error2 as NSError{
            error = error2
            self.loaded = false
            NSLog(error!.description)
        }
        if (self.loaded!){
            self.updater = Timer.scheduledTimer( timeInterval: 0.07, target: self, selector: #selector(UIMenuController.update), userInfo: nil, repeats: true)
        }else {
            self.vibrate_label.text="camera & sound error"
        }
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if (setup!){
            previewLayer!.frame = previewView.bounds
        }
        NSLog("View did appear")
    }
    
    

    //Get the device (Front or Back)
    func getDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let devices: NSArray = AVCaptureDevice.devices() as NSArray;
        for de in devices {
            let deviceConverted = de as! AVCaptureDevice
            if(deviceConverted.position == position){
                return deviceConverted
            }
        }
        return nil
    }
    
    func captureOutput(_ captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
    {
        pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        context = CIContext(options:nil)
        cameraImage = CIImage(cvPixelBuffer: pixelBuffer!)
        cgImg = context!.createCGImage(cameraImage!, from: cameraImage!.extent)
        DispatchQueue.main.async {
            self.getPixels()
        }
    }
    

    @objc func update() {
        
        if (self.lock! && setup!){
            NSLog("locked")
        } else{
            
            self.lock = true
            
            
            
            var amount = (self.prev_lum! + self.prev_lum1!)/2
            let iso = Double((self.backCamera?.iso)!)
            let exp = Double((self.backCamera?.exposureDuration.seconds)!)
            
            var scalelum =  (log10( amount / (iso*exp)) + 2.4)/2.8
            if (scalelum <= 0.0){
                scalelum = 0.0
            }
            if (scalelum >= 1.0 ){
                scalelum = 1.0
            }
            amount = scalelum
            
            //XXX NSLog("iso:%f, exp:%f, scalelum:%f", (self.backCamera?.ISO)!, (self.backCamera?.exposureDuration.seconds)!, scalelum)
            self.luminance.text = String( Int(100.0*amount) )
            
            let lo = 73.0
            let  note = UInt8(20.0*amount + lo)
            
            let vol = UInt8(amount*100 + 20)
            let sleep_time = 1000000.0*(0.4-0.3*amount)
            let vibe_sleep_time = (1.7-1.3*amount)
            
            
            if (amount > 0.01){
                self.play(note: note,velocity:vol )
                let currentDateTime = NSDate().timeIntervalSince1970
                if (self.do_vibrate.isOn && ((currentDateTime - self.lastBuzz!) > vibe_sleep_time)){
                    
                    AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
                    self.lastBuzz = currentDateTime
                }
                if (amount > 0.9){
                    AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
                }
                
            }
            
            usleep (UInt32(sleep_time))
            if (amount > 0.01){
                sampler!.stopNote(note, onChannel: 1)
            }
            self.lock = false
        }
    }
    
    func play(note:UInt8, velocity:UInt8){
        sampler!.startNote(note, withVelocity: velocity, onChannel: 1)
    }
    
    func getPixels(){
        if (!processImgLock! && !lock!){
            processImgLock = true
            
            let width = self.cgImg!.width
            let height = self.cgImg!.height
            
            pixelData = self.cgImg!.dataProvider?.data
            pixels = CFDataGetBytePtr(pixelData)
            var sum_red = 0
            var sum_green = 0
            var sum_blue = 0
            
            let mid_size = 20
            let mid_sqr = (mid_size + 1 ) * (mid_size + 1)
            
            let x_min = width/2 - mid_size / 2
            let x_max = width/2 + mid_size / 2
            
            let y_min = height/2 - mid_size / 2
            let y_max = height/2 + mid_size / 2
            
            for x in x_min ... x_max  {
                for y in y_min ... y_max {
                    //Here is your raw pixels
                    let offset = 4*((Int(width) * Int(y)) + Int(x))
                    let red = pixels![offset]
                    let green = pixels![offset+1]
                    let blue = pixels![offset+2]
                    sum_red = sum_red + Int(red)
                    sum_green = sum_green + Int(green)
                    sum_blue = sum_blue + Int(blue)
                }
            }
            
            
            let avg_red = Double( sum_red/mid_sqr)
            let avg_green = Double( sum_green/mid_sqr)
            let avg_blue = Double(sum_blue/mid_sqr)
            
            let lum =  (0.21 * avg_red + 0.72*avg_green + 0.07*avg_blue ) / 255.0
            self.prev_lum = self.prev_lum1
            self.prev_lum1 = lum
            processImgLock = false
            
        }
    }
    
    
    
    
    /*
     Accessiblity functions below
     */
    override func accessibilityPerformMagicTap() -> Bool {
        
        exit(0)
        
    }
    override func accessibilityPerformEscape() -> Bool {
        if (self.loaded!){
            
            if (self.do_vibrate.isOn){
                self.vibrate_label.text = "Vibrate mode is off"
                self.do_vibrate.setOn(false, animated: true)
            }else{
                self.do_vibrate.setOn(true, animated: true)
                
                self.vibrate_label.text = "Vibrate mode is on"
                
            }
        }
        return true
    }
    @IBAction func vibrate_toggle(_ sender: Any) {
        if (self.loaded!){
            if (self.do_vibrate.isOn){
                self.vibrate_label.text = "Vibrate mode is on"
                // self.vibrate_enable.setTitle("Vibrate On",forState: UIControlState.Normal)
            }else{
                self.vibrate_label.text = "Vibrate mode is off"
            }
        }
    }
    
    
}

