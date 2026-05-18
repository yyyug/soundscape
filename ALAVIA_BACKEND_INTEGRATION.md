# AlaVia Backend Integration Plan for Live View (ARCore Geospatial)

**Document Version**: 1.0  
**Target System**: Cloudflare Workers (AlaVia Endpoint)  
**Integration Date**: 2026-05  

---

## 1. Overview

This document outlines the backend integration required to support the "Live View" iOS feature. The implementation uses Cloudflare Workers as the proxy layer, forwarding requests to Google's ARCore Geospatial API while managing API keys, caching, and rate limiting.

**Architecture**:
```
iOS App
  ↓
AlaVia (Cloudflare Workers)
  ├─ /api/v1/geospatial/vps-available
  └─ /api/v1/geospatial/localize
       ↓
Google ARCore Geospatial API
```

---

## 2. Prerequisites

### 2.1 Environment & Credentials

**Google Cloud Setup**:
1. Create/use existing Google Cloud Project
2. Enable ARCore Geospatial API
3. Create API key (restrict to ARCore Geospatial API only)
4. Store securely: `GOOGLE_ARCORE_GEOSPATIAL_API_KEY` (Cloudflare secret)

**Cloudflare Setup**:
1. AlaVia project already uses `c:\Users\user\Downloads\AlaVia`
2. Wrangler CLI installed (`npx wrangler --version` ✓)
3. Access to Cloudflare dashboard or `wrangler.toml` configuration

---

## 3. Cloudflare Worker Implementation

### 3.1 File Structure

```
c:\Users\user\Downloads\AlaVia\
├── wrangler.toml                    (updated with secrets)
├── src\
│   ├── index.js                     (main router)
│   ├── handlers\
│   │   └── geospatial.js            (new: VPS & localization)
│   ├── middleware\
│   │   ├── auth.js                  (existing: token validation)
│   │   ├── rateLimit.js             (existing/enhanced)
│   │   └── cache.js                 (new: geohash-based caching)
│   └── utils\
│       ├── geohash.js               (new: geohash encoding)
│       └── telemetry.js             (existing: logging)
```

### 3.2 Updated wrangler.toml

```toml
[env.production]
vars = { ENVIRONMENT = "production" }
secrets = [
    "GOOGLE_ARCORE_GEOSPATIAL_API_KEY",
    "GOOGLE_CLOUD_PROJECT_ID"
]

# KV binding for caching VPS availability
kv_namespaces = [
    { binding = "GEOSPATIAL_CACHE", id = "12345..." }
]

# Rate limiting config
rate_limit_rules = [
    { path = "/api/v1/geospatial/*", limit = "100/minute" }
]
```

**To Deploy**:
```bash
cd c:\Users\user\Downloads\AlaVia

# Set secrets
npx wrangler secret put GOOGLE_ARCORE_GEOSPATIAL_API_KEY
# Paste API key when prompted

npx wrangler secret put GOOGLE_CLOUD_PROJECT_ID
# Paste project ID

# Deploy
npm run deploy
# or: npx wrangler deploy
```

### 3.3 Handler Implementation (geospatial.js)

```javascript
// src/handlers/geospatial.js

import { encodeGeohash } from '../utils/geohash.js';
import { logTelemetry } from '../utils/telemetry.js';

const ARCORE_API_BASE = 'https://arcore.googleapis.com/v1';
const CACHE_TTL = 24 * 60 * 60; // 24 hours

export async function handleVPSAvailability(request, env, context) {
    // 1. Authentication
    const authHeader = request.headers.get('Authorization');
    const token = authHeader?.replace('Bearer ', '');
    if (!token) {
        return jsonResponse({ error: 'authentication_required' }, 401);
    }

    // 2. Parse request
    const { latitude, longitude, client_version, device_id } = await request.json();
    if (!latitude || !longitude || isNaN(latitude) || isNaN(longitude)) {
        return jsonResponse({ error: 'invalid_coordinates' }, 400);
    }

    // 3. Check cache (geohash level 4 ~ 156km grid)
    const geohash = encodeGeohash(latitude, longitude, 4);
    const cacheKey = `vps:${geohash}`;
    
    let cachedResult = await env.GEOSPATIAL_CACHE.get(cacheKey);
    if (cachedResult) {
        logTelemetry({
            event: 'vps_check_cache_hit',
            geohash,
            device_id,
            timestamp: new Date().toISOString()
        });
        return jsonResponse(JSON.parse(cachedResult));
    }

    // 4. Call Google ARCore API
    try {
        const response = await fetch(
            `${ARCORE_API_BASE}/areachability:query?key=${env.GOOGLE_ARCORE_GEOSPATIAL_API_KEY}`,
            {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    latitude,
                    longitude
                })
            }
        );

        if (!response.ok) {
            if (response.status === 429) {
                return jsonResponse({ error: 'rate_limit_exceeded', retry_after: 60 }, 429);
            }
            if (response.status === 503) {
                return jsonResponse({ error: 'arcore_api_unavailable' }, 503);
            }
            throw new Error(`Google API error: ${response.status}`);
        }

        const googleResult = await response.json();

        // 5. Transform response
        const result = {
            status: 'success',
            vps_available: googleResult.vpsAvailable ?? false,
            vps_quality: googleResult.vpsQuality || 'MEDIUM',
            geohash,
            cache_ttl_seconds: CACHE_TTL,
            timestamp: new Date().toISOString(),
            regions_nearby: [] // Optional: populate from adjacent geohashes
        };

        // 6. Cache result
        await env.GEOSPATIAL_CACHE.put(cacheKey, JSON.stringify(result), {
            expirationTtl: CACHE_TTL
        });

        logTelemetry({
            event: 'vps_check_success',
            geohash,
            vps_available: result.vps_available,
            device_id,
            timestamp: new Date().toISOString()
        });

        return jsonResponse(result);

    } catch (error) {
        logTelemetry({
            event: 'vps_check_error',
            error: error.message,
            device_id,
            timestamp: new Date().toISOString()
        });
        return jsonResponse({ error: 'internal_error', detail: error.message }, 500);
    }
}

export async function handleLocalization(request, env, context) {
    // 1. Authentication
    const authHeader = request.headers.get('Authorization');
    const token = authHeader?.replace('Bearer ', '');
    if (!token) {
        return jsonResponse({ error: 'authentication_required' }, 401);
    }

    // 2. Parse request
    const body = await request.json();
    const {
        approximate_latitude,
        approximate_longitude,
        altitude_m,
        image_features,
        device_rotation_quaternion,
        device_acceleration,
        timestamp_ms,
        session_id,
        client_version
    } = body;

    if (!approximate_latitude || !approximate_longitude) {
        return jsonResponse({ error: 'invalid_coordinates' }, 400);
    }

    // 3. Call Google Geospatial API
    try {
        const response = await fetch(
            `${ARCORE_API_BASE}/geospatial:localize?key=${env.GOOGLE_ARCORE_GEOSPATIAL_API_KEY}`,
            {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    latitude: approximate_latitude,
                    longitude: approximate_longitude,
                    altitude: altitude_m,
                    rotation: device_rotation_quaternion,
                    imageData: image_features
                })
            }
        );

        if (!response.ok) {
            if (response.status === 429) {
                return jsonResponse({ error: 'rate_limit_exceeded' }, 429);
            }
            throw new Error(`Google API error: ${response.status}`);
        }

        const googleResult = await response.json();

        // 4. Transform & return
        const result = {
            status: 'success',
            localization: {
                latitude: googleResult.latitude,
                longitude: googleResult.longitude,
                altitude_m: googleResult.altitude,
                horizontal_accuracy_m: googleResult.horizontalAccuracy,
                vertical_accuracy_m: googleResult.verticalAccuracy,
                heading_degrees: googleResult.heading,
                heading_accuracy_degrees: googleResult.headingAccuracy,
                confidence_score: googleResult.confidenceScore,
                timestamp_ms: timestamp_ms,
                source: 'vps'
            },
            tracking_state: {
                earth_state: googleResult.earthState || 'DISABLED',
                vps_tracking: googleResult.trackingState || 'NOT_READY',
                vps_quality: googleResult.vpsQuality || 'MEDIUM'
            }
        };

        logTelemetry({
            event: 'localization_success',
            accuracy_m: result.localization.horizontal_accuracy_m,
            confidence: result.localization.confidence_score,
            session_id,
            timestamp: new Date().toISOString()
        });

        return jsonResponse(result);

    } catch (error) {
        logTelemetry({
            event: 'localization_error',
            error: error.message,
            session_id,
            timestamp: new Date().toISOString()
        });

        // Return tracking not ready (client can retry)
        return jsonResponse({
            status: 'tracking_not_ready',
            tracking_state: {
                earth_state: 'DISABLED',
                reason: 'insufficient_visual_features',
                retry_after_ms: 500
            }
        });
    }
}

function jsonResponse(data, status = 200) {
    return new Response(JSON.stringify(data), {
        status,
        headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        }
    });
}
```

### 3.4 Router Update (index.js)

```javascript
// src/index.js (add to existing router)

import { handleVPSAvailability, handleLocalization } from './handlers/geospatial.js';
import { authMiddleware } from './middleware/auth.js';

export default {
    async fetch(request, env, context) {
        const url = new URL(request.url);
        const path = url.pathname;

        // Geospatial routes
        if (path === '/api/v1/geospatial/vps-available' && request.method === 'POST') {
            return handleVPSAvailability(request, env, context);
        }

        if (path === '/api/v1/geospatial/localize' && request.method === 'POST') {
            return handleLocalization(request, env, context);
        }

        // ... existing routes
    }
};
```

### 3.5 Geohash Utility (utils/geohash.js)

```javascript
// src/utils/geohash.js

const BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';

export function encodeGeohash(lat, lon, precision = 5) {
    let idx = 0;
    let bit = 0;
    let evenBit = true;
    let geohash = '';

    let latMin = -90, latMax = 90;
    let lonMin = -180, lonMax = 180;

    while (geohash.length < precision) {
        if (evenBit) {
            const lonMid = (lonMin + lonMax) / 2;
            if (lon >= lonMid) {
                idx = (idx << 1) + 1;
                lonMin = lonMid;
            } else {
                idx = idx << 1;
                lonMax = lonMid;
            }
        } else {
            const latMid = (latMin + latMax) / 2;
            if (lat >= latMid) {
                idx = (idx << 1) + 1;
                latMin = latMid;
            } else {
                idx = idx << 1;
                latMax = latMid;
            }
        }

        evenBit = !evenBit;

        if (bit < 4) {
            bit++;
        } else {
            geohash += BASE32[idx];
            bit = 0;
            idx = 0;
        }
    }

    return geohash;
}
```

---

## 4. Deployment Steps

### 4.1 Local Testing

```bash
cd c:\Users\user\Downloads\AlaVia

# Install dependencies
npm install

# Test locally
npx wrangler dev

# Test VPS endpoint
curl -X POST http://localhost:8787/api/v1/geospatial/vps-available \
  -H "Authorization: Bearer test-token" \
  -H "Content-Type: application/json" \
  -d '{
    "latitude": 22.3193,
    "longitude": 114.1694,
    "client_version": "1.0.0",
    "device_id": "test-device"
  }'
```

### 4.2 Production Deployment

```bash
# 1. Set secrets in Cloudflare dashboard or CLI
npx wrangler secret put GOOGLE_ARCORE_GEOSPATIAL_API_KEY
# Then paste: AIzaSy_________...

npx wrangler secret put GOOGLE_CLOUD_PROJECT_ID
# Then paste: project-xxx-xxxxxx

# 2. Deploy
npx wrangler deploy

# 3. Verify
# Check Cloudflare Workers dashboard for deployment status
# Test live endpoint
curl -X POST https://alavia.yoofun.workers.dev/api/v1/geospatial/vps-available \
  -H "Authorization: Bearer $(gh auth token)" \
  -H "Content-Type: application/json" \
  -d '{...}'
```

---

## 5. Monitoring & Observability

### 5.1 Metrics to Track

**In Cloudflare Analytics**:
- Request count by endpoint
- Error rate (4xx, 5xx)
- Response time percentiles (p50, p95, p99)
- Rate limit hits

**Custom Telemetry** (via `logTelemetry`):
```
Events:
  vps_check_cache_hit
  vps_check_cache_miss
  vps_check_success
  vps_check_error
  localization_success
  localization_error
  localization_tracking_not_ready

Dimensions:
  geohash
  device_id
  error_code
  response_time_ms
```

### 5.2 Dashboards

**Recommended Tools**:
- Grafana (pull from Cloudflare APIs)
- Datadog (APM integration)
- Custom dashboard (log aggregation → BigQuery/Splunk)

---

## 6. Rate Limiting & Quotas

**Google ARCore Geospatial API Quotas**:
- Check current quotas in [Google Cloud Console](https://console.cloud.google.com/apis/dashboard)
- Typical tier: 10K requests/day for free tier
- Estimated iOS user calls:
  - VPS availability check: ~1 per app launch (cached 24h) → ~10 per user/month
  - Localization: ~10 per session (on-demand) → ~100 per active user/month

**Cloudflare Worker Rate Limiting**:
- Implement per-user rate limit: 100 requests/minute
- Geohash-level caching reduces actual Google API calls

---

## 7. Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| 403 Unauthorized from Google | Invalid/expired API key | Verify `GOOGLE_ARCORE_GEOSPATIAL_API_KEY` in Cloudflare secrets |
| 429 Too Many Requests | Rate limit hit on Google API | Reduce client request frequency; increase cache TTL |
| 503 Service Unavailable | Google API down | Implement exponential backoff; inform users to retry later |
| App crash on AR session | Backend not deployed yet | Ensure AlaVia endpoints are live before iOS release |
| Geohash caching not working | KV namespace not bound | Verify `GEOSPATIAL_CACHE` binding in `wrangler.toml` |

---

## 8. Future Enhancements

1. **Analytics Dashboard**: Real-time VPS availability heatmap
2. **A/B Testing**: Compare accuracy VPS vs GPS in cohorts
3. **Regional Expansion**: Support for additional VPS regions as Google expands
4. **Offline Mode**: Pre-cache VPS data for popular locations
5. **Telemetry Integration**: Export to Data Lake for ML model training

---

## 9. References

- [Google ARCore Geospatial API Docs](https://developers.google.com/ar/develop/geospatial-api)
- [Cloudflare Workers Docs](https://developers.cloudflare.com/workers/)
- [Wrangler CLI](https://developers.cloudflare.com/wrangler/)

---
