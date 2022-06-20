//
//  ViewController.swift
//  Mobility Tracking
//
//  Created by Tobias Frech on 18.06.22.
//

import UIKit
import MapKit
import CoreLocation

class ViewController: UIViewController, PermissionDelegate {

//    @IBOutlet var mapView: MKMapView!
    
    // Permission helper to request location and motion permission
    private let permission = Permission()

    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        
        // Ask for permission and start Mobility Tracker
        // TODO: Old permission behavior!!
        permission.delegate = self
        permission.requestLocation { (status) in
            print("location status:",status)
            if status == .authorized {
                self.permission.requestMotion { (status) in
                    print("motion status:",status)
                    mobilityTracker.start()
                }
            } else {
                print("Warning: Insufficient location permission to run Mobility Tracker")
            }
        }
    }

    

    // Mark - PermissionDelegate
    
    func permission(locationPermission: PermissionStatus) {
        print("location permission changed to:", locationPermission)
    }
    




}

