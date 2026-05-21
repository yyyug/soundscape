# iOS Refactor Audit (2026-05-20)

This audit highlights file-splitting priorities and best-practice improvements for the SoundScape iOS codebase.

## High-Priority Split Candidates

1. apps/ios/GuideDogs/Code/Visual UI/View Controllers/Home/HomeViewController.swift (~1525 lines)
- Current risk: UI orchestration, feature logic, and data aggregation are tightly coupled.
- Recommended split:
  - HomeViewStateController (state + event routing)
  - HomePOIAggregator (POI source composition)
  - HomeAccessibilityCoordinator (VoiceOver/custom actions)

2. apps/ios/GuideDogs/Code/Audio/AudioEngine.swift (~1336 lines)
- Current risk: engine config, playback policy, and session lifecycle in one unit.
- Recommended split:
  - AudioSessionManager
  - SpatialPlaybackMixer
  - SpeechAndEarconPipeline

3. apps/ios/GuideDogs/Code/Data/Spatial Data/SpatialDataContext.swift (~880 lines)
- Current risk: fetch lifecycle, retries, cache wiring, and notification fan-out together.
- Recommended split:
  - SpatialDataFetchOrchestrator
  - SpatialDataRefreshPolicy
  - SpatialDataEventPublisher

4. apps/ios/GuideDogs/Code/Visual UI/View Controllers/Devices/DevicesViewController.swift (~850 lines)
- Current risk: device flows and UI concerns mixed.
- Recommended split:
  - DevicesDataSource
  - DevicesActionHandler
  - DevicesViewBinder

5. apps/ios/GuideDogs/Code/Data/Destination Manager/DestinationManager.swift (~764 lines)
- Current risk: destination state machine + persistence + beacon logic coupled.
- Recommended split:
  - DestinationStateStore
  - DestinationPersistenceAdapter
  - BeaconControlService

## Medium-Priority Split Candidates

- apps/ios/GuideDogs/Code/Behaviors/Default/AutoCalloutGenerator.swift (~671 lines)
- apps/ios/GuideDogs/Code/Behaviors/Preview/PreviewBehavior.swift (~706 lines)
- apps/ios/GuideDogs/Code/Data/Models/Cache Models/Intersection.swift (~685 lines)

## Best-Practice Improvements

1. Limit feature classes to one primary responsibility
- Target: <= 400-500 lines for view controllers and service classes.

2. Extract protocol boundaries before moving logic
- Introduce protocols for navigation, audio, and data fetch boundaries.
- Add default implementations with dependency injection from AppContext.

3. Separate pure logic from UIKit side effects
- Move pure transformations/scoring/sorting into plain Swift utility modules.
- Keep view controllers focused on binding and presentation.

4. Add contract-level tests around backend-dependent paths
- Tile load fallback behavior
- address-batch response mapping to GeocodedAddress
- callout generation under missing/partial data

5. Keep docs synchronized with code ownership
- Update docs/ios-client/file-function-map.md whenever ownership moves.
- Add "Owner" and "Last verified" metadata per major module.

## Suggested Execution Order

1. HomeViewController split
2. SpatialDataContext split
3. AutoCalloutGenerator and PreviewBehavior split
4. AudioEngine split (highest risk; do after establishing test coverage)

## Exit Criteria for Each Split

- Same public behavior in manual regression checks
- No increase in crash/log error rates
- Unit tests for extracted pure logic
- Updated docs/ios-client/file-function-map.md
