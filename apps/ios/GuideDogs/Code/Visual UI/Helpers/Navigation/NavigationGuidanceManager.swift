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

    private struct GoogleStep {
        let instruction: String
        let endCoordinate: CLLocationCoordinate2D
    }

    private enum ActiveRoute {
        case apple(MKRoute)
        case google([GoogleStep])
    }

    private struct GoogleComputeRoutesRequest: Encodable {
        let origin: Waypoint
        let destination: Waypoint
        let travelMode: String

        struct Waypoint: Encodable {
            let location: Location
        }

        struct Location: Encodable {
            let latLng: LatLng
        }

        struct LatLng: Encodable {
            let latitude: Double
            let longitude: Double
        }
    }

    private struct GoogleComputeRoutesResponse: Decodable {
        let routes: [Route]?

        struct Route: Decodable {
            let legs: [Leg]?
        }

        struct Leg: Decodable {
            let steps: [Step]?
        }

        struct Step: Decodable {
            let navigationInstruction: NavigationInstruction?
            let endLocation: EndLocation?
        }

        struct NavigationInstruction: Decodable {
            let instructions: String?
        }

        struct EndLocation: Decodable {
            let latLng: LatLng?
        }

        struct LatLng: Decodable {
            let latitude: Double?
            let longitude: Double?
        }
    }

    // MARK: - Keys

    struct Keys {
        static let stepText = "NavigationStepText"
    }

    // MARK: - Singleton

    static let shared = NavigationGuidanceManager()

    // MARK: - Private state

    private var currentRoute: ActiveRoute?
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
        switch SettingsContext.shared.navigationRouteProvider {
        case .appleMaps:
            requestAppleRoute(from: origin, to: destination)
        case .googleRoutesAPI:
            requestGoogleRoute(from: origin, to: destination)
        }
    }

    private func requestAppleRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) {
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

                self.currentRoute = .apple(route)
                self.currentStepIndex = 0
                self.postCurrentStep()
            }
        }
    }

    private func requestGoogleRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) {
        let key = SettingsContext.shared.googleMapsPlatformAPIKey
        guard !key.isEmpty else {
            currentRoute = nil
            postStepUpdate(GDLocalizedString("navigation.route.google.missing_key"))
            return
        }

        guard let url = URL(string: "https://routes.googleapis.com/directions/v2:computeRoutes") else {
            currentRoute = nil
            postStepUpdate(GDLocalizedString("navigation.route.google.failed"))
            return
        }

        let payload = GoogleComputeRoutesRequest(
            origin: .init(location: .init(latLng: .init(latitude: origin.latitude, longitude: origin.longitude))),
            destination: .init(location: .init(latLng: .init(latitude: destination.latitude, longitude: destination.longitude))),
            travelMode: "WALK"
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("routes.legs.steps.navigationInstruction.instructions,routes.legs.steps.endLocation", forHTTPHeaderField: "X-Goog-FieldMask")

        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            currentRoute = nil
            postStepUpdate(GDLocalizedString("navigation.route.google.failed"))
            return
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            DispatchQueue.main.async {
                if error != nil {
                    self.currentRoute = nil
                    self.postStepUpdate(GDLocalizedString("navigation.route.google.failed"))
                    return
                }

                guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode), let data = data else {
                    self.currentRoute = nil
                    self.postStepUpdate(GDLocalizedString("navigation.route.google.failed"))
                    return
                }

                let decoded: GoogleComputeRoutesResponse
                do {
                    decoded = try JSONDecoder().decode(GoogleComputeRoutesResponse.self, from: data)
                } catch {
                    self.currentRoute = nil
                    self.postStepUpdate(GDLocalizedString("navigation.route.google.failed"))
                    return
                }

                let steps = self.mapGoogleSteps(decoded)
                guard !steps.isEmpty else {
                    self.currentRoute = nil
                    self.postStepUpdate(GDLocalizedString("navigation.route.google.failed"))
                    return
                }

                self.currentRoute = .google(steps)
                self.currentStepIndex = 0
                self.postCurrentStep()
            }
        }.resume()
    }

    private func mapGoogleSteps(_ response: GoogleComputeRoutesResponse) -> [GoogleStep] {
        guard let route = response.routes?.first,
              let leg = route.legs?.first,
              let rawSteps = leg.steps else {
            return []
        }

        return rawSteps.compactMap { step in
            guard let text = step.navigationInstruction?.instructions,
                  !text.isEmpty,
                  let lat = step.endLocation?.latLng?.latitude,
                  let lon = step.endLocation?.latLng?.longitude else {
                return nil
            }

            return GoogleStep(instruction: text, endCoordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
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

        switch route {
        case .apple(let appleRoute):
            advanceAppleStepIfNeeded(userLocation: location, route: appleRoute)
        case .google(let googleSteps):
            advanceGoogleStepIfNeeded(userLocation: location, steps: googleSteps)
        }
    }

    private func advanceAppleStepIfNeeded(userLocation: CLLocation, route: MKRoute) {
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

    private func advanceGoogleStepIfNeeded(userLocation: CLLocation, steps: [GoogleStep]) {
        guard !steps.isEmpty else { return }

        var idx = min(currentStepIndex, steps.count - 1)

        if idx < steps.count - 1 {
            let next = steps[idx + 1]
            let nextLocation = CLLocation(latitude: next.endCoordinate.latitude, longitude: next.endCoordinate.longitude)
            if userLocation.distance(from: nextLocation) < stepAdvanceDistance {
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

        switch route {
        case .apple(let appleRoute):
            let steps = appleRoute.steps.filter { !$0.instructions.isEmpty }
            guard !steps.isEmpty else { postStepUpdate(nil); return }
            let idx = min(currentStepIndex, steps.count - 1)
            let step = steps[idx]
            postStepUpdate(step.instructions)
        case .google(let googleSteps):
            guard !googleSteps.isEmpty else { postStepUpdate(nil); return }
            let idx = min(currentStepIndex, googleSteps.count - 1)
            let step = googleSteps[idx]
            postStepUpdate(step.instruction)
        }
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
