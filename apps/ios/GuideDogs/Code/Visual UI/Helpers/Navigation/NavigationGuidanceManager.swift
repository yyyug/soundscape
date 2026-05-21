//
//  NavigationGuidanceManager.swift
//  Soundscape
//
//  Copyright (c) Microsoft Corporation.
//  Licensed under the MIT License.
//

import Foundation
import CoreLocation
import MapKit

extension Notification.Name {
    /// Posted on the main queue when the current navigation step text changes.
    /// userInfo key: NavigationGuidanceManager.Keys.stepText (String?)
    static let navigationStepDidUpdate = Notification.Name("NavigationStepDidUpdate")
}

/// Listens for audio beacon changes and provides walking navigation step text
/// from Apple Maps (MKDirections) without displaying any map overlay.
final class NavigationGuidanceManager {

    // MARK: - Keys

    struct Keys {
        static let stepText = "NavigationStepText"
    }

    // MARK: - Singleton

    static let shared = NavigationGuidanceManager()

    // MARK: - Private state

    private var currentRoute: MKRoute?
    private var currentStepIndex: Int = 0
    private var destinationCoordinate: CLLocationCoordinate2D?

    /// Minimum distance (metres) the user must travel before the step index advances.
    private let stepAdvanceDistance: CLLocationDistance = 20.0

    private var destinationObserver: NSObjectProtocol?
    private var locationObserver: NSObjectProtocol?

    // MARK: - Init / deinit

    private init() {
        startListening()
    }

    deinit {
        stopListening()
    }

    // MARK: - Listening

    private func startListening() {
        destinationObserver = NotificationCenter.default.addObserver(
            forName: .destinationChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleDestinationChanged(notification)
        }

        locationObserver = NotificationCenter.default.addObserver(
            forName: .locationUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleLocationUpdated(notification)
        }
    }

    private func stopListening() {
        if let o = destinationObserver { NotificationCenter.default.removeObserver(o) }
        if let o = locationObserver { NotificationCenter.default.removeObserver(o) }
    }

    // MARK: - Destination handling

    private func handleDestinationChanged(_ notification: Notification) {
        // When destination key is nil the beacon was removed
        let key = notification.userInfo?[DestinationManager.Keys.destinationKey] as? String

        guard let key = key else {
            clearGuidance()
            return
        }

        // Resolve the marker location
        guard let entity = SpatialDataCache.referenceEntityByKey(key) else {
            clearGuidance()
            return
        }

        let coordinate = CLLocationCoordinate2D(latitude: entity.latitude, longitude: entity.longitude)
        startGuidance(to: coordinate)
    }

    private func startGuidance(to coordinate: CLLocationCoordinate2D) {
        destinationCoordinate = coordinate
        currentRoute = nil
        currentStepIndex = 0
        postStepUpdate(nil)

        guard let userLocation = AppContext.shared.geolocationManager.location else { return }
        requestRoute(from: userLocation.coordinate, to: coordinate)
    }

    private func clearGuidance() {
        destinationCoordinate = nil
        currentRoute = nil
        currentStepIndex = 0
        postStepUpdate(nil)
    }

    // MARK: - Route calculation

    private func requestRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .walking
        request.requestsAlternateRoutes = false

        let directions = MKDirections(request: request)
        directions.calculate { [weak self] response, error in
            guard let self = self else { return }

            DispatchQueue.main.async {
                if let error = error {
                    GDLogAppInfo("NavigationGuidanceManager: route calculation failed – \(error.localizedDescription)")
                    return
                }

                guard let route = response?.routes.first else { return }

                // Only apply the route if the destination hasn't changed while we were calculating
                guard let dest = self.destinationCoordinate else { return }
                let routeDestCoord = route.steps.last?.polyline.coordinate ?? destination
                let destLocation = CLLocation(latitude: dest.latitude, longitude: dest.longitude)
                let routeDestLocation = CLLocation(latitude: routeDestCoord.latitude, longitude: routeDestCoord.longitude)
                guard routeDestLocation.distance(from: destLocation) < 200 else { return }

                self.currentRoute = route
                self.currentStepIndex = 0
                self.postCurrentStep()
            }
        }
    }

    // MARK: - Location updates

    private func handleLocationUpdated(_ notification: Notification) {
        guard let location = notification.userInfo?[SpatialDataContext.Keys.location] as? CLLocation else { return }
        guard let route = currentRoute else {
            // No route yet – try to (re)calculate if we have a destination
            if let dest = destinationCoordinate {
                requestRoute(from: location.coordinate, to: dest)
            }
            return
        }

        advanceStepIfNeeded(userLocation: location, route: route)
    }

    private func advanceStepIfNeeded(userLocation: CLLocation, route: MKRoute) {
        let steps = route.steps.filter { !$0.instructions.isEmpty }
        guard !steps.isEmpty else { return }

        // Clamp index
        var idx = min(currentStepIndex, steps.count - 1)

        // Check if the user has passed the end point of the current step
        if idx < steps.count - 1 {
            let nextStep = steps[idx + 1]
            let nextStepLocation = CLLocation(latitude: nextStep.polyline.coordinate.latitude,
                                              longitude: nextStep.polyline.coordinate.longitude)
            if userLocation.distance(from: nextStepLocation) < stepAdvanceDistance {
                idx += 1
            }
        }

        if idx != currentStepIndex {
            currentStepIndex = idx
            postCurrentStep()
        }
    }

    // MARK: - Posting

    private func postCurrentStep() {
        guard let route = currentRoute else { return }
        let steps = route.steps.filter { !$0.instructions.isEmpty }
        guard !steps.isEmpty else { postStepUpdate(nil); return }
        let idx = min(currentStepIndex, steps.count - 1)
        let step = steps[idx]
        postStepUpdate(step.instructions)
    }

    private func postStepUpdate(_ text: String?) {
        let userInfo: [AnyHashable: Any]? = text.map { [Keys.stepText: $0] }
        NotificationCenter.default.post(
            name: .navigationStepDidUpdate,
            object: self,
            userInfo: userInfo
        )
    }
}
