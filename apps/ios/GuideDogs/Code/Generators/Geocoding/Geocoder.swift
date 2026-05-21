//
//  Geocoder.swift
//  Soundscape
//
//  Copyright (c) Microsoft Corporation.
//  Licensed under the MIT License.
//

import Foundation
import CoreLocation
import Contacts

class Geocoder {
    
    // MARK: Properties
    
    private let geocoder: AddressGeocoderProtocol
    private let addressFormatter = AddressFormatter()
    
    // MARK: Initialization
    
    init(geocoder: AddressGeocoderProtocol) {
        self.geocoder = geocoder
    }

    private func streetFirstAddressLine(from placemark: CLPlacemark, fallback: String) -> String {
        let isChineseLocale = LocalizationContext.currentAppLocale.identifier.lowercased().hasPrefix("zh")

        let street: String = {
            let thoroughfare = placemark.thoroughfare?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let subThoroughfare = placemark.subThoroughfare?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if !thoroughfare.isEmpty && !subThoroughfare.isEmpty {
                return isChineseLocale ? "\(thoroughfare)\(subThoroughfare)" : "\(subThoroughfare) \(thoroughfare)"
            }

            if !thoroughfare.isEmpty {
                return thoroughfare
            }

            if !subThoroughfare.isEmpty {
                return subThoroughfare
            }

            return placemark.street?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }()

        let cityComponents = [
            placemark.subLocality,
            placemark.locality,
            placemark.subAdministrativeArea,
            placemark.administrativeArea
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        var dedupedCity: [String] = []
        for component in cityComponents where !dedupedCity.contains(component) {
            dedupedCity.append(component)
        }

        let city = dedupedCity.first ?? ""

        if !street.isEmpty && !city.isEmpty {
            return "\(street), \(city)"
        }

        if !street.isEmpty {
            return street
        }

        return fallback
    }
    
    private func processPlacemarks(_ placemarks: [CLPlacemark]) -> [GeocodedAddress] {
        var geocodedComponents: [GeocodedAddress] = []
        
        for placemark in placemarks {
            guard let placemarkLocation = placemark.location else { continue }
            guard let placemarkAddress = addressFormatter.format(from: placemark, country: false) else { continue }
            let formattedPlacemarkAddress = placemarkAddress.replacingOccurrences(of: "\n", with: ", ")
            let streetFirstAddress = streetFirstAddressLine(from: placemark, fallback: formattedPlacemarkAddress)
            
            let placemarkStreet = placemark.street ?? placemark.subLocality ?? placemark.state ?? placemark.subAdministrativeArea ?? placemark.state ?? ""
            
            let component = GeocodedAddress(name: placemark.name ?? placemarkStreet,
                                            location: placemarkLocation,
                                            addressLine: streetFirstAddress,
                                            streetName: placemarkStreet,
                                            subThoroughfare: placemark.subThoroughfare,
                                            houseNumber: placemark.subThoroughfare)
            geocodedComponents.append(component)
        }
        
        return geocodedComponents
    }
    
    // MARK: Forward Geocoding Methods
    
    func geocodeAddressString(address: String, in region: CLRegion? = nil, completionHandler: @escaping ([GeocodedAddress]?) -> Void) {
        // If we cannot call the geocoding service or the geocoding fails, return nil
        // else, return an array or results
        
        guard AppContext.shared.device.isNetworkConnectionAvailable else {
            // Always call completion handler
            completionHandler(nil)
            return
        }

        // Call geocoding service
        // When input region is `nil` and location services are enabled,
        // the geocoder will use the user's location to pick the best results
        geocoder.geocodeAddressString(address, in: region, preferredLocale: LocalizationContext.currentAppLocale, completionHandler: { [weak self] (results, error) in
            guard error == nil else {
                completionHandler(nil)
                return
            }
            
            guard let results = results else {
                completionHandler(nil)
                return
            }
            
            completionHandler(self?.processPlacemarks(results))
        })
    }
    
    // MARK: Reverse Geocoding Methods
    
    func geocodeLocation(location: CLLocation, completionHandler: @escaping ([GeocodedAddress]?) -> Void) {
        // If we cannot call the geocoding service or the geocoding fails, return nil
        // else, return an array or results
        
        guard AppContext.shared.device.isNetworkConnectionAvailable else {
            // Always call completion handler
            completionHandler(nil)
            return
        }
        
        let timeout = DispatchWorkItem { [weak self] in
            self?.geocoder.cancelGeocode()
            completionHandler(nil)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2), execute: timeout)
        
        // Call geocoding service
        // When input region is `nil` and location services are enabled,
        // the geocoder will use the user's location to pick the best results
        geocoder.reverseGeocodeLocation(location, preferredLocale: LocalizationContext.currentAppLocale, completionHandler: { [weak self] (results, error) in
            timeout.cancel()
            
            guard error == nil else {
                if let error = error as? CLError, error.code == CLError.Code.network {
                    GDATelemetry.track("geocoder.apple.rate_limit_exceeded")
                    GDLogError(.application, "Apple Geocoder rate limit exceeded")
                }
                
                completionHandler(nil)
                return
            }
            
            guard let results = results else {
                completionHandler(nil)
                return
            }
            
            completionHandler(self?.processPlacemarks(results))
        })
    }
}
