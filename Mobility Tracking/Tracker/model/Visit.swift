//
//  Visit.swift
//  Tracker
//
//  Created by Tobias Frech on 02.06.19.
//  Copyright © 2018-2022 budo GmbH. All rights reserved.
//

import Foundation
import CoreLocation

struct Visit: Codable, Comparable {
    public var latitude: Double
    public var longitude: Double
    public var horizontalAccuracy: Double
    public var arrivalDate: Date
    public var departureDate: Date
    public var timestamp: Date
    
    init(_ visit: CLVisit) {
        latitude = visit.coordinate.latitude
        longitude = visit.coordinate.longitude
        horizontalAccuracy = visit.horizontalAccuracy
        arrivalDate = visit.arrivalDate
        arrivalDate = visit.arrivalDate
        departureDate = visit.departureDate
        timestamp = Date()
    }
    
    public var coordinate: CLLocationCoordinate2D { get { return CLLocationCoordinate2D(latitude: latitude, longitude: longitude) } }
    
    public var location: CLLocation {
        get {
            return CLLocation(coordinate: coordinate, altitude: -1, horizontalAccuracy: horizontalAccuracy, verticalAccuracy: -1, timestamp: timestamp)
            }
    }
    
    public var id: String { get { return String(Int(timestamp.timeIntervalSince1970)) } }
    
    
    // Mark - Comparable
    public static func < (lhs: Visit, rhs: Visit) -> Bool {
        return lhs.timestamp < rhs.timestamp
    }
    
    public static func == (lhs: Visit, rhs: Visit) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude && lhs.timestamp == rhs.timestamp
    }
}


