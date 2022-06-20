//
//  Permission.swift
//  Helper method to request user's permission
//
//  Created by Tobias Frech on 07.11.18.
//  Copyright © 2018-2022 budo GmbH. All rights reserved.
//

import Foundation
import CoreLocation
import CoreMotion
import UserNotifications
import UIKit

/**
 The permission call back returns the status of the permission request
 */
public typealias PermissionCallback = (PermissionStatus) -> Void

/**
 The permission status contains the current status of the permission
 */
public enum PermissionStatus {
    /**
     Access was granted by user
     */
    case authorized
    /**
     User has denied access
     */
    case denied
    /**
     Required service is not available
     */
    case disabled
    /**
     Permission was not requested by user yet
     */
    case notDetermined
}

protocol PermissionDelegate {
    func permission(locationPermission: PermissionStatus)
}

class Permission: NSObject, CLLocationManagerDelegate {
    
    private let locationManager = CLLocationManager()
    private let activityManager = CMMotionActivityManager()
    private let userNotificationCenter = UNUserNotificationCenter.current()
    private var locationPermissionResult: PermissionCallback?
    public var delegate: PermissionDelegate?
    
    override init() {
        super.init()
        locationManager.delegate = self
    }
    
    public func motionStatus() -> PermissionStatus {
        guard CMMotionActivityManager.isActivityAvailable() else {
            return .disabled
        }
        switch CMMotionActivityManager.authorizationStatus() {
        case .authorized:       return .authorized
        case .denied:           return .denied
        case .restricted:       return .disabled
        case .notDetermined:    return .notDetermined
        default:                return .denied
        }
    }
    
    public func motionStatusRaw() -> String {
        guard CMMotionActivityManager.isActivityAvailable() else {
            return "notAvailable"
        }
        
        switch CMMotionActivityManager.authorizationStatus() {
        case .authorized:       return "authorized"
        case .denied:           return "denied"
        case .restricted:       return "restricted"
        case .notDetermined:    return "notDetermined"
        default:                return "notDefined"
        }
    }
    
    public func locationStatus() -> PermissionStatus {
        guard CLLocationManager.locationServicesEnabled() else {
            return .disabled
        }
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            return .denied
        }
        switch locationManager.authorizationStatus {
        case .authorizedAlways:                             return .authorized
        case .restricted, .denied, .authorizedWhenInUse:    return .denied
        case .notDetermined:                                return .notDetermined
        default:                                            return .denied
        }
    }
    
    public func locationStatusRaw() -> String {
        guard CLLocationManager.locationServicesEnabled() else {
            return "disabled"
        }
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            return "geofenceNotAvailable"
        }

        switch locationManager.authorizationStatus {
        case .authorizedAlways:     return "authorizedAlways"
        case .restricted:           return "restricted"
        case .denied:               return "denied"
        case .authorizedWhenInUse:  return "authorizedWhenInUse"
        case .notDetermined:        return "notDetermined"
        default:                    return "notDefined"
        }
    }

    
    public func requestNotification(_ result: @escaping PermissionCallback) {
        userNotificationCenter.getNotificationSettings { (settings) in
            switch settings.authorizationStatus {
            case .authorized: result(.authorized)
            case .denied,.ephemeral: result(.denied)
            case .notDetermined, .provisional:
                self.userNotificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { (granted, error) in
                    if Thread.isMainThread {
                        if error == nil && granted {
                            result(.authorized)
                        } else {
                            result(.denied)
                        }
                    } else {
                        DispatchQueue.main.async {
                            if error == nil && granted {
                                result(.authorized)
                            } else {
                                result(.denied)
                            }
                        }
                    }
                }
            @unknown default:
                fatalError()
            }
        }
    }
    
    public func requestMotion(_ result: @escaping PermissionCallback) {
        guard CMMotionActivityManager.isActivityAvailable() else {
            result(.disabled)
            return
        }
        switch CMMotionActivityManager.authorizationStatus() {
        case .authorized:   result(.authorized)
        case .denied:       result(.denied)
        case .restricted:   result(.disabled)
        case .notDetermined:
            // request permission
            self.activityManager.queryActivityStarting(from: Date(), to: Date(), to: .main) { (activities, error) in
                DispatchQueue.main.async {
                    if error != nil {
                        result(.denied)
                    } else {
                        result(.authorized)
                    }
                }
            }
            break
        default:            result(.denied)
        }
    }
    
    public func requestLocation(_ result: @escaping PermissionCallback) {
        guard CLLocationManager.locationServicesEnabled() else {
            result(.disabled)
            return
        }
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            result(.denied)
            return
        }
        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            if locationManager.accuracyAuthorization == .fullAccuracy {
                result(.authorized)
            } else {
                result(.denied)
            }
            break
        case .restricted, .denied:    result(.denied)
        case .authorizedWhenInUse:
            locationPermissionResult = result
            locationManager.requestAlwaysAuthorization()
            break
        case .notDetermined:
            locationPermissionResult = result
            locationManager.requestWhenInUseAuthorization()
            break
        default:                                            result(.denied)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if let result = locationPermissionResult {
            switch status {
            case .authorizedAlways:                             result(.authorized)
            case .notDetermined:                                result(.notDetermined)
            case .restricted, .denied, .authorizedWhenInUse:    result(.denied)
            default:                                            result(.denied)
            }
            locationPermissionResult = nil
        }
        switch status {
        case .authorizedAlways:                             delegate?.permission(locationPermission: .authorized)
        case .notDetermined:                                delegate?.permission(locationPermission: .notDetermined)
        case .restricted, .denied, .authorizedWhenInUse:    delegate?.permission(locationPermission: .denied)
        default:                                            delegate?.permission(locationPermission: .denied)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Permission: Location permission request didFailWithError: \(error.localizedDescription)")
    }
}
