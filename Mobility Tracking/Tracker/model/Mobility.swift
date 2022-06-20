//
//  Mobility.swift
//  Tracker
//
//  Created by Tobias Frech on 20.05.19.
//  Copyright © 2018-2022 budo GmbH. All rights reserved.
//

import Foundation

struct Mobility: Codable {
    
    public enum Transport: Int, Codable {
        case unknown
        case foot
        case bike
        case car
    }
    
    public enum Confidence: Int, Codable {
        case low
        case medium
        case high
    }
    
    public enum Motion: Int, Codable {
        case unknown
        case still
        case moving
    }

    public var startDate: Date
    public var transport: Transport
    public var confidence: Confidence
    public var motion: Motion
    
    public static func == (lhs: Mobility, rhs: Mobility) -> Bool {
        return lhs.transport == rhs.transport && lhs.motion == rhs.motion
    }
    
    public static let Unknown = Mobility(startDate: Date(timeIntervalSince1970: 0.0), transport: .unknown, confidence: .low, motion: .unknown)
}


