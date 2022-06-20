//
//  DeviceManager.swift
//  Managing Bluetooth and CarPlay devices
//
//  Created by Tobias Frech on 21.05.19.
//  Copyright © 2018-2022 budo GmbH. All rights reserved.
//

import Foundation
import AVFoundation
import UIKit

protocol DeviceManagerDelegate {
    func deviceManager(_ manager: DeviceManager, didDetect device: Device)
    func deviceManager(_ manager: DeviceManager, didConnect device: Device)
    func deviceManager(_ manager: DeviceManager, didDisconnect device: Device)
}

class DeviceManager: NSObject {
    
    private let UDS_KEY_CONNECTED = "mobilitytracker_connected_devices"
    private let FILENAME_DEVICES = "mobilitytracker_devices.json"

    private let dispatchQueueStorage = DispatchQueue(label: "mobilitytracker.devicemanager.storage")
    private let dispatchQueueNotification = DispatchQueue(label: "mobilitytracker.devicemanager.notification")

    var delegate: DeviceManagerDelegate?

    private var _devices: [String: Device]
    public private(set) var active = false
    private var timer: Timer?
    
    private var _connectedIDs: [String] {
        get { return UserDefaults.standard.stringArray(forKey: UDS_KEY_CONNECTED) ?? [String]() }
        set { UserDefaults.standard.set(newValue, forKey: UDS_KEY_CONNECTED) }
    }
    
//    static func inCarDevice(_ deviceUIDs: [String]) -> Bool {
//        guard Storage.fileExists("mobilitytracker_devices.json", in: .documents) else { return false }
//        let devices = Storage.retrieve("mobilitytracker_devices.json", from: .documents, as: [String: MBDevice].self)
//        for uid in deviceUIDs {
//            if devices[uid]?.inCarDevice ?? false {
//                return true
//            }
//        }
//        return false
//    }
    
    override init() {
        _devices = Storage.fileExists(FILENAME_DEVICES, in: .documents) ? Storage.retrieve(FILENAME_DEVICES, from: .documents, as: [String: Device].self) : [:]
        super.init()
        
        // Prepare bluetooth connection monitoring
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: .allowBluetooth)
        } catch let error {
            print("MobilityTracker - DeviceManager: Error while configuring bluetooth monitoring: \(error.localizedDescription)")
        }
        
        // Update list of currently connected devices
        updateConnectionStates()
    }
    
    
    func start() {
        active = true
        addObserver()
        
        timer = Timer(timeInterval: 5.0, repeats: true, block: { (timer) in
            self.updateConnectionStates()
        })
        timer?.tolerance = 1.0
        RunLoop.current.add(timer!, forMode: .common)
    }
    
    func stop() {
        removeObserver()
        
        // stop timer
        timer?.invalidate()
        timer = nil
        
        // disconnect all devices
        dispatchQueueNotification.sync {
            for id in _connectedIDs {
                delegate?.deviceManager(self, didDisconnect: _devices[id]!)
            }
            _connectedIDs = []
        }
        
        active = false
    }
    
    func update(statisticsWith trackings: [Tracking]) {
        if trackings.count > 5 {
            dispatchQueueNotification.sync {
                for tracking in trackings {
                    for id in tracking.context.devices {
                        if tracking.context.activity.starts(with: "car") {
                            _devices[id]?.activityAutomotiveCount += 1
                        }
                        _devices[id]?.activityTotalCount += 1
                    }
                }
                Storage.store(_devices, to: .documents, as: FILENAME_DEVICES)
            }
        }
    }
    
    func update(statisticsWith activity: String, for devices: [String]) {
        dispatchQueueNotification.sync {
            for id in devices {
                if activity.starts(with: "car") {
                    _devices[id]?.activityAutomotiveCount += 1
                }
                _devices[id]?.activityTotalCount += 1
            }
            Storage.store(_devices, to: .documents, as: FILENAME_DEVICES)
        }
    }

    func devices() -> [Device] {
        return _devices.map { $0.value }
    }
    
    func isInCar() -> Bool {
        for device in connectedDevices() {
            if device.inCarDevice {
                return true
            }
        }
        return false
    }
    
    func connectedDevices() -> [Device] {
        var devices = [Device]()
        if let inputs = AVAudioSession.sharedInstance().availableInputs {
            for input in inputs {
                if input.portType == .carAudio || input.portType == .bluetoothHFP || input.portType == .bluetoothA2DP || input.portType == .bluetoothLE {
                    if !_devices.keys.contains(input.id) {
                        // register new device
                        dispatchQueueStorage.sync {
                            _devices[input.id] = Device(input)
                            Storage.store(_devices, to: .documents, as: FILENAME_DEVICES)
                            delegate?.deviceManager(self, didDetect: _devices[input.id]!)
                        }
                    }
                    devices.append(_devices[input.id]!)
                }
            }
        }
        return devices
    }

    func context() -> [String] {
        var context = [String]()
        let devices = connectedDevices()
        for device in devices {
            var port = "other"
            if device.port == .carplay {
                port = "carplay"
            } else if device.port == .hfp {
                port = "hfp"
            } else if device.port == .audio {
                port = "audio"
            }
            
            context.append("\(port)-\(device.id)")
        }
        return context
    }
    
    
    // Mark - Internal stuff
    
    private func addObserver() {
        removeObserver()
        NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
    }
    
    private func removeObserver() {
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
    }
    
    private func updateConnectionStates() {
        dispatchQueueNotification.sync {
            let devices = connectedDevices()
            let oldDevices = _connectedIDs
            _connectedIDs = devices.map({$0.id})
            for id in _connectedIDs {
                if !oldDevices.contains(id) {
                    delegate?.deviceManager(self, didConnect: _devices[id]!)
                }
            }
            for id in oldDevices {
                if !_connectedIDs.contains(id) {
                    delegate?.deviceManager(self, didDisconnect: _devices[id]!)
                }
            }
            
        }
    }
    
    @objc func handleRouteChange(notification: Notification) {
        updateConnectionStates()
    }
    
}


extension AVAudioSessionPortDescription {
    public var id: String {
        get {
           return String(uid.split(separator: "-").first!)
        }
    }
}

