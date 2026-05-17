//
//  SearchResultsUpdater.swift
//  Soundscape
//
//  Copyright (c) Microsoft Corporation.
//  Licensed under the MIT License.
//

import Foundation
import UIKit
import CoreLocation
import MapKit

protocol SearchResultsUpdaterDelegate: AnyObject {
    func searchResultsDidStartUpdating()
    func searchResultsDidUpdate(_ searchResults: [POI], searchLocation: CLLocation?)
    func searchResultsDidUpdate(_ searchForMore: String?)
    func searchWasCancelled()
    var isPresentingDefaultResults: Bool { get }
    var telemetryContext: String { get }
    // Set `isCachingRequired = true` if a selected search result will
    // be cached on device
    // Search results can only be cached when an unencumbered coordinate is available
    var isCachingRequired: Bool { get }
}

class SearchResultsUpdater: NSObject {
    
    enum Context {
        case partialSearchText
        case completeSearchText
    }
    
    // MARK: Properties
    
    weak var delegate: SearchResultsUpdaterDelegate?
    private var searchRequestToken: RequestToken?
    private var searchResultsUpdating = false
    private(set) var searchBarButtonClicked = false
    private var location: CLLocation?
    var context: Context = .partialSearchText
    
    // MARK: Initialization
    
    override init() {
        super.init()
        
        // Save user's current location
        location = AppContext.shared.geolocationManager.location
        
        // Observe changes in user's location
        // This is required so that we can present all search
        // results with an accurate distance
        NotificationCenter.default.addObserver(self, selector: #selector(self.onLocationUpdated(_:)), name: Notification.Name.locationUpdated, object: nil)
    }
    
    deinit {
        searchRequestToken?.cancel()
    }
    
    // MARK: Notifications
    
    @objc
    private func onLocationUpdated(_ notification: Notification) {
        guard let location = notification.userInfo?[SpatialDataContext.Keys.location] as? CLLocation else {
            return
        }
        
        self.location = location
    }
    
    // MARK: Selecting Search Results
    
    func selectSearchResult(_ poi: POI, completion: @escaping (SearchResult?, SearchResultError?) -> Void) {
        if let delegate = delegate, delegate.isPresentingDefaultResults {
            GDATelemetry.track("recent_entity_selected.search", with: ["context": delegate.telemetryContext])
            completion(.entity(poi), nil)
        } else {
            completion(.entity(poi), nil)
        }
    }
    
}

// MARK: - UISearchResultsUpdating

extension SearchResultsUpdater: UISearchResultsUpdating {
    
    func updateSearchResults(for searchController: UISearchController) {
        searchBarButtonClicked = false
        
        if let searchBarText = searchController.searchBar.text, searchBarText.isEmpty == false {
            // Fetch new search results
            switch context {
            case .partialSearchText: partialSearchWithText(searchText: searchBarText)
            case .completeSearchText: searchWithText(searchText: searchBarText)
            }
        } else {
            searchResultsUpdating = false
            // There is no search text
            // Clear current search results
            delegate?.searchResultsDidUpdate([], searchLocation: nil)
        }
    }
    
    private func partialSearchWithText(searchText: String) {
        if searchResultsUpdating == false {
            searchResultsUpdating = true
            // Notify the delegate when a new update
            // begins
            delegate?.searchResultsDidStartUpdating()
        }
        
        guard AppContext.shared.offlineContext.state == .online else {
            return
        }
        
        GDATelemetry.track("autosuggest.request_made", with: ["context": delegate?.telemetryContext ?? ""])
        
        searchRequestToken?.cancel()
        
        guard let userLocation = location else {
            delegate?.searchResultsDidUpdate([], searchLocation: nil)
            return
        }
        
        // Fetch autosuggest results with new search text from all sources
        let searchCoordinator = SearchPOICoordinator()
        searchCoordinator.searchPOIs(searchText: searchText, userLocation: userLocation) { [weak self] results in
            self?.delegate?.searchResultsDidUpdate(results, searchLocation: userLocation)
        }
    }
    
}

// MARK: - UISearchBarDelegate

extension SearchResultsUpdater: UISearchBarDelegate {
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBarButtonClicked = true
        
        guard let searchBarText = searchBar.text, searchBarText.isEmpty == false else {
            // Return if there is no search text
            return
        }
        
        self.searchWithText(searchText: searchBarText)
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        delegate?.searchWasCancelled()
    }
    
    private func searchWithText(searchText: String) {
        // Notify the delegate when a new update
        // begins
        delegate?.searchResultsDidStartUpdating()
        
        guard AppContext.shared.offlineContext.state == .online else {
            return
        }
        
        GDATelemetry.track("search.request_made", with: ["context": delegate?.telemetryContext ?? ""])
        
        searchRequestToken?.cancel()
        
        guard let userLocation = location else {
            delegate?.searchResultsDidUpdate([], searchLocation: nil)
            return
        }
        
        // Fetch results from all three sources
        let searchCoordinator = SearchPOICoordinator()
        searchCoordinator.searchPOIs(searchText: searchText, userLocation: userLocation) { [weak self] results in
            self?.delegate?.searchResultsDidUpdate(results, searchLocation: userLocation)
        }
    }
    
}

// MARK: - SearchPOICoordinator

private final class SearchPOICoordinator {
    func searchPOIs(searchText: String, userLocation: CLLocation, completion: @escaping ([POI]) -> Void) {
        AppContext.shared.spatialDataContext.updateSpatialData(at: userLocation) {
            var osmResults: [POI] = []
            var appleResults: [POI] = []
            var overtureResults: [POI] = []
            
            let group = DispatchGroup()
            
            group.enter()
            self.searchOSMPOIs(searchText: searchText, userLocation: userLocation) { results in
                osmResults = results
                group.leave()
            }
            
            group.enter()
            self.searchApplePOIs(searchText: searchText, userLocation: userLocation) { results in
                appleResults = results
                group.leave()
            }
            
            group.enter()
            self.searchOverturePOIs(searchText: searchText, userLocation: userLocation) { results in
                overtureResults = results
                group.leave()
            }
            
            group.notify(queue: .main) {
                let merged = self.mergeAndDeduplicate(osmResults + appleResults + overtureResults, userLocation: userLocation)
                completion(merged)
            }
        }
    }
    
    private func searchOSMPOIs(searchText: String, userLocation: CLLocation, completion: @escaping ([POI]) -> Void) {
        guard let dataView = AppContext.shared.spatialDataContext.getDataView(for: userLocation,
                                                                               searchDistance: SpatialDataContext.cacheDistance) else {
            completion([])
            return
        }
        
        let filtered = dataView.pois.filter { poi in
            poi.localizedName.localizedCaseInsensitiveContains(searchText) ||
            (poi.addressLine?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
        
        let sorted = filtered.sorted { $0.distanceToClosestLocation(from: userLocation) < $1.distanceToClosestLocation(from: userLocation) }
        completion(Array(sorted.prefix(50)))
    }
    
    private func searchApplePOIs(searchText: String, userLocation: CLLocation, completion: @escaping ([POI]) -> Void) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        request.region = MKCoordinateRegion(center: userLocation.coordinate,
                                            latitudinalMeters: 5000,
                                            longitudinalMeters: 5000)
        
        MKLocalSearch(request: request).start { response, _ in
            guard let mapItems = response?.mapItems else {
                completion([])
                return
            }
            
            let results: [POI] = mapItems.compactMap { mapItem in
                let coordinate = mapItem.placemark.coordinate
                guard CLLocationCoordinate2DIsValid(coordinate) else {
                    return nil
                }
                
                let name = mapItem.name ?? mapItem.placemark.name ?? "Location"
                let address = mapItem.placemark.title
                let location = GenericLocation(lat: coordinate.latitude,
                                               lon: coordinate.longitude,
                                               name: name,
                                               address: address)
                return location as POI
            }
            
            completion(results)
        }
    }
    
    private func searchOverturePOIs(searchText: String, userLocation: CLLocation, completion: @escaping ([POI]) -> Void) {
        guard let baseURL = overturePOIBaseURL() else {
            completion([])
            return
        }
        
        guard var components = URLComponents(string: baseURL) else {
            completion([])
            return
        }
        
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "lat", value: String(userLocation.coordinate.latitude)))
        queryItems.append(URLQueryItem(name: "lon", value: String(userLocation.coordinate.longitude)))
        queryItems.append(URLQueryItem(name: "radius", value: "5000"))
        queryItems.append(URLQueryItem(name: "query", value: searchText))
        queryItems.append(URLQueryItem(name: "limit", value: "100"))
        
        components.queryItems = queryItems
        
        guard let url = components.url else {
            completion([])
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            
            let results = self.parseOvertureResults(from: data, userLocation: userLocation)
            DispatchQueue.main.async { completion(results) }
        }.resume()
    }
    
    private func parseOvertureResults(from data: Data, userLocation: CLLocation) -> [POI] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        let rows: [[String: Any]]
        if let array = json as? [[String: Any]] {
            rows = array
        } else if let dict = json as? [String: Any] {
            if let results = dict["results"] as? [[String: Any]] {
                rows = results
            } else if let result = dict["result"] as? [[String: Any]] {
                rows = result
            } else if let features = dict["features"] as? [[String: Any]] {
                rows = features
            } else if let items = dict["items"] as? [[String: Any]] {
                rows = items
            } else {
                rows = []
            }
        } else {
            rows = []
        }

        return rows.compactMap { row in
            let rowName = row["name"] as? String
                ?? row["title"] as? String
                ?? row["display_name"] as? String

            let props = row["properties"] as? [String: Any]
            let name = rowName ?? props?["name"] as? String ?? GDLocalizedString("location")

            var latitude = row["lat"] as? CLLocationDegrees
                ?? row["latitude"] as? CLLocationDegrees
            var longitude = row["lon"] as? CLLocationDegrees
                ?? row["lng"] as? CLLocationDegrees
                ?? row["longitude"] as? CLLocationDegrees

            if (latitude == nil || longitude == nil),
               let geometry = row["geometry"] as? [String: Any],
               let coordinates = geometry["coordinates"] as? [CLLocationDegrees],
               coordinates.count >= 2 {
                longitude = coordinates[0]
                latitude = coordinates[1]
            }

            guard let lat = latitude, let lon = longitude else {
                return nil
            }

            let address = row["address"] as? String
                ?? props?["address"] as? String

            let location = GenericLocation(lat: lat,
                                           lon: lon,
                                           name: name,
                                           address: address)
            return location as POI
        }
    }
    
    private func mergeAndDeduplicate(_ items: [POI], userLocation: CLLocation) -> [POI] {
        var seen: Set<String> = []
        var result: [POI] = []
        
        for poi in items {
            let coordinate = poi.closestLocation(from: userLocation).coordinate
            let key = "\(String(format: "%.4f", coordinate.latitude))-\(String(format: "%.4f", coordinate.longitude))"
            if !seen.contains(key) {
                seen.insert(key)
                result.append(poi)
            }
        }
        
        return result.sorted { $0.distanceToClosestLocation(from: userLocation) < $1.distanceToClosestLocation(from: userLocation) }
    }
    
    private func overturePOIBaseURL() -> String? {
        if let customURL = UserDefaults.standard.string(forKey: "overture.poi.api.base_url"), !customURL.isEmpty {
            return customURL
        }

        if let customURL = Bundle.main.object(forInfoDictionaryKey: "OverturePOIBaseURL") as? String,
           !customURL.isEmpty {
            return customURL
        }
        
        return nil
    }
}
