//
//  AppDelegate.swift
//  Mobility Tracking
//
//  Created by Tobias Frech on 18.06.22.
//

import UIKit
import CoreLocation

let mobilityTracker = TrackingManager()

@main
class AppDelegate: UIResponder, UIApplicationDelegate, TrackingManagerDelegate {

    private let permission = Permission()

    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        

        // OPTIONAL:
        /*
        // check if application was started due to (background) location update
        // this variable is useful to prevent energy intensive data calculation in background
        // if app was only started to detect location changes
        var didStartFromLocation = false
        if let options = launchOptions, let _ =
            options[UIApplication.LaunchOptionsKey.location] {
            didStartFromLocation = true
        }
        */
        
        mobilityTracker.delegate = self
        mobilityTracker.start()
       
        /*
        // Reactivate Mobility Tracker if permission is already given
        if permission.locationStatus() == .authorized {
            print("reactivation")
            mobilityTracker.start()
        }
        */

        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }


    // Mark - TrackingManagerDelegate
    
    func trackingManager(_ manager: TrackingManager, didDetect newDevice: Device) {
        // handle new detected devices (bluetooth hfp and carplay)
        print("new device or car (bluetooth hfp or carplay) detected:", newDevice)
    }
    
    func trackingManager(_ manager: TrackingManager, didDetect tracking: Tracking) {
        // just used for testing purposes
    }
    
    func trackingManager(_ manager: TrackingManager, didDetect trackings: [Tracking]) {
        // calculate distance with different mobility types or devices
    }
    
    func trackingManager(_ manager: TrackingManager, didDepartAt origin: CLLocation) {
        // handle departure event
    }
    
    func trackingManager(_ manager: TrackingManager, didArriveAt location: CLLocation) {
        // handle arrival event
    }
    
    func trackingManager(_ manager: TrackingManager, error: Error) {
        // handle errors
    }
    

}

