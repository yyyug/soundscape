# iOS File Function Map (GuideDogs)

This document is a quick index for where core behaviors live, so feature work does not require repeated full-repo searching.

## App-Level Wiring

- `apps/ios/GuideDogs/Code/App/App Context/AppContext.swift`
  - Global dependency graph and shared runtime contexts.
  - Entry point for event processing (`AppContext.process`).
- `apps/ios/GuideDogs/Code/App/App Delegate/AppDelegate.swift`
  - App startup flow, service/context bootstrapping, notification wiring.

## Spatial Data and Backend Access

- `apps/ios/GuideDogs/Code/Data/Services/Helpers/ServiceModel.swift`
  - Shared HTTP host configuration and response validation utilities.
  - Production services host currently points to `https://via.inclu.si`.
- `apps/ios/GuideDogs/Code/Data/Services/OSM/OSMServiceModel.swift`
  - Tile and dynamic data network calls.
  - Tile endpoint format: `/tiles/{z}/{x}/{y}.json`.
- `apps/ios/GuideDogs/Code/Data/Spatial Data/SpatialDataContext.swift`
  - Tile lifecycle: fetch, retry, caching coordination, and location update notifications.
  - Main method to refresh nearby data: `updateSpatialData(at:completion:)`.
- `apps/ios/GuideDogs/Code/Data/Spatial Data/SpatialDataView.swift`
  - In-memory merged view of POIs, roads, intersections, and markers around a location.
  - Quadrant math for Around/Ahead directional filtering.
- `apps/ios/GuideDogs/Code/Data/Spatial Data/SpatialDataCache.swift`
  - Realm-backed cache lookup helpers for POIs, roads, markers, destinations.

## Manual and Automatic Callouts

- `apps/ios/GuideDogs/Code/Behaviors/Default/ExplorationGenerator.swift`
  - Manual modes: My Location, Around Me, Ahead of Me, Nearby Markers.
  - Handles directional callout selection and fallback behavior.
- `apps/ios/GuideDogs/Code/Behaviors/Default/AutoCalloutGenerator.swift`
  - Automatic callouts as user moves.
  - Range behavior now follows settings-driven callout mode.
- `apps/ios/GuideDogs/Code/Behaviors/Default/Callouts/POICallout.swift`
  - Speech/sound rendering for POIs and markers.

## Home Screen and Exploration UX

- `apps/ios/GuideDogs/Code/Visual UI/View Controllers/Home/HomeViewController.swift`
  - Home screen orchestration, menu transitions, and exploration POI category flows.
  - Contains POI aggregation for category lists (OSM + Apple + Overture/AlaVia endpoint).
- `apps/ios/GuideDogs/Code/Visual UI/View Controllers/Home/CalloutButtonPanelViewController.swift`
  - Four main action buttons (My Location, Around, Ahead, Mode/Markers behavior).
  - Accessibility custom actions and GPS status footer rendering.
- `apps/ios/GuideDogs/Code/Visual UI/View Controllers/Home/ExplorationPOICategoryViewController.swift`
  - Category-first exploration list UI and POI selection behavior.

## Settings and Persistence

- `apps/ios/GuideDogs/Code/App/Settings/SettingsContext.swift`
  - UserDefaults-backed settings model for speech, units, GPS status options, callout mode.
- `apps/ios/GuideDogs/Code/Visual UI/View Controllers/Settings/SettingsViewController.swift`
  - Settings page structure and navigation rows.
  - Hosts GPS Information page setup.

## Destinations, Markers, and Generic Locations

- `apps/ios/GuideDogs/Code/Data/Models/Temp Models/GenericLocation.swift`
  - Non-OSM location POI wrapper for coordinates and external source results.
- `apps/ios/GuideDogs/Code/Data/Models/Database Models/ReferenceEntity.swift`
  - Persisted marker/reference model and conversion to POI.
- `apps/ios/GuideDogs/Code/Data/Destination Manager/DestinationManager.swift`
  - Set/clear destination and audio beacon lifecycle.
- `apps/ios/GuideDogs/Code/Visual UI/Helpers/Location/Location Action/LocationActionHandler.swift`
  - UI-triggered actions for beacon, save marker, route/preview entry points.

## Localization and Storyboards

- `apps/ios/GuideDogs/Assets/Localization/*/Localizable.strings`
  - All translated string resources.
  - New feature keys should be added to all locales before release.
- `apps/ios/GuideDogs/Code/Visual UI/Views/main.storyboard`
  - Main UI outlet and scene wiring for classic UIKit view controllers.

## CI and Build Verification

- `.github/workflows/ios-unsigned-build.yml`
  - Unsigned iOS build workflow used for cache and wall-clock optimization checks.

## Fast Triage Playbook

- Around/Ahead has no callouts:
  - Check `ExplorationGenerator` fallback logic and `SpatialDataContext.state`.
  - Validate tile endpoint health from `ServiceModel.servicesHostName`.
- Home status line wrong/missing:
  - Check `CalloutButtonPanelViewController.updateGPSStatus` and `SettingsContext` toggles.
- API endpoint issues:
  - Check `ServiceModel.servicesHostName` and `OSMServiceModel` URL construction.
- Localization gaps:
  - Diff keys in `en-US.lproj/Localizable.strings` against other locales.
