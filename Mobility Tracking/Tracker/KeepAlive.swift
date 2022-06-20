//
//  KeepAlive.swift
//  Keeps the app in background alive using background location services
//  while consuming only a small amount of energy
//
//  Created by Tobias Frech on 07.11.18.
//  Copyright © 2018-2022 budo GmbH. All rights reserved.
//

import Foundation
import UIKit
import CoreLocation


class KeepAlive: NSObject, CLLocationManagerDelegate {
    
    private let dispatchQueue = DispatchQueue(label: "de.budo.keepalive")
    private let locationManager = CLLocationManager()
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var timer: Timer?
    private var isKeepingAlive = false
    private var updatingLocation = false
    public static let shared = KeepAlive()
    
    override private init() {
        super.init()
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        locationManager.distanceFilter = kCLLocationAccuracyThreeKilometers
        locationManager.delegate = self
    }
    
    // Mark - start/stop keeping alive
    
    public func start() {
        addObserver()
        if Thread.isMainThread {
            if UIApplication.shared.applicationState == .background { startAliveKeeping() }
        } else {
            DispatchQueue.main.sync {
                if UIApplication.shared.applicationState == .background { startAliveKeeping() }
            }
        }
    }
    
    public func stop() {
        removeObserver()
        stopAliveKeeping()
    }
    
    
    // Mark - Internal stuff
    
    @objc private func startAliveKeeping() {
        guard !isKeepingAlive else { return }
        
        isKeepingAlive = true
        
        updatingLocation = true
        locationManager.startUpdatingLocation()
        
        startBackgroundTask()
        
        setupTimer()
    }
    
    
    @objc private func stopAliveKeeping() {
        isKeepingAlive = false
        timer?.invalidate()
        timer = nil
        locationManager.stopUpdatingLocation()
        updatingLocation = false
        stopBackgroundTask()
    }
    
    private func addObserver() {
        removeObserver()
        NotificationCenter.default.addObserver(self, selector:  #selector(startAliveKeeping), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(stopAliveKeeping), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    private func removeObserver() {
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    @objc private func startBackgroundTask() {
        stopBackgroundTask()
       
        backgroundTask = UIApplication.shared.beginBackgroundTask(expirationHandler: {
            self.stopAliveKeeping()
            if self.backgroundTask != .invalid {
                self.stopBackgroundTask()
            }
        })
    }
    
    @objc private func stopBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    private func setupTimer() {
        timer?.invalidate()
        timer = Timer(timeInterval: 2.0, repeats: true, block: { (timer) in
            let remainingTime = UIApplication.shared.backgroundTimeRemaining
            self.dispatchQueue.async {
                if remainingTime < 20.0 {
                  if !self.updatingLocation {
                    self.updatingLocation = true
                    self.locationManager.startUpdatingLocation()
                    self.locationManager.requestLocation()
                  }
               }
            }
        })
        timer?.tolerance = 1.0
        RunLoop.current.add(timer!, forMode: .common)
    }
    
    // Mark - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if updatingLocation {
            self.updatingLocation = false
            self.startBackgroundTask()
            usleep(2000)
            self.locationManager.stopUpdatingLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("didFailWithError:",error)
    }
    
}
