//
//  CalloutButtonViewController.swift
//  Soundscape
//
//  Copyright (c) Microsoft Corporation.
//  Licensed under the MIT License.
//

import Foundation
import UIKit
import CoreLocation
import NVActivityIndicatorView

extension NSNotification.Name {
    static let didToggleLocate = Notification.Name("DidToggleLocate")
    static let didToggleOrientate = Notification.Name("DidToggleOrientate")
    static let didToggleLookAhead = Notification.Name("DidToggleLookAhead")
    static let didToggleMarkedPoints = Notification.Name("DidToggleMarkedPoints")
}

class CalloutButtonPanelViewController: UIViewController {
    
    // MARK: Properties
    
    @IBOutlet var headerLabel: UILabel!
    @IBOutlet var buttonLabels: [UILabel]!
    @IBOutlet weak var modeLabel: UILabel!
    
    // Buttons
    @IBOutlet weak var locateContainer: UIView!
    @IBOutlet weak var orientContainer: UIView!
    @IBOutlet weak var exploreContainer: UIView!
    @IBOutlet weak var markedPointsContainer: UIView!
    
    // Images
    @IBOutlet weak var locateImageView: UIImageView!
    @IBOutlet weak var orientateImageView: UIImageView!
    @IBOutlet weak var exploreImageView: UIImageView!
    @IBOutlet weak var markedPointImageView: UIImageView!
    
    // Button Animations
    @IBOutlet weak var locateAnimation: NVActivityIndicatorView!
    @IBOutlet weak var orientateAnimation: NVActivityIndicatorView!
    @IBOutlet weak var exploreAnimation: NVActivityIndicatorView!
    @IBOutlet weak var markedPointsAnimation: NVActivityIndicatorView!
    
    var logContext: String?
    var onShowLocationDetailsRequested: (() -> Void)?
    var onShowAroundPOIListRequested: (() -> Void)?
    var onShowAheadPOIListRequested: (() -> Void)?

    private var headingObserver: Heading?
    private lazy var statusFooterLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = Colors.Foreground.primary
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.numberOfLines = 1
        return label
    }()
    
    // MARK: View Life Cycle

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Configure header
        headerLabel.text = GDLocalizedString("callouts.panel.title").uppercasedWithAppLocale()
        headerLabel.isHidden = true
                
        configureButtonLabels()
        modeLabel?.isHidden = true
        updateModeLabel()
        configureStatusFooter()
        subscribeStatusUpdates()
        updateGPSStatus()
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.handleDidToggleLocateNotification), name: Notification.Name.didToggleLocate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.handleDidToggleOrientateNotification), name: Notification.Name.didToggleOrientate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.handleDidToggleLookAheadNotification), name: Notification.Name.didToggleLookAhead, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.handleDidToggleMarkedPointsNotification), name: Notification.Name.didToggleMarkedPoints, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.handleLocationUpdatedNotification), name: .locationUpdated, object: nil)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        let width = preferredContentSize.width
        let height = UIView.preferredContentHeightCompressedHeight(for: view)
        
        preferredContentSize = CGSize(width: width, height: height)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if let element = UIView.setGroupAccessibilityElement(for: locateContainer,
                                                             label: GDLocalizedString("directions.my_location"),
                                                             hint: GDLocalizedString("ui.action_button.my_location.acc_hint"),
                                                             traits: [.button]) {
            element.accessibilityIdentifier = "btn.mylocation"
            element.accessibilityCustomActions = [
                UIAccessibilityCustomAction(name: GDLocalizedString("ui.action_button.my_location.action.start_audio_beacon"), target: self, selector: #selector(onStartAudioBeaconAccessibilityAction)),
                UIAccessibilityCustomAction(name: GDLocalizedString("location_detail.title.default"), target: self, selector: #selector(onLocationDetailsAccessibilityAction))
            ]
        }
        
        if let element = UIView.setGroupAccessibilityElement(for: orientContainer,
                                                             label: GDLocalizedString("help.orient.page_title"),
                                                             hint: GDLocalizedString("ui.action_button.around_me.acc_hint"),
                                                             traits: [.button]) {
            element.accessibilityIdentifier = "btn.aroundme"
            element.accessibilityCustomActions = [UIAccessibilityCustomAction(name: GDLocalizedString("exploration.poi.list.action"), target: self, selector: #selector(onAroundPOIListAccessibilityAction))]
        }
        
        if let element = UIView.setGroupAccessibilityElement(for: exploreContainer,
                                                             label: GDLocalizedString("help.explore.page_title"),
                                                             hint: GDLocalizedString("ui.action_button.ahead_of_me.acc_hint"),
                                                             traits: [.button]) {
            element.accessibilityIdentifier = "btn.aheadofme"
            element.accessibilityCustomActions = [UIAccessibilityCustomAction(name: GDLocalizedString("exploration.poi.list.action"), target: self, selector: #selector(onAheadPOIListAccessibilityAction))]
        }
        
        if let element = UIView.setGroupAccessibilityElement(for: markedPointsContainer,
                                                             label: GDLocalizedString("callouts.nearby_markers"),
                                                             hint: GDLocalizedString("ui.action_button.nearby_markers.acc_hint"),
                                                             traits: [.button]) {
            element.accessibilityIdentifier = "btn.nearbymarkers"
        }
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        
        configureButtonLabels()
    }
    
    private func configureButtonLabels() {
        // When the font is scaled to an accessibility size, we need to use a slightly smaller text
        // style to prevent text from getting cut off in the callout button panel
        let font = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ?
            UIFont.preferredFont(forTextStyle: .caption2) :
            UIFont.preferredFont(forTextStyle: .footnote)
        
        buttonLabels.forEach { ( label) in
            label.font = font
        }
    }

    private func configureStatusFooter() {
        view.addSubview(statusFooterLabel)

        NSLayoutConstraint.activate([
            statusFooterLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8.0),
            statusFooterLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8.0),
            statusFooterLabel.topAnchor.constraint(greaterThanOrEqualTo: markedPointsContainer.bottomAnchor, constant: 4.0),
            statusFooterLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4.0)
        ])
    }

    private func subscribeStatusUpdates() {
        headingObserver = AppContext.shared.geolocationManager.heading(orderedBy: [.user, .device, .course])
        headingObserver?.onHeadingDidUpdate { [weak self] _ in
            self?.updateGPSStatus()
        }
    }

    private func updateModeLabel() {
        guard let modeLabel = modeLabel else {
            GDLogAppError("modeLabel is not initialized")
            return
        }
        modeLabel.text = SettingsContext.shared.calloutRangeMode.localizedName
    }

    private func updateGPSStatus() {
        guard let location = AppContext.shared.geolocationManager.location else {
            statusFooterLabel.text = nil
            statusFooterLabel.accessibilityLabel = nil
            return
        }

        var components: [String] = []

        if SettingsContext.shared.gpsAccuracyEnabled {
            let accuracy = LanguageFormatter.string(from: max(location.horizontalAccuracy, 0.0), rounded: true)
            components.append(GDLocalizedString("status.gps.accuracy.component", accuracy))
        }

        if SettingsContext.shared.gpsSpeedEnabled,
           let speed = formattedSpeed(from: location) {
            components.append(GDLocalizedString("status.gps.speed.component", speed))
        }

        let status = components.isEmpty ? nil : components.joined(separator: " | ")

        statusFooterLabel.text = status
        statusFooterLabel.accessibilityLabel = status
    }

    private func formattedSpeed(from location: CLLocation) -> String? {
        guard location.speed >= 0 else {
            return nil
        }

        let preferredUnit: UnitSpeed = SettingsContext.shared.metricUnits ? .kilometersPerHour : .milesPerHour
        let converted = Measurement(value: location.speed, unit: UnitSpeed.metersPerSecond).converted(to: preferredUnit)
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .short

        let numberFormatter = NumberFormatter()
        numberFormatter.maximumFractionDigits = 1
        numberFormatter.minimumFractionDigits = 0
        formatter.numberFormatter = numberFormatter

        return formatter.string(from: converted)
    }
    
    // MARK: `IBAction`
    
    @IBAction private func onLocateTouchUpInside(_ sender: AnyObject?) {
        updateAnimation(locateImageView, locateAnimation, true)
        
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let imageView = self?.locateImageView else {
                return
            }
            
            guard let animationView = self?.locateAnimation else {
                return
            }
            
            self?.updateAnimation(imageView, animationView, false)
        }
        
        // Prefetch fresh spatial data for reverse geocoding accuracy
        guard let location = AppContext.shared.geolocationManager.location else {
            let event: Event
            if let preview = AppContext.shared.eventProcessor.activeBehavior as? PreviewBehavior<IntersectionDecisionPoint> {
                event = PreviewMyLocationEvent(current: preview.currentDecisionPoint.value, completionHandler: completion)
            } else {
                event = ExplorationModeToggled(.locate, sender: sender, logContext: logContext, completion: completion)
            }
            AppContext.process(event)
            return
        }
        
        // Prefetch spatial data before triggering locate mode
        AppContext.shared.spatialDataContext.updateSpatialData(at: location) { [weak self] in
            guard let self = self else { return }
            
            let event: Event
            if let preview = AppContext.shared.eventProcessor.activeBehavior as? PreviewBehavior<IntersectionDecisionPoint> {
                event = PreviewMyLocationEvent(current: preview.currentDecisionPoint.value, completionHandler: completion)
            } else {
                event = ExplorationModeToggled(.locate, sender: sender, logContext: self.logContext, completion: completion)
            }
            AppContext.process(event)
        }
    }
    
    @IBAction private func onOrientateTouchUpInside(_ sender: AnyObject?) {
        updateAnimation(orientateImageView, orientateAnimation, true)

        runExplorationModeWithFreshSpatialData(.aroundMe, sender: sender) { [weak self] _ in
            guard let imageView = self?.orientateImageView else {
                return
            }
            
            guard let animationView = self?.orientateAnimation else {
                return
            }
            
            self?.updateAnimation(imageView, animationView, false)
        }
    }
    
    @IBAction private func onLookAheadTouchUpInside(_ sender: AnyObject?) {
        updateAnimation(exploreImageView, exploreAnimation, true)
        
        runExplorationModeWithFreshSpatialData(.aheadOfMe, sender: sender) { [weak self] _ in
            guard let imageView = self?.exploreImageView else {
                return
            }
            
            guard let animationView = self?.exploreAnimation else {
                return
            }
            
            self?.updateAnimation(imageView, animationView, false)
        }
    }
    
    @IBAction private func onMarkedPointsTouchUpInside(_ sender: AnyObject?) {
        playNearbyMarkers(sender)
    }

    private func playNearbyMarkers(_ sender: AnyObject?) {
        updateAnimation(markedPointImageView, markedPointsAnimation, true)

        AppContext.process(ExplorationModeToggled(.nearbyMarkers, sender: sender, logContext: logContext) { [weak self] _ in
            guard let imageView = self?.markedPointImageView else {
                return
            }

            guard let animationView = self?.markedPointsAnimation else {
                return
            }

            self?.updateAnimation(imageView, animationView, false)
        })
    }

    private func runExplorationModeWithFreshSpatialData(_ mode: ExplorationGenerator.Mode,
                                                        sender: AnyObject?,
                                                        completion: @escaping (Bool) -> Void) {
        let triggerMode = {
            AppContext.process(ExplorationModeToggled(mode, sender: sender, logContext: self.logContext, completion: completion))
        }

        guard let location = AppContext.shared.geolocationManager.location else {
            triggerMode()
            return
        }

        _ = AppContext.shared.spatialDataContext.updateSpatialData(at: location) {
            triggerMode()
        }
    }

    
    // MARK: Notifications
    
    @objc func handleDidToggleLocateNotification(_ notification: Notification) {
        onLocateTouchUpInside(notification.object as AnyObject?)
    }
    
    @objc func handleDidToggleOrientateNotification(_ notification: Notification) {
        onOrientateTouchUpInside(notification.object as AnyObject?)
    }
    
    @objc func handleDidToggleLookAheadNotification(_ notification: Notification) {
        onLookAheadTouchUpInside(notification.object as AnyObject?)
    }
    
    @objc func handleDidToggleMarkedPointsNotification(_ notification: Notification) {
        onMarkedPointsTouchUpInside(notification.object as AnyObject?)
    }

    @objc private func handleLocationUpdatedNotification(_ notification: Notification) {
        updateGPSStatus()
    }

    @objc private func onLocationDetailsAccessibilityAction() -> Bool {
        onShowLocationDetailsRequested?()
        return true
    }

    @objc private func onStartAudioBeaconAccessibilityAction() -> Bool {
        guard let location = AppContext.shared.geolocationManager.location else {
            return false
        }

        do {
            let name = GDLocalizedString("directions.my_location")
            try AppContext.shared.spatialDataContext.destinationManager.setDestination(location: location,
                                                                                       behavior: name,
                                                                                       enableAudio: true,
                                                                                       userLocation: location,
                                                                                       logContext: "home_my_location_action")
            return true
        } catch {
            return false
        }
    }

    @objc private func onAroundPOIListAccessibilityAction() -> Bool {
        onShowAroundPOIListRequested?()
        return true
    }

    @objc private func onAheadPOIListAccessibilityAction() -> Bool {
        onShowAheadPOIListRequested?()
        return true
    }
    
    // MARK: Button Animations
    
    fileprivate func updateAnimation(_ imageView: UIImageView, _ animationView: NVActivityIndicatorView, _ show: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let `self` = self else {
                return
            }
            
            guard show != animationView.isAnimating else {
                return
            }
            
            self.stopButtonAnimations()
            imageView.isHidden = show
            
            if show {
                animationView.startAnimating()
            } else {
                animationView.stopAnimating()
            }
        }
    }
    
    private func stopButtonAnimations() {
        if locateAnimation.isAnimating {
            locateAnimation.stopAnimating()
            locateImageView.isHidden = false
        }
        
        if markedPointsAnimation.isAnimating {
            markedPointsAnimation.stopAnimating()
            markedPointImageView.isHidden = false
        }
        
        if orientateAnimation.isAnimating {
            orientateAnimation.stopAnimating()
            orientateImageView.isHidden = false
        }
        
        if exploreAnimation.isAnimating {
            exploreAnimation.stopAnimating()
            exploreImageView.isHidden = false
        }
    }
    
}
