//
//  Device.swift
//  Tracker
//
//  Created by Tobias Frech on 21.05.19.
//  Copyright © 2018-2022 budo GmbH. All rights reserved.
//

import Foundation
import AVFoundation

/**
 Detected connected device (CarPlay or Bluetooth using Handsfree Profile (HFP))
 */

@objc public class Device: NSObject, Codable {
    
    /**
     Possible port types
     */
    public enum Port: Int, Codable {
        case carplay
        case hfp
        case audio
        case other
    }
    
    /**
     Name of the device
     */
    public var name: String
    
    /**
     Unique ID of the device
     */
    public var id: String
    
    /**
     Port type of the device
     */
    public var port: Port
    
    /**
     If `true`, the device was registered as a car
     */
    public var registeredAsCar: Bool

    var activityTotalCount: Int
    var activityAutomotiveCount: Int
    
    init(_ input: AVAudioSessionPortDescription) {
        name = input.portName
        id = input.id
        if input.portType == .carAudio {
            port = .carplay
        } else if input.portType == .bluetoothHFP {
            port = .hfp
        } else if input.portType == .bluetoothA2DP {
            port = .audio
        } else {
            port = .other
        }
        
        registeredAsCar = false
        activityTotalCount = 0
        activityAutomotiveCount = 0
    }
    
    /**
     Indicating the probability that this device is a car (value between 0 and 1.0)
     */
    public var carProbability: Double {
        get {
            guard activityTotalCount >= 5 else { return 0.0 }
            return Double(activityAutomotiveCount) / Double(activityTotalCount)
        }
    }

    /**
     If `true`, the device was identified as a car
     */
    public var inCarDevice: Bool {  get { return port == .carplay || registeredAsCar || carProbability >= 0.85 } }
}

