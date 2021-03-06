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
    
    let debug = false
    
    func NSLogDebug(_ str: String){
        if(debug){
            NSLog(str)
        }
    }
    
    @IBOutlet weak var vibrate_label: UILabel!
    @IBOutlet weak var previewView: UIView!
    @IBOutlet weak var do_vibrate: UISwitch!
    @IBOutlet weak var luminance: UILabel!
    
    var mySound: AVAudioPlayer?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var updater: Timer?
    
    var lastBuzz: Double?

    let tap = UITapGestureRecognizer()
    var lock : Bool?
    var app_running : Bool?
    
    let AD = UIApplication.shared.delegate as! AppDelegate
    
    
    var loaded: Bool?
       
       
       //audio variables
       var audioEngine : AVAudioEngine?
       var sampler:AVAudioUnitSampler?
       var mixer:AVAudioMixerNode?
       
       // camera variables
       var captureSession: AVCaptureSession?
       var input_av_capture: AVCaptureDeviceInput?
       var videoOutput : AVCaptureVideoDataOutput?
       var backCamera: AVCaptureDevice?
       
       //pixel callbacks
       var pixelBuffer: CVPixelBuffer?
       var context: CIContext?
       var cameraImage: CIImage?
       var cgImg: CGImage?
       var pixelData:CFData?
       var pixels: UnsafePointer<UInt8>?
       
       //lightdetection computation
       var prev_lum: Double?
       var prev_lum1: Double?
       var processImgLock : Bool?
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        NSLogDebug("View will appear")
        app_running = false
        startServices()
        startApp()
        
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        
         NotificationCenter.default.addObserver(self, selector: #selector(applicationWillTerminate), name: UIApplication.willTerminateNotification, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        
         NotificationCenter.default.addObserver(self, selector: #selector(willResignActive), name: UIApplication.willResignActiveNotification, object: nil)
               
    }
    
    @objc func willResignActive(){
        NSLogDebug("View: will resign active")
        stopApp()
    }
    @objc func willEnterForeground(){
        NSLogDebug("View: will enter foreground")
        startServices()
        startApp()
    }
    
    @objc func didBecomeActive(){
        NSLogDebug("View: did become active")
        startServices()
        startApp()
    }
    
    @objc func applicationWillTerminate(){
           NSLogDebug("View: app will terminate")
        stopApp()
        stopServices()
       }
    @objc func didEnterBackground(){
           NSLogDebug("View: did enter background")
        stopApp()
        stopServices()
       }
    
    
        
   /* func startLightDetection(){
        self.setupServices()
        
        self.prev_lum1 = 0.0
        self.prev_lum = 0.0
        self.processImgLock = false
        self.lastBuzz =   NSDate().timeIntervalSince1970
        self.lock = false
        if (self.loaded!){
            self.updater = Timer.scheduledTimer( timeInterval: 0.07, target: self, selector: #selector(UIMenuController.update), userInfo: nil, repeats: true)
        }
        
    }*/
    func stopServices(){
        return
        
        if (self.loaded!){
            // stop cameras and audio
            NSLogDebug("TODO: stop camera and audio")
        }else{
            NSLogDebug("already stopped services")
        }
    }
    
    func stopApp(){
        if (self.app_running!){
        self.lock = true
        self.processImgLock = true
        self.updater!.invalidate()
        self.app_running = false
        //self.videoOutput!.
        }
    
    }
    
    func startApp() {
        if (!self.loaded!){
            NSLogDebug("system services not loaded!")
            return
        }
        if (self.app_running!){
            //NSLogDebug("already running")
            return
        }
        self.prev_lum1 = 0.0
        self.prev_lum = 0.0
        self.processImgLock = false
        self.lastBuzz =   NSDate().timeIntervalSince1970
        self.lock = false
        
        // Start threads
        //self.videoOutput!.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sample buffer delegate"))
        self.updater = Timer.scheduledTimer( timeInterval: 0.07, target: self, selector: #selector(UIMenuController.update), userInfo: nil, repeats: true)
        self.app_running = true
    
    }
    
    
    /* Start Up Services Camera and Audo*/
    func startServices(){
        let setup_camera = setupCamera()
        let setup_audio = setupAudio()
        self.loaded = setup_camera && setup_audio
        setupCameraPreviewLayer()

        
    }
    
    func setupCameraPreviewLayer(){
          if (!self.loaded!){
              self.vibrate_label.text="camera error"
          }
          
          if (self.loaded!){
          previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession!)
          previewLayer!.connection?.videoOrientation = AVCaptureVideoOrientation.portrait
          previewView.layer.addSublayer(previewLayer!)
          }else{
              NSLogDebug("did not load preview layer due to loading error")
          }
          if (self.loaded! && previewLayer != nil){
              previewLayer!.frame = previewView.bounds
          }
          NSLogDebug("View did appear")
      }
      
    
    
    func setupAudio() -> Bool {
        var setup : Bool?
        setup = true
        self.audioEngine = AVAudioEngine()
        AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
        AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
        AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
        
        self.mixer = self.audioEngine?.mainMixerNode
        self.sampler = AVAudioUnitSampler()
        self.audioEngine?.attach(self.sampler!)
        self.audioEngine?.connect(self.sampler!, to: self.mixer!, format: self.sampler!.outputFormat(forBus: 0))
        do{
            try   self.audioEngine?.start()
        }catch let error as NSError{
            setup = false
            NSLogDebug(error.description)
        }
        return setup!
    }
    
    func setupCamera() -> Bool {
           
           var setup : Bool?
           setup = false
           
           self.captureSession = AVCaptureSession()
           self.backCamera = getDevice(position: .back)
           
           if self.backCamera == nil {
               NSLogDebug("Cant even discover a camera!")
               return setup!
           }
           
           // set up back camera as input device
           do {
               self.input_av_capture = try AVCaptureDeviceInput(device: self.backCamera!)
           } catch let error as NSError {
               self.input_av_capture = nil
               NSLogDebug("Camera error -- permissions")
               NSLogDebug(error.description)
               return setup!
           }
           
           self.videoOutput = AVCaptureVideoDataOutput()
           self.videoOutput!.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sample buffer delegate"))
           
           if self.captureSession!.canAddInput(self.input_av_capture!) {
               self.captureSession!.addInput(self.input_av_capture!)
           
               if self.captureSession!.canAddOutput(self.videoOutput!) {
                   self.captureSession!.addOutput(self.videoOutput!)
                   self.captureSession!.startRunning()
                   setup = true
               }else{
                   NSLogDebug("cannot capture video output")
               }
           }else{
               NSLogDebug("cannot capture video input")
               }
           return setup!
       }
    
    //Get the device (Front or Back)
       func getDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
           // as default back device is first option
           // possibly want to be more specific here
           let devices: NSArray = AVCaptureDevice.devices() as NSArray;
           for de in devices {
               let deviceConverted = de as! AVCaptureDevice
               if(deviceConverted.position == position){
                   return deviceConverted
               }
           }
           return nil
       }
    
    // camera image callback and pixel computation
    func captureOutput(_ captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
    {
        // not sure how this attaches tbh
        pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        context = CIContext(options:nil)
        cameraImage = CIImage(cvPixelBuffer: pixelBuffer!)
        cgImg = context!.createCGImage(cameraImage!, from: cameraImage!.extent)
        DispatchQueue.main.async {
            self.getPixels()
        }
    }
    
    func getPixels(){
        
        if (!self.loaded!){
            // ideally we would not get here, since the camera calls it
            // but in case there's a race condition
            NSLogDebug("GetPixels: Light detection services not enabled") //XXX should comment
            return
        }
        
        if (!processImgLock!){
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

    
    /* Light detection secret sauce */
    
    @objc func update() {
        if (!self.loaded!){
            NSLogDebug("Light detection services not enabled") //XXX should comment
            return
        }
        
        if (self.lock!){
            NSLogDebug("locked")
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
            
            //XXX NSLogDebug("iso:%f, exp:%f, scalelum:%f", (self.backCamera?.ISO)!, (self.backCamera?.exposureDuration.seconds)!, scalelum)
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
                self.sampler!.stopNote(note, onChannel: 1)
            }
            self.lock = false
        }
    }
    
    
    
    func play(note:UInt8, velocity:UInt8){
        self.sampler!.startNote(note, withVelocity: velocity, onChannel: 1)
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

