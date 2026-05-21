//
//  POI+Extensions.swift
//  Soundscape
//
//  Copyright (c) Microsoft Corporation.
//  Licensed under the MIT License.
//

import Foundation

// MARK: Realm Keys

struct POIKeys {
    static let lastSelectedDate = "lastSelectedDate"
}

extension POI {
    typealias Keys = POIKeys
    
    func isEqual(_ poi: POI) -> Bool {
        return self.key == poi.key
    }

    var localizedTypeName: String? {
        let amenityValue: String = {
            if let osm = self as? GDASpatialDataResultEntity {
                return (osm.amenity ?? "").lowercasedWithAppLocale()
            }

            if let generic = self as? GenericLocation {
                return (generic.amenity ?? "").lowercasedWithAppLocale()
            }

            return ""
        }()

        if amenityValue.contains("supermarket") {
            return GDLocalizedString("exploration.poi.category.supermarket")
        }

        if amenityValue.contains("convenience") {
            return GDLocalizedString("exploration.poi.category.convenience")
        }

        if amenityValue.contains("pharmacy") || amenityValue.contains("chemist") {
            return GDLocalizedString("exploration.poi.category.pharmacy")
        }

        if amenityValue.contains("cafe") || amenityValue.contains("coffee") {
            return GDLocalizedString("exploration.poi.category.cafe")
        }

        if amenityValue.contains("restaurant") {
            return GDLocalizedString("exploration.poi.category.restaurant")
        }

        if amenityValue.contains("transit") || amenityValue.contains("station") || amenityValue.contains("stop") {
            return GDLocalizedString("exploration.poi.category.transit")
        }

        if amenityValue.contains("park") {
            return GDLocalizedString("exploration.poi.category.parks")
        }

        switch SuperCategory(rawValue: superCategory) {
        case .mobility:
            return GDLocalizedString("callouts.mobility")
        case .places, .landmarks:
            return GDLocalizedString("callouts.places_and_landmarks")
        default:
            return nil
        }
    }

    var localizedNameWithType: String {
        let baseName = localizedName.isEmpty ? GDLocalizedString("location") : localizedName

        guard let typeName = localizedTypeName, !typeName.isEmpty else {
            return baseName
        }

        if baseName.lowercasedWithAppLocale().contains(typeName.lowercasedWithAppLocale()) {
            return baseName
        }

        return "\(baseName), \(typeName)"
    }
}
