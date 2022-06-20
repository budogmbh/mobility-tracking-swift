//
//  MobilityManager.swift
//  iOS activity wrapper, reacting on transport mode changes
//
//  Created by Tobias Frech on 20.05.19.
//  Copyright © 2018-2022 budo GmbH. All rights reserved.
//

import Foundation
import CoreMotion
import CoreLocation


protocol MobilityManagerDelegate {
    func mobilityManager(_ manager: MobilityManager, didChange mobility: Mobility, from oldMobility: Mobility)
    func mobilityManagerMayLeaveCar(_ manager: MobilityManager)
}

class MobilityManager: NSObject {
    
    private let UDS_KEY_TRANSPORT = "mobilitytracker_mobility_transport"
    private let UDS_KEY_CONFIDENCE = "mobilitytracker_mobility_confidence"
    private let UDS_KEY_MOTION = "mobilitytracker_mobility_motion"
    private let UDS_KEY_STARTDATE = "mobilitytracker_mobility_startDate"
    
    var delegate: MobilityManagerDelegate?
    private var activity: CMMotionActivity?
    private let activityManager = CMMotionActivityManager()
    public private(set) var active = false
    private var started = false
    private var mayLeaveCar = false
    
    public private(set) var transport: Mobility.Transport {
        get { return Mobility.Transport(rawValue: UserDefaults.standard.integer(forKey: "mobilitytracker_transport")) ?? .unknown }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "mobilitytracker_transport") }
    }
    
    public private(set) var confidence: Mobility.Confidence {
        get { return Mobility.Confidence(rawValue: UserDefaults.standard.integer(forKey: "mobilitytracker_confidence")) ?? .low }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "mobilitytracker_confidence") }
    }
    
    public private(set) var motion: Mobility.Motion {
        get { return Mobility.Motion(rawValue: UserDefaults.standard.integer(forKey: "mobilitytracker_motion")) ?? .unknown }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "mobilitytracker_motion") }
    }
    
    public private(set) var startDate: Date {
        get { return Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "mobilitytracker_mobility_startDate")) }
        set { UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: "mobilitytracker_mobility_startDate") }
    }
    
    public var mobility: Mobility {
        get {
            if active && !started { start() }
            return Mobility(startDate: startDate, transport: transport, confidence: confidence, motion: motion)
        }
    }
    
    public func findMobility(at timestamp: Date, _ closure: @escaping (_ mobility: Mobility) -> Void) {
        var mobility = Mobility.Unknown
        activityManager.queryActivityStarting(from: timestamp.addingTimeInterval(-86400.0), to: timestamp, to: OperationQueue.main) { (activities, error) in
            if error == nil && activities != nil {
                for activity in activities!.filter({$0.confidence != .low}).reversed() {
                    if mobility.motion == .unknown {
                        mobility.motion = activity.stationary ? .still : .moving
                        mobility.confidence = Mobility.Confidence(rawValue: activity.confidence.rawValue) ?? .low
                        mobility.startDate = activity.startDate
                    }
                    if mobility.transport == .unknown {
                        if activity.automotive {
                            mobility.transport = .car
                        } else if activity.walking || activity.running {
                            mobility.transport = .foot
                        } else if activity.cycling {
                            mobility.transport = .bike
                        }
                    }
                    if mobility.motion != .unknown && mobility.transport != .unknown {
                        closure(mobility)
                        return
                    }
                }
            }
            closure(mobility)
        }
    }
    
    
    func start() {
        active = true

        guard CMMotionActivityManager.isActivityAvailable(), CMMotionActivityManager.authorizationStatus() == .authorized else {
            handleMobility(Mobility.Unknown)
            return
        }

        findMobility(at: Date()) { (mobility) in
            if self.motion == .unknown || self.transport == .unknown {
                self.transport = mobility.transport
                self.motion = mobility.motion
            } else {
                self.handleMobility(mobility)
            }
        }
        
        // start watching activity
        activityManager.startActivityUpdates(to: OperationQueue.main) { activity in
            if let activity = activity {
                DispatchQueue.main.async {
                    self.handleActivity(activity)
                }
            }
        }
        
        started = true
    }
    
    func stop() {
        activityManager.stopActivityUpdates()
        active = false
        started = false
    }
    
    private func handleActivity(_ activity: CMMotionActivity) {
        // handle first event
        if transport == .unknown || motion == .unknown {
            guard activity.confidence != .low else { return }
            if activity.automotive {
                transport = .car
                motion = activity.stationary ? .still : .moving
            } else if activity.cycling {
                transport = .bike
                motion = .moving
            } else if activity.walking || activity.running {
                transport = .foot
                motion = .moving
            } else if activity.stationary {
                transport = .foot
                motion = .still
            }
            return
        }
        
        // get confidence level
        let confidence = Mobility.Confidence(rawValue: activity.confidence.rawValue) ?? .low
        
        // handle event while in car
        if transport == .car {
            if activity.confidence == .medium || activity.confidence == .high {
                if activity.automotive {
                    mayLeaveCar = false
                    handleMobility(Mobility(startDate: activity.startDate, transport: .car, confidence: confidence, motion: activity.stationary ? .still : .moving))
                } else if activity.cycling {
                    mayLeaveCar = false
                    handleMobility(Mobility(startDate: activity.startDate, transport: .bike, confidence: confidence, motion: .moving))
                } else if activity.walking || activity.running {
                    mayLeaveCar = false
                    handleMobility(Mobility(startDate: activity.startDate, transport: .foot, confidence: confidence, motion: .moving))
                } else if !mayLeaveCar {
                    mayLeaveCar = true
                    delegate?.mobilityManagerMayLeaveCar(self)
                }
            } else  if !mayLeaveCar {
                if !activity.automotive && !activity.cycling && !activity.walking && !activity.running && !activity.stationary {
                    mayLeaveCar = true
                    delegate?.mobilityManagerMayLeaveCar(self)
                }
            }
            return
        }
        
        // handle event while on bike
        if transport == .bike {
            guard activity.confidence != .low else { return }
            if activity.stationary {
                handleMobility(Mobility(startDate: activity.startDate, transport: .bike, confidence: confidence, motion: .still))
            } else if activity.automotive {
                handleMobility(Mobility(startDate: activity.startDate, transport: .car, confidence: confidence, motion: activity.stationary ? .still : .moving))
            } else if activity.walking || activity.running {
                handleMobility(Mobility(startDate: activity.startDate, transport: .foot, confidence: confidence, motion: .moving))
            } else if activity.cycling {
                handleMobility(Mobility(startDate: activity.startDate, transport: .bike, confidence: confidence, motion: .moving))
            }
            return
        }
        
        // handle event while on foot
        if transport == .foot {
            guard activity.confidence != .low else { return }
            if activity.stationary {
                handleMobility(Mobility(startDate: activity.startDate, transport: .foot, confidence: confidence, motion: .still))
            } else if activity.automotive {
                handleMobility(Mobility(startDate: activity.startDate, transport: .car, confidence: confidence, motion: activity.stationary ? .still : .moving))
            } else if activity.cycling {
                handleMobility(Mobility(startDate: activity.startDate, transport: .bike, confidence: confidence, motion: .moving))
            } else if activity.walking || activity.running {
                handleMobility(Mobility(startDate: activity.startDate, transport: .foot, confidence: confidence, motion: .moving))
            }
            return
        }
    }
    
    private func handleMobility(_ mobility: Mobility) {
        if transport != mobility.transport || motion != mobility.motion || confidence != mobility.confidence {
            let oldMobility = Mobility(startDate: startDate, transport: transport, confidence: confidence, motion: motion)
            startDate = mobility.startDate
            transport = mobility.transport
            confidence = mobility.confidence
            motion = mobility.motion
            delegate?.mobilityManager(self, didChange: mobility, from: oldMobility)
        }
    }
    
}

