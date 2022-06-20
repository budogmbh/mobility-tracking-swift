//
//  Location.swift
//  Tracker
//
//  Created by Tobias Frech on 27.05.19.
//  Copyright © 2018-2022 budo GmbH. All rights reserved.
//

import Foundation
import CoreLocation

public struct Location: Codable, Comparable {
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double
    public var horizontalAccuracy: Double
    public var verticalAccuracy: Double
    public var course: Double
    public var speed: Double
    public var timestamp: Date
    
    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        altitude = location.altitude
        horizontalAccuracy = location.horizontalAccuracy
        verticalAccuracy = location.verticalAccuracy
        course = location.course
        speed = location.speed
        timestamp = location.timestamp
    }
    
//    init(_ dict: Dictionary<String, Any>) {
//        latitude = dict["latitude"] as! Double
//        longitude = dict["longitude"] as! Double
//        altitude = dict["altitude"] as! Double
//        horizontalAccuracy = dict["horizontalAccuracy"] as! Double
//        verticalAccuracy = dict["verticalAccuracy"] as! Double
//        course = dict["course"] as! Double
//        speed = dict["speed"] as! Double
//        timestamp = dict["timestamp"] as! Date
//    }
    
    public var coordinate: CLLocationCoordinate2D { get { return CLLocationCoordinate2D(latitude: latitude, longitude: longitude) } }
    
    public var location: CLLocation {
        get {
            return CLLocation(coordinate: coordinate, altitude: altitude, horizontalAccuracy: horizontalAccuracy, verticalAccuracy: verticalAccuracy, course: course, speed: speed, timestamp: timestamp)
        }
    }
    
//    public var dict: Dictionary<String, Any> {
//        get {
//            return ["latitude": latitude, "longitude": longitude, "altitude": altitude, "horizontalAccuracy": horizontalAccuracy, "verticalAccuracy": verticalAccuracy, "course": course, "speed": speed, "timestamp": timestamp]
//        }
//    }
    
    public var id: String { get { return String(Int(timestamp.timeIntervalSince1970)) } }
    
    
    public static func center(of locations: [Location]) -> Location {
        var latitude = 0.0, longitude = 0.0, horizontalAccuracy = 0.0, altitude = 0.0, verticalAccuracy = 0.0
        for location in locations {
            latitude += location.coordinate.latitude
            longitude += location.coordinate.longitude
            horizontalAccuracy += location.horizontalAccuracy
            altitude += location.altitude
            verticalAccuracy += location.verticalAccuracy
        }
        latitude = latitude / Double(locations.count)
        longitude = longitude / Double(locations.count)
        horizontalAccuracy = horizontalAccuracy / Double(locations.count)
        altitude = altitude / Double(locations.count)
        verticalAccuracy = verticalAccuracy / Double(locations.count)
        return Location(CLLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), altitude: altitude, horizontalAccuracy: horizontalAccuracy, verticalAccuracy: verticalAccuracy, timestamp: Date()))
    }
    
    
    
    // Mark - Comparable
    public static func < (lhs: Location, rhs: Location) -> Bool {
        return lhs.timestamp < rhs.timestamp
    }
    
    public static func == (lhs: Location, rhs: Location) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude && lhs.timestamp == rhs.timestamp
    }
}


