//
//  GPXExtensions.swift
//  Soundscape
//
//  Copyright (c) Microsoft Corporation.
//  Licensed under the MIT License.
//

import Foundation
import CoreLocation
import UIKit
import iOS_GPX_Framework
import CoreMotion.CMMotionActivity

public typealias GPXActivity = String

public struct GPXLocation {
    var location: CLLocation
    var deviceHeading: Double?
    var activity: GPXActivity?
}

extension GPXBounds {
    convenience init?(with locations: [GPXLocation]) {
        guard let firstLocation = locations.first?.location else {
            return nil
        }
        
        var minLatitude = firstLocation.coordinate.latitude
        var maxLatitude = firstLocation.coordinate.latitude
        var minLongitude = firstLocation.coordinate.longitude
        var maxLongitude = firstLocation.coordinate.longitude

        for gpxLocation in locations {
            let location = gpxLocation.location
            
            if location.coordinate.latitude < minLatitude {
                minLatitude = location.coordinate.latitude
            }
            if location.coordinate.latitude > maxLatitude {
                maxLatitude = location.coordinate.latitude
            }
            if location.coordinate.latitude < minLongitude {
                minLongitude = location.coordinate.longitude
            }
            if location.coordinate.latitude > maxLongitude {
                maxLongitude = location.coordinate.longitude
            }
        }
        
        self.init(minLatitude: minLatitude,
                  minLongitude: minLongitude,
                  maxLatitude: maxLatitude,
                  maxLongitude: maxLongitude)
    }
}

extension GPXRoot {
    
    class func defaultRoot() -> GPXRoot {
        let creator = "\(AppContext.appDisplayName) \(AppContext.appVersion) (\(AppContext.appBuild))"
        guard let root = GPXRoot(creator: creator) else {
            fatalError("Unable to create GPXRoot")
        }
        
        let metadata = GPXMetadata()
        metadata.time = Date()
        metadata.desc = "Created on \(UIDevice.current.model) (\(UIDevice.current.systemName) \(UIDevice.current.systemVersion))"
        
        let author = GPXAuthor()
        author.name = UIDevice.current.name
        metadata.author = author
        
        root.metadata = metadata
        
        return root
    }
    
    class func createGPX(withTrackLocations trackLocations: [GPXLocation]) -> GPXRoot {
        let root = GPXRoot.defaultRoot()
        root.metadata?.bounds = GPXBounds(with: trackLocations)
        
        let trackSegment = GPXTrackSegment()
        for gpxLocation in trackLocations {
            trackSegment.addTrackpoint(GPXTrackPoint(with: gpxLocation))
        }
        
        let track = GPXTrack()
        track.addTracksegment(trackSegment)
        
        root.addTrack(track)
        
        return root
    }
}

extension GPXWaypoint {

    /// This can be used to check if a timestamp of a `CLLocation` created with a waypoint is compared to nil.
    /// Date is `Date(timeIntervalSince1970: 0)`.
    class func noDateIdentifier() -> Date {
        return Date(timeIntervalSince1970: 0)
    }
    
    var hasSoundscapeExtension: Bool {
        return false
    }
    
    convenience init(with gpxLocation: GPXLocation) {
        self.init()
        
        let location = gpxLocation.location
        
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        elevation = location.altitude
        time = location.timestamp

        // Preserve the older fallback behavior by storing accuracies in dilution fields.
        horizontalDilution = location.horizontalAccuracy
        verticalDilution = location.verticalAccuracy
    }

    /// Note: if a waypoint's timestamp is nil (when the GPX file does not contain time values),
    /// we use `noDateIdentifier` to symbolize nil, because `CLLocation` cannot contain nil timestamps.
    func gpxLocation() -> GPXLocation {
        var speed: CLLocationSpeed = -1
        var course: CLLocationDirection = -1
        
        var horizontalAccuracy: CLLocationAccuracy = -1
        var verticalAccuracy: CLLocationAccuracy = -1

        var deviceHeading: Double?

        var activity: GPXActivity?

        // Backwards compatibility: previuosly Soundscape used the dilution values for accuracy
        horizontalAccuracy = horizontalDilution
        verticalAccuracy = verticalDilution

        // Speed/course and custom extension properties are unavailable in the base GPX pod,
        // so we intentionally fall back to dilution-based accuracies and unknown heading/activity.
        
        let location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                                  altitude: elevation,
                                  horizontalAccuracy: horizontalAccuracy,
                                  verticalAccuracy: verticalAccuracy,
                                  course: course,
                                  speed: speed,
                                  timestamp: time ?? GPXWaypoint.noDateIdentifier())
        
        return GPXLocation(location: location, deviceHeading: deviceHeading, activity: activity)
    }
    
}

extension Array where Element == CLLocationCoordinate2D {
    func toGPXRoute() -> GPXRoute {
        let routePoints = self.compactMap { GPXRoutePoint.routepoint(withLatitude: CGFloat($0.latitude),
                                                                     longitude: CGFloat($0.longitude)) }
        let route = GPXRoute()
        route.addRoutepoints(routePoints)
        
        return route
    }
}
