//
//  CarMode.swift
//  Detect if user is connected to carplay or car bluetooth
//
//  Created by Tobias Frech on 26.06.19.
//  Copyright © 2018-2022 budo GmbH. All rights reserved.
//

import Foundation
import AVFoundation

protocol CarModeDelegate {
    func carMode(active: Bool)
}

class CarMode: NSObject {
    
    private let kCarIdentifiers = ["car", "bmw", "porsche", "audi", "vw", "volkswagen", "mercedes", "toyota", "nissan", "smart", "peugeot", "renault", "volvo", "tesla", "sion", "sono", "opel", "ford", "chrysler", "mini", "byton", "nio", "škoda", "skoda", "citroën", "citroen", "bugatti", "fiat", "ferrari", "lamborghini", "maserati", "honda", "daihatsu", "infiniti", "isuzu", "lexus", "mazda", "mitsubishi", "nissan", "suzuki", "subaru", "dacia", "hyundai", "kia", "seat", "jaguar", "land rover", "lotus", "mclaren", "vauxhall", "rolls-royce", "buick", "dodge", "chevrolet", "cadillac", "faraday", "jeep", "general motors", "gmc", "auto"]
    
    private let dispatchQueue = DispatchQueue(label: "de.budo.carmode")
    private let session = AVAudioSession.sharedInstance()
    private var lastInCarState = false
    private var timer: Timer?
    public var delegate: CarModeDelegate?
    
    override init() {
        do {
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.allowBluetooth, .mixWithOthers])
        } catch let error {
            print("CarMode: Error while setup HFP/CarPlay monitoring: \(error.localizedDescription)")
        }
        
        super.init()
    }
    
    /**
     Start active monitoring of car mode. Every change will be notified to the registered CarModeDelegate.
     */
    public func start() {
        // initial value
        lastInCarState = active
        delegate?.carMode(active: lastInCarState)
        
        // timer to watch connection states
        timer = Timer(timeInterval: 5.0, repeats: true, block: { (timer) in
            self.checkStateChange()
        })
        timer?.tolerance = 1.0
        RunLoop.current.add(timer!, forMode: .common)
        addObserver()
    }
    
    /**
     Stop active monitoring of car mode
     */
    public func stop() {
        removeObserver()
        timer?.invalidate()
        timer = nil
    }
    
    /**
     Query if car mode is currently active
     */
    public var active: Bool {
        get {
            if let inputs = session.availableInputs {
                for input in inputs {
                    if input.portType == .carAudio { return true }
                    if input.portType == .bluetoothHFP && carState(by: input.portName) { return true }
                }
                return false
            }
            return false
        }
    }
    
    private func checkStateChange() {
        dispatchQueue.sync {
            if lastInCarState != active {
                lastInCarState = !lastInCarState
                DispatchQueue.main.async {
                    self.delegate?.carMode(active: self.lastInCarState)
                }
            }
        }
    }
    
    private func addObserver() {
        removeObserver()
        NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
    }
    
    private func removeObserver() {
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
    }
    
    @objc private func handleRouteChange(notification: Notification) {
        checkStateChange()
    }
    
    private func carState(by deviceName: String) -> Bool {
        for carIdentifier in kCarIdentifiers {
            if deviceName.lowercased().contains(carIdentifier) {
                return true
            }
        }
        return false
    }
    
    deinit {
        stop()
    }
    
    
}
