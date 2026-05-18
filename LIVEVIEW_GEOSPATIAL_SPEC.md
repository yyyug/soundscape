# Live View - ARCore Geospatial Integration Specification

**Document Version**: 1.0  
**Date**: 2026-05-18  
**Status**: Implementation Plan  

---

## 1. Overview

**Live View** is a new iOS feature that leverages Google ARCore Geospatial API to provide real-time camera-based localization, compensating for inaccurate GPS signals. The feature integrates with the existing location stack without replacing it, providing a fallback/supplement mechanism.

**Key Constraint**: Show button always when VPS is available in the region, regardless of GPS accuracy.

---

## 2. Requirements

### 2.1 Functional Requirements

| # | Requirement | Detail |
|---|-----------|--------|
| FR-1 | Button Display | Show "Live View" button on home screen callout panel (right of existing 4 buttons) when: feature flag enabled, ARCore supported, camera permission granted, VPS available in current region |
| FR-2 | Button Placement | Position as 5th button in callout panel, consistent styling with other buttons |
| FR-3 | Always Show | Display button regardless of current GPS accuracy |
| FR-4 | Regional Availability | Dynamically check and cache VPS availability per geohash; hide button if region unsupported |
| FR-5 | Camera Session | Launch camera AR session with VPS tracking when button pressed |
| FR-6 | Localization Fallback | If AR session fails or tracking lost, automatically revert to GPS-based localization without user intervention |
| FR-7 | Multi-language | Provide "Live View" translation for all 17 supported languages |

### 2.2 Non-Functional Requirements

| # | Requirement | Detail |
|---|-----------|--------|
| NFR-1 | Performance | VPS availability check cached for 24h to minimize backend calls |
| NFR-2 | Reliability | No crash or UI freeze if AR initialization fails; graceful degradation |
| NFR-3 | Privacy | All AR-related operations opt-in; camera frame data not logged or stored on device |
| NFR-4 | Battery | AR session auto-pauses when app backgrounded; session lifecycle managed carefully |
| NFR-5 | Observability | Telemetry events track availability hit rate, localization accuracy improvement, session duration, failure reasons |

---

## 3. Architecture

### 3.1 High-Level Flow

```
Home Screen Load
    ↓
Check Feature Flag (geospatialLiveview)
    ↓ (enabled)
Check ARCore Support + Camera Permission
    ↓ (supported + permitted)
Get User Location
    ↓
Query VPS Availability Cache (geohash)
    ↓
If Cache Hit & Valid: Use Cached Result
    ↓ (valid & available)
Show "Live View" Button
    ↓ (user taps)
Launch Camera AR Session
    ↓
Localize via Geospatial API
    ↓ (success)
Return Coordinates + Accuracy to Home
    ↓
Update UI with Improved Accuracy
```

### 3.2 Component Architecture

```
┌─────────────────────────────────────────────────┐
│           Home View Controller                   │
│    (CalloutButtonPanelViewController)            │
├─────────────────────────────────────────────────┤
│  Live View Button Logic                         │
│  - Visibility: Feature Flag + VPS Check         │
│  - Tap Handler: Launch AR VC                    │
└──────────────────┬──────────────────────────────┘
                   │
          ┌────────┴────────┐
          ↓                 ↓
    ┌──────────────┐  ┌──────────────────┐
    │ Geospatial   │  │ ARCore Session   │
    │ Service      │  │ Manager          │
    │ (VPS Check)  │  │ (Tracking)       │
    └──────────────┘  └──────────────────┘
          │                 │
          └────────┬────────┘
                   ↓
         ┌──────────────────────┐
         │   Backend Proxy      │
         │ /api/v1/geospatial/* │
         └──────────────────────┘
                   │
                   ↓
         ┌──────────────────────┐
         │ Google ARCore        │
         │ Geospatial API       │
         │ (Cloud Localization) │
         └──────────────────────┘
```

### 3.3 Data Flow

**VPS Availability Check** (Cache Layer):
```
Input: latitude, longitude
       ↓
Compute Geohash (precision 4, ~156km grid)
       ↓
Check 24h Cache
       ├─ Hit & Fresh: Return cached result
       └─ Miss/Stale: Call Backend
              ↓
           POST /api/v1/geospatial/vps-available
           Body: { lat, lon }
              ↓
           Response: { vps_available: bool, vps_quality: "HIGH|MEDIUM|LOW" }
              ↓
           Cache Result + TTL 24h
              ↓
           Return to UI
```

**Localization Call** (AR Session):
```
Input: Camera Frame Features, Device Pose, Approx Location
       ↓
POST /api/v1/geospatial/localize
Body: {
  latitude, longitude (approx),
  camera_frame_features (byte array),
  device_rotation (quaternion),
  device_acceleration,
  timestamp_ms
}
       ↓
Backend Forwards to Google
       ↓
Response: {
  latitude, longitude (precise),
  altitude,
  horizontal_accuracy_m,
  vertical_accuracy_m,
  confidence_score,
  tracking_state: "TRACKING|PAUSED|NOT_READY",
  earth_state: "ENABLED|DISABLED"
}
       ↓
Return to App, Update UI
```

---

## 4. Implementation Details

### 4.1 iOS App Changes

#### 4.1.1 Feature Flag (FeatureFlag.swift)

```swift
enum FeatureFlag {
    case developerTools
    case experimentConfiguration
    case geospatialLiveview  // ← New
    
    static func isEnabled(_ feature: FeatureFlag) -> Bool {
        // ... existing logic
        case .geospatialLiveview:
            #if FF_GEOSPATIAL_LIVEVIEW
            return true
            #else
            return false
            #endif
    }
}
```

**Compilation Flags**:
- `FeatureFlags-Debug`: `#define FF_GEOSPATIAL_LIVEVIEW 1` (enabled for testing)
- `FeatureFlags-Release`: Leave undefined (disabled by default)
- `FeatureFlags-AdHoc`: `#define FF_GEOSPATIAL_LIVEVIEW 1` (for beta)

#### 4.1.2 Geospatial Service (new file)

**Path**: `apps/ios/GuideDogs/Code/Data/Services/GeospatialServiceModel.swift`

**Responsibilities**:
- VPS availability cache management (geohash-based, 24h TTL)
- Backend communication for availability check & localization
- Error handling & telemetry logging
- Graceful fallback on API failure

**Key Methods**:
```swift
class GeospatialServiceModel {
    private var vpsCache: [String: (available: Bool, vpsQuality: String, timestamp: Date)] = [:]
    
    func checkVPSAvailability(
        lat: Double, lon: Double,
        completion: @escaping (Bool, String?) -> Void
    )
    
    func localizeWithGeospatial(
        imageData: Data,
        devicePose: ARCorePose,
        approximateLocation: CLLocation,
        completion: @escaping (GeospatialResult?) -> Void
    )
    
    private func computeGeohash(_ lat: Double, _ lon: Double) -> String
}
```

#### 4.1.3 CalloutButtonPanelViewController Changes

**Changes**:
1. Add `liveViewContainer` IBOutlet (5th button slot)
2. Add `liveViewImageView` for icon
3. Initialize GeospatialServiceModel
4. Implement `updateLiveViewButtonVisibility()` to evaluate:
   - Feature flag enabled?
   - ARCore supported?
   - Camera permission granted?
   - VPS available in region?
5. Subscribe to location updates to refresh button state
6. Implement tap handler: `onLiveViewTouchUpInside()`

**Pseudocode**:
```swift
@objc private func updateLiveViewButtonVisibility() {
    // 1. Feature flag
    guard FeatureFlag.isEnabled(.geospatialLiveview) else {
        liveViewContainer.isHidden = true
        return
    }
    
    // 2. ARCore support + camera permission
    guard ARCoreGeospatialSession.isSupported(),
          cameraPermissionGranted() else {
        liveViewContainer.isHidden = true
        return
    }
    
    // 3. Get location
    guard let location = AppContext.shared.geolocationManager.location else {
        liveViewContainer.isHidden = true
        return
    }
    
    // 4. Check VPS availability (async, cached)
    geospatialService.checkVPSAvailability(
        lat: location.coordinate.latitude,
        lon: location.coordinate.longitude
    ) { [weak self] isAvailable, quality in
        DispatchQueue.main.async {
            self?.liveViewContainer.isHidden = !isAvailable
            self?.logTelemetry(
                event: "liveview_vps_check",
                available: isAvailable,
                quality: quality
            )
        }
    }
}

@IBAction func onLiveViewTouchUpInside(_ sender: AnyObject?) {
    let arVC = ARCoreGeospatialViewController()
    arVC.onLocalizationComplete = { [weak self] result in
        // Fuse localization result into location stack
        AppContext.process(
            GeospatialLocalizationCompleted(result: result)
        )
        self?.dismiss(animated: true)
    }
    self.present(arVC, animated: true)
}
```

#### 4.1.4 Storyboard Changes

- Edit `CalloutButtonPanelViewController.xib` (or storyboard reference)
- Add 5th button container view (`liveViewContainer`)
- Connect IBOutlet to `liveViewContainer`
- Position in horizontal stack with existing 4 buttons (right side)
- Add icon image to `liveViewImageView`
- Preferred sizing: same as other callout buttons

---

### 4.2 Backend Integration (AlaVia)

#### 4.2.1 Endpoint Design

**Base URL**: `https://alavia.yoofun.workers.dev` (existing endpoint from ServiceModel)

**New Endpoints**:

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/api/v1/geospatial/vps-available` | Check VPS availability in region |
| POST | `/api/v1/geospatial/localize` | Perform geospatial localization |

#### 4.2.2 VPS Availability Check Endpoint

**Request**:
```json
POST /api/v1/geospatial/vps-available
Authorization: Bearer <user-token>
Content-Type: application/json

{
  "latitude": 22.3193,
  "longitude": 114.1694,
  "client_version": "1.0.0",
  "device_id": "<device-identifier>"
}
```

**Response (Success)**:
```json
HTTP 200 OK
{
  "status": "success",
  "vps_available": true,
  "vps_quality": "HIGH",
  "geohash": "wecb",
  "cache_ttl_seconds": 86400,
  "regions_nearby": [
    {
      "geohash": "wecc",
      "vps_available": true,
      "distance_km": 12
    }
  ]
}
```

**Response (Not Available)**:
```json
HTTP 200 OK
{
  "status": "success",
  "vps_available": false,
  "reason": "region_not_supported",
  "supported_regions": {
    "asia": ["HK", "JP", "SG"],
    "europe": ["UK", "FR"],
    "americas": ["US", "CA"]
  }
}
```

**Error Responses**:
```json
HTTP 400 Bad Request
{ "error": "invalid_coordinates" }

HTTP 401 Unauthorized
{ "error": "authentication_required" }

HTTP 429 Too Many Requests
{ "error": "rate_limit_exceeded", "retry_after": 60 }

HTTP 503 Service Unavailable
{ "error": "arcore_api_unavailable" }
```

#### 4.2.3 Localization Endpoint

**Request**:
```json
POST /api/v1/geospatial/localize
Authorization: Bearer <user-token>
Content-Type: application/json

{
  "approximate_latitude": 22.3193,
  "approximate_longitude": 114.1694,
  "altitude_m": 50,
  "image_features": "<base64-encoded-feature-vector>",
  "device_rotation_quaternion": { "w": 0.99, "x": 0.1, "y": 0.02, "z": 0.01 },
  "device_acceleration": { "x": 0.0, "y": 0.0, "z": -9.8 },
  "timestamp_ms": 1684408323000,
  "session_id": "<unique-session-id>",
  "client_version": "1.0.0"
}
```

**Response (Success)**:
```json
HTTP 200 OK
{
  "status": "success",
  "localization": {
    "latitude": 22.31931,
    "longitude": 114.16936,
    "altitude_m": 50.5,
    "horizontal_accuracy_m": 1.8,
    "vertical_accuracy_m": 2.3,
    "heading_degrees": 45.2,
    "heading_accuracy_degrees": 5.0,
    "confidence_score": 0.92,
    "timestamp_ms": 1684408323050,
    "source": "vps"
  },
  "tracking_state": {
    "earth_state": "ENABLED",
    "vps_tracking": "TRACKING",
    "vps_quality": "HIGH"
  },
  "device_info": {
    "arcore_version_supported": true,
    "arcore_version": "1.35.0"
  }
}
```

**Error Response (Tracking Not Ready)**:
```json
HTTP 200 OK
{
  "status": "tracking_not_ready",
  "tracking_state": {
    "earth_state": "DISABLED",
    "reason": "insufficient_visual_features",
    "retry_after_ms": 500
  }
}
```

#### 4.2.4 API Key Management

**Location**: AlaVia (Cloudflare Worker) environment

```env
# .env / wrangler.toml (deployed to CF Workers)
GOOGLE_ARCORE_GEOSPATIAL_API_KEY = "AIzaSy_________..." # Keep in secret
GOOGLE_CLOUD_PROJECT_ID = "project-xxx"
```

**Implementation** (Node.js / Cloudflare Worker):
```javascript
// src/api/geospatial.js
export async function handleVPSAvailability(request) {
    const apiKey = env.GOOGLE_ARCORE_GEOSPATIAL_API_KEY;
    
    const { latitude, longitude } = await request.json();
    
    // Call Google Geospatial API
    const response = await fetch(
        'https://arcore.googleapis.com/v1/areachability:query',
        {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${apiKey}`,
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                latitude, longitude
            })
        }
    );
    
    const result = await response.json();
    
    // Transform & cache
    return cacheAndReturn({
        vps_available: result.vpsAvailable,
        vps_quality: result.vpsQuality || 'MEDIUM',
        geohash: geohashEncode(latitude, longitude)
    });
}

export async function handleLocalization(request) {
    // Similar pattern: extract API key, forward to Google,
    // transform response, add telemetry
}
```

#### 4.2.5 Deployment

1. Update `apps/ios/GuideDogs/Podfile` or SwiftPM: No new dependencies required (use existing URLSession)
2. Deploy AlaVia changes:
   ```bash
   cd c:\Users\user\Downloads\AlaVia
   npm run deploy
   # Deploys to Cloudflare Workers; adds environment variables via dashboard/wrangler
   ```
3. Verify endpoints are live before releasing to users

---

## 5. Localization

### 5.1 Translations for "Live View"

| Language | Code | Translation |
|----------|------|-------------|
| English (US) | en-US | Live View |
| English (GB) | en-GB | Live View |
| Chinese (Traditional) | zh-Hant | 即時景觀 |
| French | fr-FR | Vue en Direct |
| French (Canada) | fr-CA | Vue en Direct |
| German | de-DE | Live-Ansicht |
| Spanish | es-ES | Vista en Directo |
| Italian | it-IT | Visualizzazione dal Vivo |
| Portuguese (Brazil) | pt-BR | Visualização ao Vivo |
| Portuguese (Portugal) | pt-PT | Vista em Direto |
| Dutch | nl-NL | Live Weergave |
| Swedish | sv-SE | Livevy |
| Norwegian | nb-NO | Direktevisning |
| Danish | da-DK | Livsvisning |
| Finnish | fi-FI | Reaaliaikainen näkymä |
| Greek | el-GR | Ζωντανή Προβολή |
| Japanese | ja-JP | ライブビュー |

### 5.2 Localization String Key

```swift
// Add to all Localizable.strings files
"ui.action_button.live_view" = "Live View";  // (replace with translation above)
"ui.action_button.live_view.acc_hint" = "Activate live camera-based location to improve positioning accuracy";
```

**Entries by file**:
- `en-US.lproj/Localizable.strings`: `"ui.action_button.live_view" = "Live View";`
- `zh-Hant.lproj/Localizable.strings`: `"ui.action_button.live_view" = "即時景觀";`
- ...etc

---

## 6. Telemetry & Analytics

### 6.1 Events to Track

| Event | Payload | Purpose |
|-------|---------|---------|
| `liveview_button_shown` | `{ region: geohash, vps_quality: HIGH/MED/LOW }` | Track regional availability |
| `liveview_button_hidden` | `{ reason: flag_disabled / ar_unsupported / vps_unavailable }` | Understand non-availability |
| `liveview_session_started` | `{ session_id, timestamp }` | Session lifecycle |
| `liveview_localization_success` | `{ accuracy_m, confidence, time_ms, source: vps }` | Success metrics |
| `liveview_localization_failed` | `{ error_code, reason, time_ms }` | Failure analysis |
| `liveview_fallback_to_gps` | `{ reason, gps_accuracy_m }` | Fallback triggers |
| `liveview_tracking_state_changed` | `{ new_state: TRACKING/PAUSED/NOT_READY }` | Session state |

### 6.2 Dashboard Queries

- Rollout progress: % of users with button visible
- Engagement: % of session starts / button taps
- Accuracy improvement: Avg GPS accuracy before/after
- Error distribution: Top failure reasons
- Regional coverage: Heatmap of VPS availability

---

## 7. Testing Strategy

### 7.1 Unit Tests
- `GeospatialServiceModel`: Geohash encoding, cache TTL logic, error handling
- `FeatureFlag`: Conditional compilation verification

### 7.2 Integration Tests
- Mock backend responses; verify app logic flows correctly
- VPS availability cache invalidation & refresh
- Graceful fallback on API timeout

### 7.3 Manual Testing
- **Regional Testing**:
  - Test in VPS-supported region (HK, JP, SG, UK, etc.) → Button shows
  - Test in unsupported region → Button hidden
- **Device Testing**:
  - Test on AR-capable device → Button logic enabled
  - Test on non-AR device → Button always hidden
- **Permisson Testing**:
  - Camera permission denied → Button hidden
  - Camera permission granted → Button shows (if region available)
- **Network Testing**:
  - Offline → Button hidden (no availability check)
  - Poor network → Cache hit prevents delay
  - API error → Button hidden gracefully (no crash)

### 7.4 Staged Rollout

**Phase 1**: Beta (5% of users)
- Monitor crash rate, success rate, feedback
- Duration: 1 week

**Phase 2**: Expanded (25% of users)
- If Phase 1 stable, increase rollout
- Duration: 1 week

**Phase 3**: General Availability (100%)
- Full rollout after validation

---

## 8. Success Criteria

| Metric | Target | Notes |
|--------|--------|-------|
| VPS Availability Hit Rate | > 85% in supported regions | Validate regional data accuracy |
| Session Success Rate | > 90% | Localization returned successfully |
| Accuracy Improvement | Mean ± 3m (vs GPS ~5-15m) | Improved position estimate |
| Crash Rate | < 0.1% | No regressions |
| Latency (VPS Check) | < 200ms (cached) | Acceptable UX |
| Latency (Localization) | < 1000ms | Acceptable for camera session |
| User Engagement | > 10% tap rate (button visible) | Measure interest |

---

## 9. Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| AR session crashes on unsupported device | ARCore device check before showing button; try-catch wrapping AR session |
| API key exposure in APK | Keep key in backend only; app→backend→Google pattern |
| User privacy (camera data) | Document telemetry scope; camera frames sent only to Google (not stored locally); user can disable via feature flag |
| Backend rate limiting | Implement geohash cache; fallback to GPS if backend unavailable |
| Localization accuracy regression | A/B test before rollout; monitor accuracy metrics in real-time |
| Compatibility with future iOS | ARCore Geospatial API supported on iOS 13+; use feature detection |

---

## 10. Future Enhancements

1. **AR Anchors**: Visualize placed objects/routes in AR view
2. **Multi-Source Fusion**: Combine VPS + GPS + IMU for smoother trajectory
3. **Cloud Anchors**: Share AR anchors between users
4. **Offline AR**: Cache VPS models locally for regions visited frequently
5. **Performance Optimization**: Reduce image feature transmission size; use compression

---

## 11. Appendices

### A. Glossary

- **VPS**: Visual Positioning Service (Google ARCore's cloud-based localization)
- **Geohash**: Spatial encoding; used for cache bucketing (~156km per level 4)
- **Earth**: ARCore term for global coordinate system; must be ENABLED for VPS
- **Tracking**: ARCore session state indicating active localization
- **Quaternion**: 4D representation of 3D rotation (w, x, y, z)

### B. References

- [Google ARCore Geospatial API](https://developers.google.com/ar/develop/ios/geospatial)
- [iOS Location Services](https://developer.apple.com/documentation/corelocation)
- [ARKit Best Practices](https://developer.apple.com/arkit/)

### C. Contact

- **Project Lead**: [Your Name]
- **Backend Owner**: [Backend Team]
- **QA Lead**: [QA Team]

---
