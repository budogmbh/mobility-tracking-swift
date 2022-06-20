//
//  ContextManager.swift
//  Collecting additional context information
//
//  Created by Tobias Frech on 20.05.19.
//  Copyright © 2018-2022 budo GmbH. All rights reserved.
//

import Foundation
import AVFoundation
import UIKit
import SystemConfiguration.CaptiveNetwork

class ContextManager: NSObject {
    
    private static var initDone = false
    
    public static func connectedNetworks() -> [String] {
        var bssids = [String]()
        if let interfaces = CNCopySupportedInterfaces() as NSArray? {
            for interface in interfaces {
                if let interfaceInfo = CNCopyCurrentNetworkInfo(interface as! CFString) as NSDictionary? {
                    if let bssid = interfaceInfo[kCNNetworkInfoKeyBSSID as String] as? String {
                        bssids.append(bssid)
                    }
                }
            }
        }
        return bssids
    }
    
    public static func connectedDevices() -> [String] {
        if !initDone {
            // Prepare bluetooth connection monitoring
            do {
                try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .spokenAudio, options: [.allowBluetooth, .mixWithOthers])
            } catch let error {
                print("ContextManager: Error while configuring bluetooth monitoring: \(error.localizedDescription)")
            }
            initDone = true
        }
        var context = [String]()
        if let inputs = AVAudioSession.sharedInstance().availableInputs {
            let devices = inputs.map { (input) -> Device in return Device(input) }
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
        }
        return context
    }


    public static func batteryLevel() -> Int {
        UIDevice.current.isBatteryMonitoringEnabled = true
        return Int(UIDevice.current.batteryLevel * 100)
    }
    
    public static func externalPowerSupply() -> Bool {
        UIDevice.current.isBatteryMonitoringEnabled = true
        return UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
    }

    
    
}
