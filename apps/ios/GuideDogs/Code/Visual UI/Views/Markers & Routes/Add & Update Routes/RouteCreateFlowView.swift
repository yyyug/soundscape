//
//  RouteCreateFlowView.swift
//  Soundscape
//
//  Copyright (c) Microsoft Corporation.
//  Licensed under the MIT License.
//

import SwiftUI
import UIKit
import CoreLocation
import Combine

private enum RouteCreateMode {
    case manual
    case auto
}

private enum RouteManualTab: String, CaseIterable {
    case location
    case gps
}

struct RouteCreateFlowView: View {
    @EnvironmentObject var navHelper: ViewNavigationHelper

    @State private var routeName = ""
    @State private var selectedMode: RouteCreateMode?
    @State private var goToModeScreen = false

    private var trimmedName: String {
        routeName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var destination: AnyView {
        switch selectedMode {
        case .manual:
            return AnyView(RouteCreateManualView(routeName: trimmedName).environmentObject(navHelper))
        case .auto:
            return AnyView(RouteCreateAutoView(routeName: trimmedName).environmentObject(navHelper))
        case .none:
            return AnyView(EmptyView())
        }
    }

    var body: some View {
        Form {
            Section {
                TextField(GDLocalizedString("route_detail.name.default"), text: $routeName)
                    .autocapitalization(.words)
            } header: {
                Text(GDLocalizedString("route_detail.action.create"))
            }

            Section {
                Button(GDLocalizationUnnecessary("Manual Add Points")) {
                    selectedMode = .manual
                    goToModeScreen = true
                }
                .disabled(trimmedName.isEmpty)

                Button(GDLocalizationUnnecessary("Auto Mode")) {
                    selectedMode = .auto
                    goToModeScreen = true
                }
                .disabled(trimmedName.isEmpty)
            } footer: {
                Text(GDLocalizationUnnecessary("Enter route name first, then pick how to add points."))
            }

            NavigationLink(destination: destination, isActive: $goToModeScreen) {
                EmptyView()
            }
            .accessibilityHidden(true)
        }
        .navigationBarTitle(GDLocalizedTextView("route_detail.action.create"), displayMode: .inline)
    }
}

private struct RouteCreateManualView: View {
    @EnvironmentObject var navHelper: ViewNavigationHelper

    let routeName: String

    @State private var selectedTab: RouteManualTab = .location
    @State private var waypoints: [IdentifiableLocationDetail] = []

    @State private var showAlert = false
    @State private var alertMessage = ""

    var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: $selectedTab) {
                Text(GDLocalizedString("location")).tag(RouteManualTab.location)
                Text(GDLocalizationUnnecessary("GPS Position")).tag(RouteManualTab.gps)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)

            if selectedTab == .location {
                VStack(spacing: 12) {
                    NavigationLink(destination: WaypointAddList(waypoints: $waypoints)) {
                        Text(GDLocalizationUnnecessary("Select Saved Marker"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(GDLocalizationUnnecessary("Search by Location")) {
                        presentSearchWaypoint()
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
            } else {
                VStack(spacing: 12) {
                    Button(GDLocalizationUnnecessary("Add Current Location")) {
                        addCurrentLocation()
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)

                    Button(GDLocalizationUnnecessary("Remove Recently Added Point")) {
                        if !waypoints.isEmpty {
                            _ = waypoints.popLast()
                        }
                    }
                    .disabled(waypoints.isEmpty)
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
            }

            if waypoints.isEmpty {
                RouteEditTutorialView()
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
            } else {
                List {
                    WaypointEditList(identifiableWaypoints: $waypoints)
                }
                .environment(\.editMode, .constant(.active))
                .listStyle(PlainListStyle())
            }

            Button(GDLocalizedString("general.alert.done")) {
                saveRoute()
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.borderedProminent)
            .disabled(waypoints.count < 2)
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .background(Color.tertiaryBackground)
        .navigationBarTitle(GDLocalizationUnnecessary("Manual Add Points"), displayMode: .inline)
        .alert(isPresented: $showAlert) {
            Alert(title: Text(GDLocalizedString("general.error.error_occurred")),
                  message: Text(alertMessage),
                  dismissButton: .default(Text(GDLocalizedString("general.alert.dismiss"))))
        }
    }

    private func presentSearchWaypoint() {
        let storyboard = UIStoryboard(name: "POITable", bundle: Bundle.main)

        guard let navigationController = storyboard.instantiateViewController(identifier: "SearchWaypointNavigation") as? UINavigationController,
              let viewController = navigationController.topViewController as? SearchWaypointViewController else {
            return
        }

        viewController.routeName = routeName
        viewController.waypoints = $waypoints
        navigationController.accessibilityViewIsModal = true
        navHelper.present(navigationController, animated: true, completion: nil)
    }

    private func addCurrentLocation() {
        guard let location = AppContext.shared.geolocationManager.location else {
            alertMessage = GDLocalizedString("general.alert.error.message")
            showAlert = true
            return
        }

        let detail = LocationDetail(location: location, telemetryContext: "route_manual")

        do {
            let markerId = try ReferenceEntity.add(detail: detail, telemetryContext: "route_manual")

            guard let saved = LocationDetail(markerId: markerId) else {
                return
            }

            if !waypoints.contains(where: { $0.locationDetail.markerId == markerId }) {
                waypoints.append(IdentifiableLocationDetail(locationDetail: saved))
            }
        } catch {
            alertMessage = GDLocalizedString("general.alert.error.message")
            showAlert = true
        }
    }

    private func saveRoute() {
        let name = routeName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            alertMessage = GDLocalizedString("general.alert.error.message")
            showAlert = true
            return
        }

        do {
            let route = Route(name: name, description: nil, waypoints: waypoints.asRouteWaypoint)
            try Route.add(route)
            navHelper.popViewController(animated: true)
        } catch {
            alertMessage = GDLocalizedString("general.alert.error.message")
            showAlert = true
        }
    }
}

private final class RouteAutoRecorderStore: ObservableObject {
    enum State {
        case idle
        case recording
        case paused
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var routeLength: CLLocationDistance = 0.0
    @Published private(set) var sampleCount: Int = 0

    private var samples: [CLLocation] = []
    private var listener: NSObjectProtocol?

    deinit {
        stopListening()
    }

    func start() {
        samples = []
        routeLength = 0.0
        sampleCount = 0
        state = .recording
        startListening()
    }

    func pause() {
        guard state == .recording else {
            return
        }

        state = .paused
        stopListening()
    }

    func resume() {
        guard state == .paused else {
            return
        }

        state = .recording
        startListening()
    }

    func stopAndSave(routeName: String) throws {
        stopListening()
        state = .idle

        guard samples.count >= 2 else {
            throw RouteRealmError.invalidData
        }

        let markerDetails: [LocationDetail] = try samples.compactMap { location in
            let detail = LocationDetail(location: location, telemetryContext: "route_auto")
            let markerId = try ReferenceEntity.add(detail: detail, telemetryContext: "route_auto")
            return LocationDetail(markerId: markerId)
        }

        let route = Route(name: routeName, description: nil, waypoints: markerDetails.asRouteWaypoint)
        try Route.add(route)
    }

    private func startListening() {
        guard listener == nil else {
            return
        }

        listener = NotificationCenter.default.addObserver(forName: .locationUpdated, object: nil, queue: .main) { [weak self] notification in
            self?.handleLocationUpdated(notification)
        }
    }

    private func stopListening() {
        guard let listener = listener else {
            return
        }

        NotificationCenter.default.removeObserver(listener)
        self.listener = nil
    }

    private func handleLocationUpdated(_ notification: Notification) {
        guard let location = notification.userInfo?[SpatialDataContext.Keys.location] as? CLLocation else {
            return
        }

        guard location.horizontalAccuracy >= 0.0, location.horizontalAccuracy <= 40.0 else {
            return
        }

        if let last = samples.last {
            let elapsed = location.timestamp.timeIntervalSince(last.timestamp)
            let speed = max(location.speed, 0.0)
            let minInterval = recommendedInterval(for: speed)

            if elapsed < minInterval {
                return
            }

            let distance = location.distance(from: last)
            let minDistance = max(3.0, speed * minInterval * 0.5)

            if speed < 0.2 && distance > 20.0 {
                return
            }

            if distance < minDistance {
                return
            }

            if distance > 80.0 && elapsed < 3.0 {
                return
            }

            routeLength += distance
        }

        samples.append(location)
        sampleCount = samples.count
    }

    private func recommendedInterval(for speed: CLLocationSpeed) -> TimeInterval {
        switch speed {
        case ..<0.5:
            return 5.0
        case ..<1.0:
            return 3.0
        case ..<2.0:
            return 2.0
        default:
            return 1.0
        }
    }
}

private struct RouteCreateAutoView: View {
    @EnvironmentObject var navHelper: ViewNavigationHelper

    let routeName: String

    @StateObject private var recorder = RouteAutoRecorderStore()
    @State private var showAlert = false
    @State private var alertMessage = ""

    private var distanceText: String {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .medium

        if recorder.routeLength >= 1000 {
            return formatter.string(from: Measurement(value: recorder.routeLength / 1000.0, unit: UnitLength.kilometers))
        }

        return formatter.string(from: Measurement(value: recorder.routeLength, unit: UnitLength.meters))
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(GDLocalizationUnnecessary("Recorded Route Length"))
                .font(.headline)

            Text(distanceText)
                .font(.title)
                .fontWeight(.bold)

            Text(GDLocalizationUnnecessary("Recorded Points: \(recorder.sampleCount)"))
                .font(.callout)

            HStack(spacing: 12) {
                Button(GDLocalizationUnnecessary("Start")) {
                    recorder.start()
                }
                .disabled(recorder.state == .recording)
                .buttonStyle(.borderedProminent)

                Button(GDLocalizationUnnecessary("Pause")) {
                    recorder.pause()
                }
                .disabled(recorder.state != .recording)
                .buttonStyle(.bordered)

                Button(GDLocalizationUnnecessary("Resume")) {
                    recorder.resume()
                }
                .disabled(recorder.state != .paused)
                .buttonStyle(.bordered)
            }

            Button(GDLocalizationUnnecessary("Stop and Save Route")) {
                stopAndSave()
            }
            .buttonStyle(.borderedProminent)
            .disabled(recorder.sampleCount < 2)

            Spacer()
        }
        .padding(24)
        .navigationBarTitle(GDLocalizationUnnecessary("Auto Mode"), displayMode: .inline)
        .alert(isPresented: $showAlert) {
            Alert(title: Text(GDLocalizedString("general.error.error_occurred")),
                  message: Text(alertMessage),
                  dismissButton: .default(Text(GDLocalizedString("general.alert.dismiss"))))
        }
    }

    private func stopAndSave() {
        do {
            try recorder.stopAndSave(routeName: routeName)
            navHelper.popViewController(animated: true)
        } catch {
            alertMessage = GDLocalizedString("general.alert.error.message")
            showAlert = true
        }
    }
}
