//
//  TrackingManager.swift
//  Tracker Main Class
//
//  Created by Tobias Frech on 15.05.19.
//  Copyright © 2018-2022 budo GmbH. All rights reserved.
//

import Foundation
import UIKit
import CoreLocation
import CommonCrypto


protocol TrackingManagerDelegate {
    func trackingManager(_ manager: TrackingManager, didDetect device: Device)
    func trackingManager(_ manager: TrackingManager, didDetect tracking: Tracking)         // only for testing purposes
    func trackingManager(_ manager: TrackingManager, didDetect trackings: [Tracking])
    func trackingManager(_ manager: TrackingManager, didDepartAt origin: CLLocation)
    func trackingManager(_ manager: TrackingManager, didArriveAt location: CLLocation)
    func trackingManager(_ manager: TrackingManager, error: Error)
}

class TrackingManager: NSObject, CLLocationManagerDelegate, MobilityManagerDelegate, DeviceManagerDelegate, CarModeDelegate {
    
    private enum State: Int {
        case undefined  // tracker is not set up yet - setup will be started if tracker is active
        case arrived    // idle - location updates are swiched off
        case departing  // may depart soon - locations updates are temporary monitored
        case departed   // on tour - locations updates are permanently recorded
        case arriving   // may arrive soon - find the current visit location
    }
    
    private let UDS_KEY_ACTIVE = "mobilitytracker_active"
    private let UDS_KEY_STATE = "mobilitytracker_state"
    private let UDS_KEY_TRACKER_ID = "mobilitytracker_tracker_id"
    private let UDS_KEY_ACCOUNT_ID = "mobilitytracker_account_id"
    private let UDS_KEY_TRAJECTORY_ID = "mobilitytracker_trajectory_id"
    
    private let FILENAME_VISIT_LOCATION = "mobilitytracker_visit_location.json"
    private let FILENAME_TRACKINGS = "mobilitytracker_trackings.json"
    private let FILENAME_VISITS = "mobilitytracker_visits.json"
    
    private let dispatchQueue = DispatchQueue(label: "mobilitytracker.tracking")
    private let locationManager = CLLocationManager()
    private let backgroundRunner = CLLocationManager()
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var timer: Timer?
    private var intervalTimer: Timer?
    
    private var trackerId: String
    private var accountId: String
    
    private let mobilityManager = MobilityManager()
    private let deviceManager = DeviceManager()
    private let carMode = CarMode()
    
    private var trajectory: String {
        get { return UserDefaults.standard.string(forKey: UDS_KEY_TRAJECTORY_ID) ?? "undefined" }
        set { UserDefaults.standard.set(newValue, forKey: UDS_KEY_TRAJECTORY_ID) }
    }
    
    
    private var _visitLocation: Tracking?
    private var _lastLocation: Location?
    private var _trackings: [Tracking]
    private var _visits: [Visit]
    private var _tempTrackings: [Tracking]
    
    
    // Mark - Public variables
    
    public var trackings: [Tracking] { get { return _trackings.sorted() } }
    public var delegate: TrackingManagerDelegate?
    
    
    // Mark - State variables
    
    public private(set) var active: Bool {
        get { return UserDefaults.standard.bool(forKey: UDS_KEY_ACTIVE) }
        set { UserDefaults.standard.set(newValue, forKey: UDS_KEY_ACTIVE) }
    }
    
    private var running: Bool = false
    
    private var state: State {
        get { return State(rawValue: UserDefaults.standard.integer(forKey: UDS_KEY_STATE)) ?? .undefined }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: UDS_KEY_STATE) }
    }
    
    public var stationary: Bool { get { return state != .departed && state != .arriving } }
    
    
    // Mark - Setup
    
    override init() {
        // restore data
        _visitLocation = Storage.fileExists(FILENAME_VISIT_LOCATION, in: .documents) ? Storage.retrieve(FILENAME_VISIT_LOCATION, from: .documents, as: Tracking.self) : nil
        _trackings = Storage.fileExists(FILENAME_TRACKINGS, in: .documents) ? Storage.retrieve(FILENAME_TRACKINGS, from: .documents, as: [Tracking].self) : []
        _visits = Storage.fileExists(FILENAME_VISITS, in: .documents) ? Storage.retrieve(FILENAME_VISITS, from: .documents, as: [Visit].self) : []
        _tempTrackings = []
        
        // set/restore tracker id
        if let id = UserDefaults.standard.string(forKey: UDS_KEY_TRACKER_ID) {
            trackerId = id
        } else if let id = UIDevice.current.identifierForVendor?.uuidString {
            UserDefaults.standard.set("ios-vid-\(id)", forKey: UDS_KEY_TRACKER_ID)
            trackerId = id
        } else {
            let id = "ios-uuid-\(UUID.init().uuidString)"
            UserDefaults.standard.set(id, forKey: UDS_KEY_TRACKER_ID)
            trackerId = id
        }
        
        // set/restore account id
        if let id = UserDefaults.standard.string(forKey: UDS_KEY_ACCOUNT_ID) {
            accountId = id
        } else {
            let data = Data (trackerId.utf8)
            var digest = [UInt8](repeating: 0, count:Int(CC_SHA1_DIGEST_LENGTH))
            data.withUnsafeBytes {
                _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest)
            }
            let hexBytes = digest.map { String(format: "%02hhx", $0) }
            let id = hexBytes.joined()
            UserDefaults.standard.set(id, forKey: UDS_KEY_ACCOUNT_ID)
            accountId = id
        }
        
        super.init()
        
        // setup location managers
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 20.0
        locationManager.delegate = self
        
        backgroundRunner.allowsBackgroundLocationUpdates = true
        backgroundRunner.pausesLocationUpdatesAutomatically = false
        backgroundRunner.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        backgroundRunner.distanceFilter = kCLLocationAccuracyThreeKilometers
        backgroundRunner.delegate = self
        
        // setup delegates
        mobilityManager.delegate = self
        deviceManager.delegate = self
        
        // restart if already activated/started
        if active {
            startTracking(requestPermission: false)
        }
    }
    
    
    // Mark - Manage start/stop tracking
    
    public func start() {
        guard !active else { return }
        active = true
        state = .undefined
        startTracking(requestPermission: false)
    }
    
    public func startAndRequestPermission() {
        guard !active else { return }
        active = true
        state = .undefined
        startTracking(requestPermission: true)
    }
    
    public func stop() {
        guard active else { return }
        active = false
        stopTracking()
    }
    
    
    // Mark - Internal stuff
    
    private func startTracking(requestPermission: Bool) {
        guard !running else { return }
        if active {
            running = true
            
            if locationManager.authorizationStatus == .authorizedAlways {

                // start keep alive service
                KeepAlive.shared.start()
                
                // start all services
                locationManager.startMonitoringVisits()
                mobilityManager.start()
                deviceManager.start()
                carMode.start()
                
                // setup state machine
                if state == .undefined {
                    // get initial location
                    locationManager.requestLocation()
                } else {
                    // recover state
                    let newState = state
                    state = .undefined
                    if newState == .arrived || newState == .departing {
                        change(state: .arrived)
                    } else if newState == .departed || newState == .arriving {
                        change(state: .departed)
                    }
                    
                }
                
            } else if locationManager.authorizationStatus == .notDetermined {
                // ask for location permission
                
                if requestPermission {
                    locationManager.requestAlwaysAuthorization()
                }
            } else {
                // insufficient location permission
                delegate?.trackingManager(self, error: NSError(domain: "MobilityTracker", code: 100, userInfo: [NSLocalizedDescriptionKey : "Insufficient location permission"]))
            }
        }
    }
    
    private func stopTracking() {
        guard running else { return }
        
        // stop services
        carMode.stop()
        mobilityManager.stop()
        deviceManager.stop()
        
        // turn tracking off
        state = .undefined
        locationManager.stopMonitoringVisits()
        stopUpdatingLocation()
        
        // reset all timers
        timer?.invalidate()
        timer = nil
        
        // remove geofences
        removeGeofences()
        
        // reset data
        resetTrackings()
        _tempTrackings = []
        _visitLocation = nil

        // stop keep alive service
        KeepAlive.shared.stop()
        running = false
        
    }
    
    private func change(state newState: State) {
        guard state != newState else { return }
        
        // set new state
        let oldState = state
        state = newState
        
        
        // reset all stuff from old states
        timer?.invalidate()
        timer = nil
        stopUpdatingLocation()
        
        if newState == .arrived {
            
            // if there is no visitLocation set initial visitLocation first
            if _visitLocation == nil {
                // reset initial location
                state = .undefined
                locationManager.requestLocation()
                return
            }
            
            // TODO: Start monitoring for indicators (e.g. pedometer)
            
            // notify delegate
            if (oldState == .departed || oldState == .arriving) && _trackings.count > 0 {
                let trackings = processTrip(visits: _visits, trackings: _trackings)
                delegate?.trackingManager(self, didDetect: trackings)
                if let visitLocation = _visitLocation {
                    delegate?.trackingManager(self, didArriveAt: visitLocation.location.location)
                }
            }
            
        } else if newState == .departing {
            
            // TODO: reuse temp trackings if they are not too old
            
            // clean up temp trackings
            _tempTrackings = []
            
            // start permanent location tracking for just one minute to watch if there is a departure within this time
            startUpdatingLocation()
            
            timer = Timer(timeInterval: 60.0, repeats: false, block: { (timer) in
                // discard temp trackings
                // TODO: maybe not required? Could be reused if departure is happending right after some seconds
                self._tempTrackings = []
                
                // switch back to arrived state
                self.change(state: .arrived)
            })
            timer?.tolerance = 5.0
            RunLoop.current.add(timer!, forMode: .common)
            
        } else if newState == .departed {
            
            if oldState == .arrived || oldState == .departing {
                
                // start new trip - take over temp trackings from departing state
                resetTrackings()
                takeoverTempTrackings()
                
                // start permanent location tracking
                startUpdatingLocation()
                
                // notify delegate
                if oldState != newState {
                    if let visitLocation = _visitLocation {
                        delegate?.trackingManager(self, didDepartAt: visitLocation.location.location)
                    }
                }
                
            } else if oldState == .arriving {
                takeoverTempTrackings()
            }
            
        } else if newState == .arriving {
            
            // clean up temp trackings
            _tempTrackings = []
            
            // start interval location tracking for two minutes to get the current location
            let startArriving = Date()
            locationManager.requestLocation()
            
            timer = Timer(timeInterval: 20.0, repeats: true, block: { (timer) in
                if abs(startArriving.timeIntervalSinceNow) < 110.0 {
                    self.locationManager.requestLocation()
                } else {
                    self.timer?.invalidate()
                    self.timer = nil
                    
                    // set visit location
                    if let location = self._tempTrackings.last?.location {
                        // TODO: check if there is enought information for finding a visit
                        // TODO: calculate center of last trackings
                        self.set(visit: location)
                        self.createGeofences(at: location)
                    } else if let location = self._trackings.last?.location {
                        self.set(visit: location)
                        self.createGeofences(at: location)
                        // TODO: self._trackings.last?.transport = .unknown
                    }
                    
                    // clean up temp trackings
                    self._tempTrackings = []
                    
                    // change state to arrived
                    self.change(state: .arrived)
                }
                
            })
            timer?.tolerance = 1.0
            RunLoop.current.add(timer!, forMode: .common)
        }
        
    }
    
    private func tracking(for location: Location) -> Tracking {
        
        // Get current context data
        let mobility = mobilityManager.mobility
        let activity = mobility.transport == .unknown ? "unknown" : "\(mobility.transport)-\(mobility.confidence)-\(mobility.motion)"
        let devices = ContextManager.connectedDevices()
        let wifis = ContextManager.connectedNetworks()
        let batteryLevel = ContextManager.batteryLevel()
        let externalPowerSupply = ContextManager.externalPowerSupply()
        let activeCarMode = carMode.active
        
        let context = Tracking.Context(activity: activity, carmode: activeCarMode, devices: devices, wifis: wifis, batteryLevel: batteryLevel, externalPowerSupply: externalPowerSupply)
        
        // update device statistics
        deviceManager.update(statisticsWith: activity, for: devices)
        
        // Guess transport state
        var transport: Tracking.Transport = .unknown
        
        // ...by activity recognition
        if mobility.confidence == .medium || mobility.confidence == .high {
            if mobility.transport == .car {
                transport = .car
            } else if mobility.transport == .bike {
                transport = .bike
            } else if mobility.transport == .foot {
                transport = .foot
            }
        }
        
        // ...by device statistics
        if deviceManager.isInCar() {
            transport = .car
        }
        
        // ...by CarMode
        if activeCarMode {
            transport = .car
        }
        
        return Tracking(tracker: trackerId, account: accountId, trajectory: trajectory, location: location, transport: transport, stationary: stationary, context: context)
    }
    
    
    
    // Mark - Start/stop continued location updates
    
    private func startUpdatingLocation() {
        // start background task
        backgroundRunner.startUpdatingLocation()
        backgroundRunner.startMonitoringSignificantLocationChanges()
        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(expirationHandler: {
                if self.backgroundTask != .invalid {
                    UIApplication.shared.endBackgroundTask(self.backgroundTask)
                    self.backgroundTask = .invalid
                }
            })
        }
        
        // start recording
        intervalTimer?.invalidate()
        locationManager.requestLocation()
        intervalTimer = Timer(timeInterval: 3.0, repeats: true, block: { (timer) in
            self.locationManager.requestLocation()
        })
        intervalTimer?.tolerance = 1.0
        RunLoop.current.add(intervalTimer!, forMode: .common)
    }
    
    private func stopUpdatingLocation() {
        intervalTimer?.invalidate()
        intervalTimer = nil
        
        // stop background task
        backgroundRunner.stopUpdatingLocation()
        backgroundRunner.stopMonitoringSignificantLocationChanges()
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    private func traveling(at location: Location) -> Bool {
        if let lastLocation = _lastLocation {
            if location.location.distance(from: lastLocation.location) > 50.0 {
                print("traveling: >50m")
                _lastLocation = location
                return true
            } else if location.timestamp.timeIntervalSince(lastLocation.timestamp) > 60.0 {
                print("NOT traveling: >60s (timeout)")
                return false
            }
            print("traveling: in distance but in time")
            return true
        }
        print("traveling: no reference location")
        _lastLocation = location
        return true
    }
    
    // Mark - Internal data management
    
    private func resetTrackings() {
        dispatchQueue.sync {
            trajectory = UUID().uuidString
            _trackings = []
            
            if let visitLocation = _visitLocation {
                // add last visit as first trajectory waypoint
                
                var location = visitLocation.location
                location.timestamp = Date() - 15.0
                let batteryLevel = ContextManager.batteryLevel()
                let externalPowerSupply = ContextManager.externalPowerSupply()
                let context = Tracking.Context(activity: "unknown", carmode: false, devices: [], wifis: [], batteryLevel: batteryLevel, externalPowerSupply: externalPowerSupply)
                
                _trackings.append(Tracking(tracker: trackerId, account: accountId, trajectory: trajectory, location: location, transport: .unknown, stationary: true, context: context))
            }
            Storage.store(_trackings, to: .documents, as: FILENAME_TRACKINGS)
        }
    }
    
    private func takeoverTempTrackings() {
        dispatchQueue.sync {
            // take over temp trackings
            _trackings.append(contentsOf: _tempTrackings)
            // update trip id
            for i in 0..<_trackings.count {
                _trackings[i].trajectory = trajectory
            }
            Storage.store(_trackings, to: .documents, as: FILENAME_TRACKINGS)
        }
    }
    
    private func add(tracking: Tracking) {
        dispatchQueue.sync {
            _trackings.append(tracking)
            Storage.store(_trackings, to: .documents, as: FILENAME_TRACKINGS)
        }
    }
    
    private func add(visit: Visit) {
        dispatchQueue.sync {
            _visits.append(visit)
            Storage.store(_visits, to: .documents, as: FILENAME_VISITS)
        }
    }
    
    private func set(visit location: Location) {
        dispatchQueue.sync {
            _visitLocation = tracking(for: location)
            Storage.store(_visitLocation, to: .documents, as: FILENAME_VISIT_LOCATION)
        }
    }
    
    
    
    private func processTrip(visits: [Visit], trackings: [Tracking]) -> [Tracking] {
        
        // TODO: Implement trip processing
        // - sort all trackings by timestamp
        // - cut off unrelevant trackings
        // - add start and end visit
        
        return trackings.sorted()
    }
    
    
    
    
    // Mark - Geofence management
    
    private func removeGeofences() {
        for region in locationManager.monitoredRegions {
            if region.identifier.starts(with: "mobilitytracker") {
                locationManager.stopMonitoring(for: region)
            }
        }
    }
    
    private func createGeofences(at location: Location) {
        removeGeofences()
        
        let speedRadius = location.speed < 10.0 ? 80.0 : location.speed * 15.0
        let accuracyRadius = speedRadius + location.horizontalAccuracy
        
        locationManager.startMonitoring(for: CLCircularRegion(center: location.coordinate, radius: speedRadius, identifier: "mobilitytracker-primary"))
        locationManager.startMonitoring(for: CLCircularRegion(center: location.coordinate, radius: accuracyRadius, identifier: "mobilitytracker-fallback"))
    }
    
    
    // Mark - MobilityManagerDelegate
    
    func mobilityManager(_ manager: MobilityManager, didChange mobility: Mobility, from oldMobility: Mobility) {
        if state == .arrived {
            if mobility.transport != oldMobility.transport {
                change(state: .departing)
                return
            }
        }
        
        if state == .departed {
            if mobility.transport != oldMobility.transport {
                requestLocation()
                return
            }
            
            if mobility.motion == .still && oldMobility.motion == .moving {
                requestLocation()
                return
            }
        }
    }
    
    func mobilityManagerMayLeaveCar(_ manager: MobilityManager) {
        requestLocation()
    }
    
    
    // Mark - DeviceManagerDelegate
    
    func deviceManager(_ manager: DeviceManager, didDetect device: Device) {
        delegate?.trackingManager(self, didDetect: device)
    }
    
    func deviceManager(_ manager: DeviceManager, didConnect device: Device) {
        // TODO: Update state to departing if connected to a carplay device
    }
    
    func deviceManager(_ manager: DeviceManager, didDisconnect device: Device) {
        // TODO: handle indicators
    }
    
    
    // Mark - CarModeDelegate
    
    func carMode(active: Bool) {
        if active {
            if state == .arrived {
                change(state: .departing)
            } else {
                requestLocation()
            }
        }
    }
    
    
    // Mark - CLLocationManagerDelegate
    
    private func requestLocation() {
        if state == .arrived || state == .undefined {
            locationManager.requestLocation()
        } else if state == .departing || state == .departed || state == .arriving {
            startUpdatingLocation()
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways:     startTracking(requestPermission: false)
        case .notDetermined:        break //if active { manager.requestAlwaysAuthorization() }
        default:                    delegate?.trackingManager(self, error: NSError(domain: "MobilityTracker", code: 100, userInfo: [NSLocalizedDescriptionKey : "Insufficient location permission"]))
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        add(visit: Visit(visit))
        requestLocation()
    }
    
    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        if manager == locationManager && region is CLCircularRegion && region.identifier.starts(with: "mobilitytracker") {
            if state == .arriving {
                change(state: .departed)
            } else if state == .arrived {
                change(state: .departing)
            } else {
                requestLocation()
            }
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if manager == locationManager {
            
            let location = locations.last!
            
            // get initial location to start tracking
            if state == .undefined {
                let loca = Location(location)
                set(visit: loca)
                createGeofences(at: loca)
                change(state: .arrived)
                return
            }
            
            // set speed depended distance filter
            if location.speed < 3.0 {
                manager.distanceFilter = 20.0
            } else if location.speed < 5.0 {
                manager.distanceFilter = 30.0
            } else if location.speed < 8.0 {
                manager.distanceFilter = 50.0
            } else if location.speed < 18.0 {
                manager.distanceFilter = 80.0
            } else {
                manager.distanceFilter = 120.0
            }
            
            
            // update geofence
            if state == .departed {
                let currentLocation = Location(location)
                if traveling(at: currentLocation) {
                    createGeofences(at: currentLocation)
                } else {
                    change(state: .arriving)
                }
            }
            
            // check if there is a departure event  // TODO: accuracy was 65.0
            if location.horizontalAccuracy <= 50.0 {
                if (state == .arrived || state == .departing) {
                    if let visitLocation = _visitLocation {
                        if visitLocation.location.location.distance(from: location) >= 80.0 {
                            // departure detected
                            change(state: .departed)
                        }
                    }
                } else if state == .arriving {
                    if _trackings.count > 0 {
                        if _trackings.sorted().last!.location.location.distance(from: location) > 80.0 {
                            // switch back to departed mode
                            change(state: .departed)
                        }
                    }
                }
            }
            
            // store tracking
            let tracking = self.tracking(for: Location(location))
            if state == .departing || state == .arriving {
                _tempTrackings.append(tracking)
            } else if state == .departed {
                add(tracking: tracking)
                
                // TEMP - TODO: remove later
                delegate?.trackingManager(self, didDetect: tracking)
            }
            
        }
    }
    
    
    // TODO: Notify error to delegate within this function
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        
        if let error = error as? CLError {
            switch error {
            case CLError.locationUnknown:
                if manager == locationManager {
                    // restart in 5 seconds if there was an error
                    DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 5.0) {
                        manager.requestLocation()
                    }
                }
            default:
                delegate?.trackingManager(self, error: error)
            }
        } else {
            delegate?.trackingManager(self, error: error)
        }
    }
    
}
