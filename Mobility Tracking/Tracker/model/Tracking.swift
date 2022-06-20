//
//  Tracking.swift
//  Tracker
//
//  Created by Tobias Frech on 15.05.19.
//  Copyright © 2018-2022 budo GmbH. All rights reserved.
//

import Foundation

struct Tracking: Codable, Comparable {
    
    public enum Transport: String, Codable {
        case unknown = "unknown"
        case foot = "foot"
        case car = "car"
        case bike = "bike"
    }
    
    struct Context: Codable {
        public var activity: String
        public var carmode: Bool
        public var devices: [String]
        public var wifis: [String]
        public var batteryLevel: Int
        public var externalPowerSupply: Bool
    }
    
    public var tracker: String
    public var account: String
    public var trajectory: String
    public var location: Location
    public var transport: Transport
    public var stationary: Bool
    public var context: Context
    
    public var timestamp: Date { get { return location.timestamp } }
    
    public var data: [String: Any] {
        get {
            var dict = [
                "timestamp": Int(timestamp.timeIntervalSince1970),
                "latitude": location.latitude,
                "longitude": location.longitude,
                
                "horizontalAccuracy": location.horizontalAccuracy,
                "altitude": location.altitude,
                "verticalAccuracy": location.verticalAccuracy,
                "speed": location.speed,
                "course": location.course,
                
                "source": "iOS",
                "tracker": tracker,
                "trajectory": trajectory,
                
                "activity": context.activity,
                "devices": context.devices,
                "wifis": context.wifis,
                "carmode": context.carmode,
                "batteryLevel": context.batteryLevel,
                "externalPowerSupply": context.externalPowerSupply
                ] as [String : Any]
            
            // add transport
            switch transport {
            case .foot: dict["transport"] = "foot"
            case .bike: dict["transport"] = "bike"
            case .car: dict["transport"] = "car"
            case .unknown: dict["transport"] = "unknown"
            }
            
            return dict
        }
    }
    
    
    // Mark - Comparable
    
    static func < (lhs: Tracking, rhs: Tracking) -> Bool {
        return lhs.timestamp < rhs.timestamp
    }
    
    static func == (lhs: Tracking, rhs: Tracking) -> Bool {
        return lhs.timestamp == rhs.timestamp
    }
    
}

