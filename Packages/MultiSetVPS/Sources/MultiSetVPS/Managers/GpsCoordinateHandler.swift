/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Foundation
import Combine
import CoreLocation

/// Internal handler class for GPS coordinate retrieval
internal class GpsCoordinateHandler: NSObject, ObservableObject, CLLocationManagerDelegate {

    // MARK: - Published Properties

    @Published var gpsCoordinates = GeoCoordinates()
    @Published var isEnabled = false
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    // MARK: - Private Properties

    private var locationManager: CLLocationManager?
    private var permissionCallback: ((Bool) -> Void)?

    // MARK: - Computed Properties

    var isGpsOn: Bool {
        return isEnabled && locationManager != nil
    }

    var hasValidCoordinates: Bool {
        return gpsCoordinates.isValid()
    }

    // MARK: - Initialization

    override init() {
        super.init()
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.desiredAccuracy = kCLLocationAccuracyBest
        locationManager?.distanceFilter = 1.0

        if let manager = locationManager {
            authorizationStatus = manager.authorizationStatus
        }
    }

    // MARK: - Public Methods

    func hasLocationPermission() -> Bool {
        let status = locationManager?.authorizationStatus ?? .notDetermined
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }

    func isLocationEnabled() -> Bool {
        return CLLocationManager.locationServicesEnabled()
    }

    func requestPermission(completion: ((Bool) -> Void)? = nil) {
        permissionCallback = completion

        guard isLocationEnabled() else {
            print("MultiSetVPS >> Location services are disabled")
            completion?(false)
            return
        }

        let status = locationManager?.authorizationStatus ?? .notDetermined

        switch status {
        case .notDetermined:
            print("MultiSetVPS >> Requesting location permission")
            locationManager?.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            print("MultiSetVPS >> Location permission already granted")
            completion?(true)
        case .denied, .restricted:
            print("MultiSetVPS >> Location permission denied")
            completion?(false)
        @unknown default:
            completion?(false)
        }
    }

    @discardableResult
    func startUpdates() -> Bool {
        guard hasLocationPermission() else {
            print("MultiSetVPS >> Location permission not granted")
            return false
        }

        guard isLocationEnabled() else {
            print("MultiSetVPS >> Location services are disabled")
            return false
        }

        locationManager?.startUpdatingLocation()
        isEnabled = true

        if let location = locationManager?.location {
            updateCoordinates(from: location)
            print("MultiSetVPS >> Initial coordinates set from last known location")
        } else {
            print("MultiSetVPS >> No last known location available - waiting for GPS fix")
        }

        print("MultiSetVPS >> GPS handler enabled")
        return true
    }

    func stopUpdates() {
        locationManager?.stopUpdatingLocation()
        isEnabled = false
        print("MultiSetVPS >> GPS handler stopped")
    }

    func getCurrentCoordinates() -> GeoCoordinates {
        return GeoCoordinates(
            latitude: gpsCoordinates.latitude,
            longitude: gpsCoordinates.longitude,
            altitude: gpsCoordinates.altitude
        )
    }

    // MARK: - Private Methods

    private func updateCoordinates(from location: CLLocation) {
        gpsCoordinates = GeoCoordinates(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude
        )
        print("MultiSetVPS >> GPS coordinates updated: \(gpsCoordinates.toGeoHintString())")
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        updateCoordinates(from: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("MultiSetVPS >> Location error: \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            print("MultiSetVPS >> Location permission granted")
            locationManager?.startUpdatingLocation()
            isEnabled = true
            permissionCallback?(true)
        case .denied, .restricted:
            print("MultiSetVPS >> Location permission denied")
            permissionCallback?(false)
        case .notDetermined:
            print("MultiSetVPS >> Location permission not determined")
        @unknown default:
            break
        }

        permissionCallback = nil
    }
}
