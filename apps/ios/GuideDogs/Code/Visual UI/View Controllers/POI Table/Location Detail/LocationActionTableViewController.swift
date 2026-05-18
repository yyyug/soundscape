//
//  LocationActionTableViewController.swift
//  Soundscape
//
//  Copyright (c) Microsoft Corporation.
//  Licensed under the MIT License.
//

import Foundation
import UIKit
import MapKit

class LocationActionTableViewController: UITableViewController {
    
    // MARK: Properties
    
    private static let prototypeCellIdentifier = "ActionCell"
    
    private let defaultCell = UITableViewCell(style: .default, reuseIdentifier: "DefaultCell")
    private let previewMapView = MKMapView(frame: .zero)
    private let previewContainerView = UIView(frame: .zero)
    private let previewTitleLabel = UILabel(frame: .zero)

    weak var delegate: LocationActionDelegate?
    
    var locationDetail: LocationDetail? {
        didSet {
            guard isViewLoaded else {
                return
            }
            
            tableView.reloadData()
            updateMapPreview()
        }
    }
    
    private var actions: [LocationAction] {
        guard let locationDetail = locationDetail else {
            return []
        }
        
        return LocationAction.actions(for: locationDetail)
    }
    
    // MARK: View Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()
        configureMapPreviewFooter()
        updateMapPreview()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        updateMapPreviewFooterFrame()
        preferredContentSize.height = UIView.preferredContentHeight(for: tableView)
    }

    private func configureMapPreviewFooter() {
        previewContainerView.backgroundColor = Colors.Background.primary

        previewTitleLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        previewTitleLabel.textColor = Colors.Foreground.secondary
        previewTitleLabel.text = GDLocalizedString("location_detail.map.view.title")

        previewMapView.showsCompass = false
        previewMapView.showsScale = false
        previewMapView.isRotateEnabled = false
        previewMapView.isPitchEnabled = false
        previewMapView.isScrollEnabled = false
        previewMapView.isZoomEnabled = false
        previewMapView.layer.cornerRadius = 8.0
        previewMapView.clipsToBounds = true

        previewContainerView.addSubview(previewTitleLabel)
        previewContainerView.addSubview(previewMapView)
        tableView.tableFooterView = previewContainerView
    }

    private func updateMapPreviewFooterFrame() {
        let width = tableView.bounds.width
        guard width > 0 else {
            return
        }

        let horizontalPadding: CGFloat = 16.0
        let titleTop: CGFloat = 10.0
        let titleHeight: CGFloat = 18.0
        let mapTop: CGFloat = 34.0
        let mapHeight: CGFloat = 168.0
        let totalHeight: CGFloat = 212.0

        previewContainerView.frame = CGRect(x: 0.0, y: 0.0, width: width, height: totalHeight)
        previewTitleLabel.frame = CGRect(x: horizontalPadding,
                                         y: titleTop,
                                         width: width - horizontalPadding * 2.0,
                                         height: titleHeight)
        previewMapView.frame = CGRect(x: horizontalPadding,
                                      y: mapTop,
                                      width: width - horizontalPadding * 2.0,
                                      height: mapHeight)

        tableView.tableFooterView = previewContainerView
    }

    private func updateMapPreview() {
        guard let detail = locationDetail else {
            previewContainerView.isHidden = true
            return
        }

        previewContainerView.isHidden = false
        previewMapView.removeAnnotations(previewMapView.annotations)

        let annotation = MKPointAnnotation()
        annotation.coordinate = detail.location.coordinate
        annotation.title = detail.displayName
        previewMapView.addAnnotation(annotation)

        let region = MKCoordinateRegion(center: detail.location.coordinate,
                                        latitudinalMeters: 320.0,
                                        longitudinalMeters: 320.0)
        previewMapView.setRegion(region, animated: false)
    }
    
    // MARK: `UITableViewDataSource`
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        guard locationDetail != nil else {
            return 0
        }
        
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard locationDetail != nil else {
            return 0
        }
        
        guard section == 0 else {
            return 0
        }
        
        return actions.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard indexPath.section == 0 else {
            return defaultCell
        }
        
        guard indexPath.row < actions.count else {
            return defaultCell
        }
        
        let action = actions[indexPath.row]
        
        let identifier = LocationActionTableViewController.prototypeCellIdentifier
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath)
        
        cell.textLabel?.text = action.text
        cell.accessibilityHint = action.accessibilityHint
        cell.accessibilityIdentifier = action.accessibilityIdentifier
        cell.imageView?.image = action.image
        
        if action.isEnabled {
            cell.selectionStyle = .default
            cell.textLabel?.isEnabled = true
            cell.imageView?.alpha = 1.0
        } else {
            cell.selectionStyle = .none
            cell.textLabel?.isEnabled = false
            cell.imageView?.alpha = 0.4
        }
        
        // Image view will scale with content size
        cell.imageView?.adjustsImageSizeForAccessibilityContentSizeCategory = true
        
        return cell
    }
    
    // MARK: `UITableViewDelegate`
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer {
            tableView.deselectRow(at: indexPath, animated: true)
        }
        
        guard indexPath.section == 0 else {
            return
        }
        
        guard indexPath.row < actions.count else {
            return
        }
        
        guard let delegate = delegate else {
            return
        }
        
        guard let detail = locationDetail else {
            return
        }
        
        let action = actions[indexPath.row]
        
        guard action.isEnabled else {
            return
        }
        
        delegate.didSelectLocationAction(action, detail: detail)
    }
    
}
