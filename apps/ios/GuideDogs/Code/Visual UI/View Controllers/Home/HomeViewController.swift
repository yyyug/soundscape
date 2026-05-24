//
//  HomeViewController.swift
//  Soundscape
//
//  Copyright (c) Microsoft Corporation.
//  Licensed under the MIT License.
//

import UIKit
import CoreMotion
import CoreLocation
import MapKit
import AVFoundation
import ARKit
#if canImport(ARCore)
import ARCore
#endif
import MessageUI
import CocoaLumberjackSwift
import SwiftUI
import Combine

extension Notification.Name {
    static let homeViewControllerDidLoad = Notification.Name("HomeViewControllerDidLoad")
}

class HomeViewController: UIViewController {
    
    // MARK: Segues
    
    struct Segue {
        
        // Main Menu Segues
        
        static let showRecreationActivities = "ShowRecreationActivities"
        static let showManageDevices = "ShowManageDevices"
        static let showStatus = "ShowStatus"
        static let showHelp = "ShowHelpSegue"
        static let showSettings = "ShowSettingsSegue"
        
        /// This method returns the segue associated with items in the main menu.
        ///
        /// - Parameter menuItem: A menu item
        /// - Returns: The segue associated with this menu item
        static func segue(for menuItem: MenuItem) -> String? {
            switch menuItem {
            case .recreation: return Segue.showRecreationActivities
            case .devices:    return Segue.showManageDevices
            case .help:       return Segue.showHelp
            case .settings:   return Segue.showSettings
            case .status:     return Segue.showStatus
            default:          return nil
            }
        }
    }
    
    // MARK: Properties
    
    // Banners
    
    @IBOutlet weak var largeBannerContainerView: UIView!
    @IBOutlet var largeBannerContainerHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var smallBannerContainerView: UIView!
    @IBOutlet weak var smallBannerContainerHeightConstraint: NSLayoutConstraint!
    
    @IBOutlet weak var sleepIcon: UIImageView!
    @IBOutlet weak var sleepButton: UIButton!
    
    @IBOutlet var searchContainerHeightConstraint: NSLayoutConstraint!
    @IBOutlet var cardContainerHeightConstraint: NSLayoutConstraint!
    @IBOutlet var calloutPanelContainerHeightConstraint: NSLayoutConstraint!
    @IBOutlet var cardContainerTopConstraints: [NSLayoutConstraint]!
    
    private var previousSearchContainerHeight = 0.0
    
    fileprivate var lastLocation: CLLocation?
    
    // New feature view
    
    fileprivate var didCheckForNewFeatures = false
    
    var shouldFocusOnBeacon: Bool = false
    
    lazy var externalGPSBarButtonItem: UIBarButtonItem = {
        let icon = UIBarButtonItem(image: UIImage(named: "ic_settings_input_antenna_white"),
                               style: .plain,
                               target: nil,
                               action: nil)
        icon.accessibilityLabel = GDLocalizedString("bar_icon.external_GPS.acc_label")
        return icon
    }()

    private lazy var liveViewBarButtonItem: UIBarButtonItem = {
        let item = UIBarButtonItem(image: UIImage(systemName: "camera.viewfinder"),
                                   style: .plain,
                                   target: self,
                                   action: #selector(onLiveViewTouchUpInside))
        item.accessibilityLabel = GDLocalizedString("liveview.button.title")
        item.accessibilityHint = GDLocalizedString("liveview.screen.title")
        return item
    }()
    
    private var searchController: UISearchController?
    
    // Experiences
    
    var cardViewController: CardStateViewController?
    var experienceDidStartObserver: NSObjectProtocol?
    var experienceDidFailToDownloadObserver: NSObjectProtocol?
    var listeners: [AnyCancellable] = []
    
    // Callout Button Panel
    
    private weak var calloutButtonViewController: CalloutButtonPanelViewController?
    private var didAutoAnnounceInitialMyLocation = false
    
    // Navigation step banner (shown above the callout button panel when a beacon/route is active)
    private lazy var navigationStepContainerView: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = UIColor(named: "Background 2") ?? UIColor.secondarySystemBackground
        container.isHidden = true
        container.accessibilityTraits = .staticText
        return container
    }()

    private lazy var navigationStepIconView: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "figure.walk"))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.tintColor = .label
        view.contentMode = .scaleAspectFit
        return view
    }()

    private lazy var navigationStepLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 2
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        return label
    }()

    private var navigationStepObserver: NSObjectProtocol?
    
    override func preferredContentSizeDidChange(forChildContentContainer container: UIContentContainer) {
        super.preferredContentSizeDidChange(forChildContentContainer: container)
        
        if container is SearchTableViewController {
            searchContainerHeightConstraint.constant = container.preferredContentSize.height
            // Save value
            previousSearchContainerHeight = container.preferredContentSize.height
        }
        
        if container is CalloutButtonPanelViewController {
            calloutPanelContainerHeightConstraint.constant = container.preferredContentSize.height
        }
        
        if container is CardStateViewController {
            cardContainerHeightConstraint.constant = container.preferredContentSize.height
        }
    }
    
    private func configureSearchAndBrowseView() {
        if AppContext.shared.eventProcessor.activeBehavior is GuidedTour {
            navigationItem.searchController = nil
            searchContainerHeightConstraint.constant = 0.0
            NSLayoutConstraint.deactivate(cardContainerTopConstraints)
        } else {
            navigationItem.searchController = self.searchController
            searchContainerHeightConstraint.constant = previousSearchContainerHeight
            NSLayoutConstraint.activate(cardContainerTopConstraints)
        }
    }
    
    private func showOrRefreshExperiences() {
        if navigationController?.visibleViewController is HomeViewController {
            
            // The HomeViewController is currently the visible VC - segue to the AuthoredActivitiesList
            performSegue(withIdentifier: Segue.showRecreationActivities, sender: self)
            
        } else if let vc = navigationController?.visibleViewController as? MenuViewController {
            
            // The MenuViewController is currently the visible VC - dismiss it and segue to the AdaptiveSportsEventsList
            vc.dismiss(animated: true) { [weak self] in
                self?.performSegue(withIdentifier: Segue.showRecreationActivities, sender: self)
            }
            
        } else {
            
            // Some other view controller is currently the visible VC - return to home and then segue to the AuthoredActivitiesList
            CATransaction.begin()
            navigationController?.popToViewController(self, animated: true)
            CATransaction.setCompletionBlock { [weak self] in
                self?.performSegue(withIdentifier: Segue.showRecreationActivities, sender: self)
            }
            CATransaction.commit()
            
        }
    }
    
    @discardableResult
    func checkPermissions() -> Bool {
        let geolocationManager = AppContext.shared.geolocationManager
        
        if !geolocationManager.coreLocationServicesEnabled {
            self.performSegue(withIdentifier: "EnableLocationServices", sender: nil)
            return false
        }
        
        switch geolocationManager.coreLocationAuthorizationStatus {
        case .notDetermined:
            self.performSegue(withIdentifier: "RequestLocationServices", sender: nil)
            return false
        case .reducedAccuracyLocationAuthorized, .denied:
            self.performSegue(withIdentifier: "AuthorizeLocationServices", sender: nil)
            return false
        default:
            // Authorized
            break
        }
        
        MotionActivityContext.requestAuthorization { [unowned self] (authorized, _) in
            if !authorized && !UIDeviceManager.isSimulator {
                // While Motion & Fitness is not authorized, disable callouts
                if SettingsContext.shared.automaticCalloutsEnabled {
                    MotionActivityContext.motionFitnessDidToggleCallouts = true
                    AppContext.process(ToggleAutoCalloutsEvent(playSound: false))
                }
                
                // Use additional context regarding authorization so we can distinguish between Fitness Tracking
                // being turned off on the device and Motion & Fitness being disabled for the app
                let motionAuth = CMMotionActivityManager.authorizationStatus()
                
                if motionAuth == .notDetermined {
                    self.performSegue(withIdentifier: "RequestMotionFitness", sender: nil)
                    return
                }
                
                if motionAuth == .denied {
                    self.performSegue(withIdentifier: "AuthorizeMotionFitness", sender: nil)
                    return
                }
                
                if motionAuth == .restricted {
                    self.performSegue(withIdentifier: "EnableMotionFitness", sender: nil)
                    return
                }
                
                // We cannot distinguish between Fitness Tracking being turned off on the
                // device and Motion & Fitness being disabled for the app
                self.performSegue(withIdentifier: "AuthorizeMotionFitness", sender: nil)
                return
            } else {
                // If necessary, turn callouts back on
                if MotionActivityContext.motionFitnessDidToggleCallouts {
                    MotionActivityContext.motionFitnessDidToggleCallouts = false
                    AppContext.process(ToggleAutoCalloutsEvent(playSound: false))
                }
            }
        }
        
        return true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Restore the original top navigation search field behavior.
        self.searchController = UISearchController(delegate: self)
        self.searchController?.delegate = self
        self.searchController?.searchBar.searchTextField.accessibilityIdentifier = GDLocalizationUnnecessary("searchbar.home")

        configureSearchAndBrowseView()
        self.navigationItem.hidesSearchBarWhenScrolling = false
        self.definesPresentationContext = true
        self.navigationItem.backBarButtonItem = UIBarButtonItem.defaultBackBarButtonItem

        setupNavigationStepBanner()

        NotificationCenter.default.addObserver(self, selector: #selector(self.handleLocationUpdatedNotification), name: Notification.Name.locationUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.continueUserAction), name: Notification.Name.continueUserAction, object: nil)

        AppContext.shared.remoteCommandManager.delegate = self

        experienceDidStartObserver = NotificationCenter.default.addObserver(forName: Notification.Name.processedActivityDeepLink,
                                                                            object: nil,
                                                                            queue: OperationQueue.main,
                                                                            using: { [weak self] _ in
            self?.showOrRefreshExperiences()
        })

        experienceDidFailToDownloadObserver = NotificationCenter.default.addObserver(forName: Notification.Name.activityDownloadDidFail,
                                                                                     object: nil,
                                                                                     queue: OperationQueue.main,
                                                                                     using: { [weak self] _ in
            let alert = UIAlertController(title: GDLocalizedString("behavior.experiences.download_failed.title"),
                                          message: GDLocalizedString("behavior.experiences.download_failed.error"),
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: GDLocalizedString("general.alert.dismiss"), style: .cancel, handler: nil))
            self?.present(alert, animated: true, completion: nil)
        })

        listeners.append(NotificationCenter.default.publisher(for: .behaviorActivated)
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] _ in
                self?.configureSearchAndBrowseView()
            }))

        listeners.append(NotificationCenter.default.publisher(for: .behaviorDeactivated)
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] _ in
                self?.configureSearchAndBrowseView()
            }))

        listeners.append(NotificationCenter.default.publisher(for: .didTryActivityUpdate)
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] notification in
                guard let self = self else {
                    return
                }

                guard let userInfo = notification.userInfo,
                      let updatesAvailable = userInfo[AuthoredActivityLoader.Keys.updateAvailable] as? Bool,
                      let success = userInfo[AuthoredActivityLoader.Keys.updateSuccess] as? Bool else {
                    return
                }

                let alert: UIAlertController
                if success {
                    alert = UIAlertController.activityDidUpdate()
                } else if !updatesAvailable {
                    alert = UIAlertController.activityUpdateUnavailable()
                } else {
                    alert = UIAlertController.activityDidFailToUpdate()
                }

                self.present(alert, animated: true)
            }))

        NotificationCenter.default.post(name: Notification.Name.homeViewControllerDidLoad, object: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        GDATelemetry.trackScreenView("home")
        updateCalloutButtonTraits()

        navigationController?.setNavigationBarHidden(false, animated: true)
        navigationController?.navigationBar.configureAppearance(for: .transparentLightTitle)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.handleAppWillEnterForeground(_:)),
                                               name: Notification.Name.appWillEnterForeground,
                                               object: nil)

        guard checkPermissions() else {
            if AppContext.shared.isFirstLaunch {
                SettingsContext.shared.newFeaturesLastDisplayedVersion = AppContext.appVersion
                didCheckForNewFeatures = true
            }

            return
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if shouldFocusOnBeacon,
           UIAccessibility.isVoiceOverRunning,
           let vc = cardViewController?.currentVC as? BeaconViewHostingController {
            GDLogAppInfo("Focusing VoiceOver on the beacon UI")
            UIAccessibility.post(notification: .layoutChanged, argument: vc.view)
            shouldFocusOnBeacon = false
        }

        focusAccessibilityOnFirstItemIfNeeded()

        guard !didCheckForNewFeatures else {
            return
        }

        if AppContext.shared.newFeatures.shouldShowNewFeatures() {
            let vc = NewFeaturesViewController(nibName: "NewFeaturesView", bundle: nil)
            vc.newFeatures = AppContext.shared.newFeatures
            vc.modalPresentationStyle = .fullScreen
            vc.modalTransitionStyle = .crossDissolve
            vc.accessibilityViewIsModal = true
            self.present(vc, animated: !UIAccessibility.isVoiceOverRunning, completion: nil)
        } else {
            LaunchActivityCoordinator.coordinateActivitiesOnAppLaunch(from: self)
        }

        didCheckForNewFeatures = true
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        positionNavigationStepBanner()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        navigationController?.navigationBar.configureAppearance(for: .default)
        NotificationCenter.default.removeObserver(self, name: Notification.Name.appWillEnterForeground, object: nil)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateCalloutButtonTraits()
        configureSearchAndBrowseView()
    }

    private func updateCalloutButtonTraits() {
        guard let child = calloutButtonViewController else {
            return
        }

        if traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
            setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: .accessibilityMedium), forChild: child)
        } else {
            setOverrideTraitCollection(nil, forChild: child)
        }
    }
    
    // MARK: Navigation

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        
        if let vc = segue.destination as? LocationPermissionViewController {
            vc.displayAsModal = true
        } else if let vc = segue.destination as? MotionPermissionViewController {
            vc.displayAsModal = true
        } else if let vc = segue.destination as? DestinationTutorialIntroViewController {
            vc.source = self
            vc.logContext = telemetryContext
        } else if let vc = segue.destination as? MarkerTutorialViewController {
            vc.logContext = telemetryContext
        } else if let vc = segue.destination as? StandbyViewController {
            vc.delegate = self
        } else if let vc = segue.destination as? LoadingModalViewController {
            vc.loadingMessage = GDLocalizedString("general.loading.almost_ready")
        } else if let vc = segue.destination as? LocationDetailViewController {
            let locationDetail = sender as? LocationDetail
            vc.locationDetail = locationDetail
        } else if let vc = segue.destination as? CardStateViewController {
            cardViewController = vc
        } else if let vc = segue.destination as? CalloutButtonPanelViewController {
            calloutButtonViewController = vc
            calloutButtonViewController?.logContext = telemetryContext
            calloutButtonViewController?.onShowLiveViewRequested = { [weak self] in
                self?.onLiveViewTouchUpInside()
            }
            calloutButtonViewController?.onShowMarkersAndRoutesRequested = { [weak self] in
                self?.showMarkersAndRoutesFromHome()
            }
            calloutButtonViewController?.onShowLocationDetailsRequested = { [weak self] in
                self?.showLocationDetailsForCurrentLocation()
            }
            calloutButtonViewController?.onShowAroundPOIListRequested = { [weak self] in
                self?.presentExplorationPOICategoryScreen(for: .aroundMe)
            }
            calloutButtonViewController?.onShowAheadPOIListRequested = { [weak self] in
                self?.presentExplorationPOICategoryScreen(for: .aheadOfMe)
            }
        } else if let navigationController = segue.destination as? UINavigationController,
                  let viewController = navigationController.topViewController as? PreviewViewController {
            let locationDetail = sender as? LocationDetail
            viewController.locationDetail = locationDetail
        }
    }
    
    @IBAction func unwindToHome(segue: UIStoryboardSegue) {
        if segue.source is DestinationTutorialViewController {
            FirstUseExperience.setDidComplete(for: .beaconTutorial)
        }
        
        if segue.source is DestinationTutorialIntroViewController {
            // The user skipped the demo, so prevent it from showing again
            FirstUseExperience.setDidComplete(for: .beaconTutorial)
        }
        
        // Transparent navigation bar
        navigationController?.navigationBar.configureAppearance(for: .transparentLightTitle)
    }

    deinit {
        if let token = experienceDidStartObserver {
            NotificationCenter.default.removeObserver(token)
        }

        if let token = experienceDidFailToDownloadObserver {
            NotificationCenter.default.removeObserver(token)
        }

        listeners.cancelAndRemoveAll()

        if let observer = navigationStepObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        DDLogDebug("\(String(describing: type(of: self))) deinitialized")
    }
}

// MARK: UIViewControllerTransitioningDelegate

// This delegate is only used for animating the home screen menu in and off of the screen. This is not used for any of the other segues in the app.
extension HomeViewController: UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard presented is MenuViewController else {
            return nil
        }
        
        return MenuAnimator(.open)
    }
    
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard let dismissed = dismissed as? MenuViewController else {
            return nil
        }
        
        return MenuAnimator(.close) { [weak self] (finished) in
            guard finished else {
                return
            }

            guard let segue = Segue.segue(for: dismissed.selected) else {
                return
            }
            
            self?.performSegue(withIdentifier: segue, sender: self)
        }
    }
}

// MARK: Navigation Step Banner

private extension HomeViewController {

    /// Build the navigation step banner view and pin it just above the callout button panel.
    func setupNavigationStepBanner() {
        // Build view hierarchy: container → icon + label
        navigationStepContainerView.addSubview(navigationStepIconView)
        navigationStepContainerView.addSubview(navigationStepLabel)

        NSLayoutConstraint.activate([
            navigationStepIconView.leadingAnchor.constraint(equalTo: navigationStepContainerView.leadingAnchor, constant: 16),
            navigationStepIconView.centerYAnchor.constraint(equalTo: navigationStepContainerView.centerYAnchor),
            navigationStepIconView.widthAnchor.constraint(equalToConstant: 24),
            navigationStepIconView.heightAnchor.constraint(equalToConstant: 24),

            navigationStepLabel.leadingAnchor.constraint(equalTo: navigationStepIconView.trailingAnchor, constant: 12),
            navigationStepLabel.trailingAnchor.constraint(equalTo: navigationStepContainerView.trailingAnchor, constant: -16),
            navigationStepLabel.topAnchor.constraint(equalTo: navigationStepContainerView.topAnchor, constant: 10),
            navigationStepLabel.bottomAnchor.constraint(equalTo: navigationStepContainerView.bottomAnchor, constant: -10)
        ])

        view.addSubview(navigationStepContainerView)

        // Pin leading / trailing to the main view edges
        NSLayoutConstraint.activate([
            navigationStepContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationStepContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        // The vertical position (above the callout panel) is set in viewWillLayoutSubviews once
        // the callout button VC view is available.

        // Subscribe to navigation step updates
        navigationStepObserver = NotificationCenter.default.addObserver(
            forName: .navigationStepDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleNavigationStepUpdate(notification)
        }
    }

    func handleNavigationStepUpdate(_ notification: Notification) {
        let text = notification.userInfo?[NavigationGuidanceManager.Keys.stepText] as? String
        let hasText = text != nil && !text!.isEmpty

        navigationStepLabel.text = text
        navigationStepContainerView.accessibilityLabel = text

        UIView.animate(withDuration: 0.3) {
            self.navigationStepContainerView.isHidden = !hasText
            self.view.layoutIfNeeded()
        }
    }

    /// Re-anchor the banner above the callout panel whenever the layout changes.
    func positionNavigationStepBanner() {
        guard let calloutPanel = calloutButtonViewController?.view?.superview else { return }

        // Remove any existing top constraint for the banner
        view.constraints.filter { c in
            (c.firstItem as? UIView) == navigationStepContainerView && c.firstAttribute == .top
        }.forEach { $0.isActive = false }
        view.constraints.filter { c in
            (c.secondItem as? UIView) == navigationStepContainerView && c.secondAttribute == .bottom
        }.forEach { $0.isActive = false }

        NSLayoutConstraint.activate([
            navigationStepContainerView.bottomAnchor.constraint(equalTo: calloutPanel.topAnchor)
        ])
    }
}

// MARK: Actions

extension HomeViewController {
    @IBAction func onMenuTouchUpInside() {
        // Construct the menu and present it
        let vc = MenuViewController()
        vc.transitioningDelegate = self
        vc.modalPresentationStyle = .custom
        
        present(vc, animated: true, completion: nil)
    }
    
    @IBAction func onSleepTouchUpInside () {
        performSegue(withIdentifier: "showStandbyScreen", sender: nil)
        
        return
    }

    @objc func onLiveViewTouchUpInside() {
        let vc = LiveViewNavigationViewController()
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .fullScreen
        nav.navigationBar.configureAppearance(for: .default)
        present(nav, animated: true)
    }

    private func showMarkersAndRoutesFromHome() {
        let storyboard = UIStoryboard(name: "POITable", bundle: Bundle.main)
        guard let viewController = storyboard.instantiateViewController(withIdentifier: "MarkersAndRoutesListHostViewController") as? MarkersAndRoutesListHostViewController else {
            GDLogAppError("Failed to instantiate MarkersAndRoutesListHostViewController")
            return
        }

        viewController.onDismissPreviewHandler = { [weak self] in
            self?.navigationController?.popToRootViewController(animated: true)
        }

        navigationController?.pushViewController(viewController, animated: true)
    }

}

// MARK: Notifications

extension HomeViewController {
    
    @objc func handleAppWillEnterForeground(_ notification: Notification) {
        checkPermissions()
    }
    
    @objc func handleLocationUpdatedNotification(_ notification: Notification) {
        guard let location = notification.userInfo?[SpatialDataContext.Keys.location] as? CLLocation else {
            return
        }
        
        lastLocation = location
        attemptInitialMyLocationAnnouncementIfNeeded()
    }
    
    @objc private func continueUserAction(_ notification: Notification) {
        guard !AppContext.shared.isStreetPreviewing else {
            // `PreviewViewController` will handle the user action
            return
        }
        
        guard let userAction = notification.userInfo?[UserActionManager.Keys.userAction] as? UserAction else { return }
        
        GDLogAppInfo("Continuing user action: \(userAction.rawValue)")
        
        switch userAction {
        case .myLocation:
            calloutButtonViewController?.handleDidToggleLocateNotification(notification)
        case .aroundMe:
            calloutButtonViewController?.handleDidToggleOrientateNotification(notification)
        case .aheadOfMe:
            calloutButtonViewController?.handleDidToggleLookAheadNotification(notification)
        case .nearbyMarkers:
            calloutButtonViewController?.handleDidToggleMarkedPointsNotification(notification)
        case .search, .saveMarker, .streetPreview:
            break
        }
    }
    
}

private extension HomeViewController {
    func focusAccessibilityOnFirstItemIfNeeded() {
        guard UIAccessibility.isVoiceOverRunning else {
            return
        }

        guard presentedViewController == nil else {
            return
        }

        let firstItem = searchController?.searchBar.searchTextField
        UIAccessibility.post(notification: .screenChanged, argument: firstItem)
    }

    func attemptInitialMyLocationAnnouncementIfNeeded() {
        guard !didAutoAnnounceInitialMyLocation else {
            return
        }

        guard isViewLoaded, view.window != nil else {
            return
        }

        guard presentedViewController == nil else {
            return
        }

        guard AppContext.shared.geolocationManager.location != nil else {
            return
        }

        didAutoAnnounceInitialMyLocation = true
        AppContext.process(ExplorationModeToggled(.locate, sender: self, logContext: "auto_launch"))
    }

    enum ExplorationPOIMode {
        case aroundMe
        case aheadOfMe

        var categoryTitle: String {
            switch self {
            case .aroundMe:
                return GDLocalizedString("exploration.poi.category.title.around")
            case .aheadOfMe:
                return GDLocalizedString("exploration.poi.category.title.ahead")
            }
        }

        var telemetryContext: String {
            switch self {
            case .aroundMe:
                return "around_me_poi_list"
            case .aheadOfMe:
                return "ahead_of_me_poi_list"
            }
        }
    }

    func showLocationDetailsForCurrentLocation() {
        guard let location = AppContext.shared.geolocationManager.location else {
            present(ErrorAlerts.buildLocationAlert(), animated: true)
            return
        }

        AppContext.shared.spatialDataContext.updateSpatialData(at: location) { [weak self] in
            let detail = LocationDetail(location: location, telemetryContext: "current_location")
            self?.performSegue(withIdentifier: "LocationDetailView", sender: detail)
        }
    }

    func presentExplorationPOICategoryScreen(for mode: ExplorationPOIMode) {
        guard let location = AppContext.shared.geolocationManager.location else {
            present(ErrorAlerts.buildLocationAlert(), animated: true)
            return
        }

        let heading: CLLocationDirection
        switch mode {
        case .aroundMe:
            heading = AppContext.shared.geolocationManager.collectionHeading.value ?? Heading.defaultValue
        case .aheadOfMe:
            heading = AppContext.shared.geolocationManager.heading(orderedBy: [.user, .device, .course]).value ?? Heading.defaultValue
        }

        let categoryVC = ExplorationPOICategoryViewController(mode: mode,
                                                              userLocation: location,
                                                              heading: heading)
        categoryVC.onSelectPOI = { [weak self] poi, telemetry in
            let detail = LocationDetail(entity: poi, telemetryContext: telemetry)
            self?.performSegue(withIdentifier: "LocationDetailView", sender: detail)
        }

        navigationController?.pushViewController(categoryVC, animated: true)
    }
}

private enum ExplorationPOISource {
    case osm
    case apple
    case overture

    var localizedName: String {
        switch self {
        case .osm:
            return GDLocalizedString("exploration.poi.source.osm")
        case .apple:
            return GDLocalizedString("exploration.poi.source.apple")
        case .overture:
            return GDLocalizedString("exploration.poi.source.overture")
        }
    }

    var priority: Int {
        switch self {
        case .osm:
            return 3
        case .overture:
            return 2
        case .apple:
            return 1
        }
    }
}

private enum ExplorationPOICategory: CaseIterable {
    case all
    case supermarket
    case convenience
    case pharmacy
    case cafe
    case restaurant
    case transit
    case parks

    var localizedName: String {
        switch self {
        case .all:
            return GDLocalizedString("exploration.poi.category.all")
        case .supermarket:
            return GDLocalizedString("exploration.poi.category.supermarket")
        case .convenience:
            return GDLocalizedString("exploration.poi.category.convenience")
        case .pharmacy:
            return GDLocalizedString("exploration.poi.category.pharmacy")
        case .cafe:
            return GDLocalizedString("exploration.poi.category.cafe")
        case .restaurant:
            return GDLocalizedString("exploration.poi.category.restaurant")
        case .transit:
            return GDLocalizedString("exploration.poi.category.transit")
        case .parks:
            return GDLocalizedString("exploration.poi.category.parks")
        }
    }

    var overtureCategory: String {
        switch self {
        case .all:
            return ""
        case .supermarket:
            return "supermarket"
        case .convenience:
            return "convenience"
        case .pharmacy:
            return "pharmacy"
        case .cafe:
            return "cafe"
        case .restaurant:
            return "restaurant"
        case .transit:
            return "transit"
        case .parks:
            return "park"
        }
    }

    var appleQueries: [String] {
        switch self {
        case .all:
            return [
                "point of interest",
                "supermarket",
                "convenience store",
                "pharmacy",
                "cafe",
                "restaurant",
                "transit stop",
                "park"
            ]
        case .supermarket:
            return ["supermarket", "grocery store"]
        case .convenience:
            return ["convenience store"]
        case .pharmacy:
            return ["pharmacy", "chemist"]
        case .cafe:
            return ["cafe", "coffee shop"]
        case .restaurant:
            return ["restaurant"]
        case .transit:
            return ["transit stop", "bus stop", "train station"]
        case .parks:
            return ["park"]
        }
    }
}

private struct ExplorationPOIItem {
    let poi: POI
    let source: ExplorationPOISource
    let distance: CLLocationDistance
}

private final class ExplorationPOICategoryViewController: UITableViewController {
    private let mode: HomeViewController.ExplorationPOIMode
    private let userLocation: CLLocation
    private let heading: CLLocationDirection

    var onSelectPOI: ((POI, String) -> Void)?

    init(mode: HomeViewController.ExplorationPOIMode, userLocation: CLLocation, heading: CLLocationDirection) {
        self.mode = mode
        self.userLocation = userLocation
        self.heading = heading
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = mode.categoryTitle
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "CategoryCell")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return ExplorationPOICategory.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CategoryCell", for: indexPath)
        let category = ExplorationPOICategory.allCases[indexPath.row]
        cell.textLabel?.text = category.localizedName
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let category = ExplorationPOICategory.allCases[indexPath.row]
        let listVC = ExplorationPOIListViewController(mode: mode,
                                                      category: category,
                                                      userLocation: userLocation,
                                                      heading: heading)
        listVC.onSelectPOI = onSelectPOI
        navigationController?.pushViewController(listVC, animated: true)
    }
}

private final class ExplorationPOIListViewController: UITableViewController {
    private let mode: HomeViewController.ExplorationPOIMode
    private let category: ExplorationPOICategory
    private let userLocation: CLLocation
    private let heading: CLLocationDirection
    private let coordinator = ExplorationPOIDataCoordinator()

    private var items: [ExplorationPOIItem] = []
    private var accessibilityActionIndices: [ObjectIdentifier: Int] = [:]
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    var onSelectPOI: ((POI, String) -> Void)?

    init(mode: HomeViewController.ExplorationPOIMode,
         category: ExplorationPOICategory,
         userLocation: CLLocation,
         heading: CLLocationDirection) {
        self.mode = mode
        self.category = category
        self.userLocation = userLocation
        self.heading = heading
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = category.localizedName
        tableView.tableFooterView = UIView()

        loadingIndicator.startAnimating()
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: loadingIndicator)

        coordinator.loadPOIs(mode: mode,
                             category: category,
                             userLocation: userLocation,
                             heading: heading) { [weak self] items in
            guard let self = self else {
                return
            }

            self.items = items
            self.loadingIndicator.stopAnimating()
            self.navigationItem.rightBarButtonItem = nil
            self.tableView.reloadData()
            self.postAccessibilityResultsAnnouncement()
        }
    }

    private func postAccessibilityResultsAnnouncement() {
        guard UIAccessibility.isVoiceOverRunning else {
            return
        }

        let announcement: String
        if let first = items.first {
            announcement = GDLocalizedString("search.results_found_first_result", String(items.count), displayName(for: first))
        } else {
            announcement = GDLocalizedString("search.no_results_found_with_hint")
        }

        UIAccessibility.post(notification: .announcement, argument: announcement)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return max(items.count, 1)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if items.isEmpty {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.selectionStyle = .none
            cell.textLabel?.text = GDLocalizedString("exploration.poi.list.empty")
            cell.textLabel?.textColor = Colors.Foreground.secondary
            return cell
        }

        let reuseIdentifier = "POICell"
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseIdentifier) ?? UITableViewCell(style: .subtitle, reuseIdentifier: reuseIdentifier)
        let item = items[indexPath.row]
        let poi = item.poi
        let distance = LanguageFormatter.string(from: item.distance, rounded: true)
        let bearing = poi.bearingToClosestLocation(from: userLocation)
        let relativeDirection = Direction(from: heading, to: bearing, type: .combined).localizedString

        cell.textLabel?.text = displayName(for: item)
        cell.detailTextLabel?.text = "\(item.source.localizedName) • \(distance) • \(relativeDirection)"
        cell.accessoryType = .disclosureIndicator

        let beaconAction = UIAccessibilityCustomAction(name: GDLocalizedString("location_action.beacon"), target: self, selector: #selector(onSetBeacon(_:)))
        let previewAction = UIAccessibilityCustomAction(name: GDLocalizedString("location_action.preview"), target: self, selector: #selector(onStreetPreview(_:)))

        accessibilityActionIndices[ObjectIdentifier(beaconAction)] = indexPath.row
        accessibilityActionIndices[ObjectIdentifier(previewAction)] = indexPath.row
        cell.accessibilityCustomActions = [beaconAction, previewAction]
        cell.tag = indexPath.row

        return cell
    }

    private func displayName(for item: ExplorationPOIItem) -> String {
        let baseName = item.poi.localizedName.isEmpty ? GDLocalizedString("location") : item.poi.localizedName

        let typeName: String?
        if category != .all {
            typeName = category.localizedName
        } else if let inferred = coordinator.inferCategory(for: item.poi) {
            typeName = inferred.localizedName
        } else {
            typeName = item.poi.localizedTypeName
        }

        guard let typeName, !typeName.isEmpty else {
            return baseName
        }

        if baseName.lowercasedWithAppLocale().contains(typeName.lowercasedWithAppLocale()) {
            return baseName
        }

        return "\(baseName), \(typeName)"
    }

    @objc private func onSetBeacon(_ action: UIAccessibilityCustomAction) -> Bool {
        guard let index = accessibilityActionIndices[ObjectIdentifier(action)],
              items.indices.contains(index) else {
            return false
        }

        let selected = items[index]
        onSelectPOI?(selected.poi, mode.telemetryContext)
        return true
    }

    @objc private func onStreetPreview(_ action: UIAccessibilityCustomAction) -> Bool {
        guard let index = accessibilityActionIndices[ObjectIdentifier(action)],
              items.indices.contains(index) else {
            return false
        }

        let selected = items[index]
        onSelectPOI?(selected.poi, mode.telemetryContext)
        return true
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard items.indices.contains(indexPath.row) else {
            return
        }

        let selected = items[indexPath.row]
        onSelectPOI?(selected.poi, mode.telemetryContext)
    }
}

private final class ExplorationPOIDataCoordinator {
    func loadPOIs(mode: HomeViewController.ExplorationPOIMode,
                  category: ExplorationPOICategory,
                  userLocation: CLLocation,
                  heading: CLLocationDirection,
                  completion: @escaping ([ExplorationPOIItem]) -> Void) {
        AppContext.shared.spatialDataContext.updateSpatialData(at: userLocation) { [self] in
            let osmItems = self.fetchOSMPOIs(category: category,
                                             mode: mode,
                                             userLocation: userLocation,
                                             heading: heading)

            let group = DispatchGroup()
            var appleItems: [ExplorationPOIItem] = []
            var overtureItems: [ExplorationPOIItem] = []

            group.enter()
            self.fetchApplePOIs(category: category, userLocation: userLocation) { results in
                appleItems = results
                group.leave()
            }

            group.enter()
            self.fetchOverturePOIs(category: category, userLocation: userLocation) { results in
                overtureItems = results
                group.leave()
            }

            group.notify(queue: .main) {
                let merged = self.mergeAndDeduplicate(osmItems + appleItems + overtureItems,
                                                      mode: mode,
                                                      userLocation: userLocation,
                                                      heading: heading)
                completion(merged)
            }
        }
    }

    private func fetchOSMPOIs(category: ExplorationPOICategory,
                              mode: HomeViewController.ExplorationPOIMode,
                              userLocation: CLLocation,
                              heading: CLLocationDirection) -> [ExplorationPOIItem] {
        guard let dataView = AppContext.shared.spatialDataContext.getDataView(for: userLocation,
                                                                               searchDistance: SpatialDataContext.cacheDistance) else {
            return []
        }

        let pois = dataView.pois.filter { matchesCategory($0, category: category) }
        let candidates = applyDirectionalFilterIfNeeded(pois,
                                                        mode: mode,
                                                        userLocation: userLocation,
                                                        heading: heading)

        return candidates.map {
            ExplorationPOIItem(poi: $0,
                               source: .osm,
                               distance: $0.distanceToClosestLocation(from: userLocation))
        }
    }

    private func fetchApplePOIs(category: ExplorationPOICategory,
                                userLocation: CLLocation,
                                completion: @escaping ([ExplorationPOIItem]) -> Void) {
        let queries = Array(Set(category.appleQueries.filter { !$0.isEmpty }))

        guard !queries.isEmpty else {
            completion([])
            return
        }

        let group = DispatchGroup()
        let mergeQueue = DispatchQueue(label: "com.company.appname.exploration.apple.merge")
        var mergedItems: [ExplorationPOIItem] = []

        for query in queries {
            group.enter()

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = MKCoordinateRegion(center: userLocation.coordinate,
                                                latitudinalMeters: 2000,
                                                longitudinalMeters: 2000)

            MKLocalSearch(request: request).start { response, _ in
                let items: [ExplorationPOIItem] = (response?.mapItems ?? []).compactMap { mapItem in
                    let coordinate = mapItem.placemark.coordinate
                    guard CLLocationCoordinate2DIsValid(coordinate) else {
                        return nil
                    }

                    let name = mapItem.name ?? mapItem.placemark.name ?? GDLocalizedString("location")
                    let address = mapItem.placemark.title
                    let location = GenericLocation(lat: coordinate.latitude,
                                                   lon: coordinate.longitude,
                                                   name: name,
                                                   address: address)
                    location.amenity = category.overtureCategory

                    let distance = location.distanceToClosestLocation(from: userLocation)
                    return ExplorationPOIItem(poi: location, source: .apple, distance: distance)
                }

                mergeQueue.async {
                    mergedItems.append(contentsOf: items)
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            completion(Array(mergedItems.sorted(by: { $0.distance < $1.distance }).prefix(120)))
        }
    }

    private func fetchOverturePOIs(category: ExplorationPOICategory,
                                   userLocation: CLLocation,
                                   completion: @escaping ([ExplorationPOIItem]) -> Void) {
        if category == .all {
            let categories = ExplorationPOICategory.allCases
                .filter { $0 != .all }
                .map { $0.overtureCategory }
                .filter { !$0.isEmpty }

            let group = DispatchGroup()
            let mergeQueue = DispatchQueue(label: "com.company.appname.exploration.overture.merge")
            var mergedItems: [ExplorationPOIItem] = []

            for categoryName in categories {
                group.enter()
                fetchOverturePOIs(categoryName: categoryName, userLocation: userLocation) { results in
                    mergeQueue.async {
                        mergedItems.append(contentsOf: results)
                        group.leave()
                    }
                }
            }

            group.notify(queue: .main) {
                completion(Array(mergedItems.sorted(by: { $0.distance < $1.distance }).prefix(120)))
            }

            return
        }

        fetchOverturePOIs(categoryName: category.overtureCategory, userLocation: userLocation, completion: completion)
    }

    private func fetchOverturePOIs(categoryName: String,
                                   userLocation: CLLocation,
                                   completion: @escaping ([ExplorationPOIItem]) -> Void) {
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
        queryItems.append(URLQueryItem(name: "radius", value: "2000"))
        queryItems.append(URLQueryItem(name: "limit", value: "100"))

        if !categoryName.isEmpty {
            queryItems.append(URLQueryItem(name: "category", value: categoryName))
        }

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

            let items = self.parseOvertureItems(from: data, userLocation: userLocation)
            DispatchQueue.main.async { completion(items) }
        }.resume()
    }

    private func parseOvertureItems(from data: Data, userLocation: CLLocation) -> [ExplorationPOIItem] {
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
            if let category = row["category"] as? String ?? props?["category"] as? String {
                location.amenity = category
            }

            let distance = location.distanceToClosestLocation(from: userLocation)
            return ExplorationPOIItem(poi: location, source: .overture, distance: distance)
        }
    }

    private func overturePOIBaseURL() -> String? {
        if let endpoint = UserDefaults.standard.string(forKey: "overture.poi.api.base_url"), !endpoint.isEmpty {
            return endpoint
        }

        if let endpoint = Bundle.main.object(forInfoDictionaryKey: "OverturePOIBaseURL") as? String,
           !endpoint.isEmpty {
            return endpoint
        }

        return nil
    }

    private func mergeAndDeduplicate(_ items: [ExplorationPOIItem],
                                     mode: HomeViewController.ExplorationPOIMode,
                                     userLocation: CLLocation,
                                     heading: CLLocationDirection) -> [ExplorationPOIItem] {
        var deduped: [ExplorationPOIItem] = []

        for item in items.sorted(by: { $0.distance < $1.distance }) {
            if let index = deduped.firstIndex(where: { self.looksLikeDuplicate($0.poi, item.poi, location: userLocation) }) {
                if item.source.priority > deduped[index].source.priority {
                    deduped[index] = item
                }
                continue
            }

            deduped.append(item)
        }

        let directional = applyDirectionalFilterIfNeeded(deduped.map { $0.poi },
                                                        mode: mode,
                                                        userLocation: userLocation,
                                                        heading: heading)

        let directionalSet = Set(directional.map { $0.key })
        return deduped
            .filter { directionalSet.contains($0.poi.key) }
            .sorted { $0.distance < $1.distance }
            .prefix(80)
            .map { $0 }
    }

    private func applyDirectionalFilterIfNeeded(_ pois: [POI],
                                                mode: HomeViewController.ExplorationPOIMode,
                                                userLocation: CLLocation,
                                                heading: CLLocationDirection) -> [POI] {
        guard mode == .aheadOfMe else {
            return pois
        }

        let quadrants = SpatialDataView.getQuadrants(heading: heading)
        let forward = SpatialDataView.getHeadingDirection(heading: heading)

        return pois.filter {
            let bearing = $0.bearingToClosestLocation(from: userLocation)
            return CompassDirection.from(bearing: bearing, quadrants: quadrants) == forward
        }
    }

    private func looksLikeDuplicate(_ lhs: POI, _ rhs: POI, location: CLLocation) -> Bool {
        let lhsName = normalizedName(lhs.localizedName)
        let rhsName = normalizedName(rhs.localizedName)

        if lhsName.isEmpty || rhsName.isEmpty {
            return false
        }

        let lhsLocation = lhs.closestLocation(from: location)
        let rhsLocation = rhs.closestLocation(from: location)
        let distance = lhsLocation.distance(from: rhsLocation)

        if lhsName == rhsName && distance < 60 {
            return true
        }

        if (lhsName.contains(rhsName) || rhsName.contains(lhsName)) && distance < 30 {
            return true
        }

        return false
    }

    private func normalizedName(_ name: String) -> String {
        let lowered = name.lowercasedWithAppLocale()
        let filtered = lowered.filter { $0.isLetter || $0.isNumber }
        return String(filtered)
    }

    private func matchesCategory(_ poi: POI, category: ExplorationPOICategory) -> Bool {
        guard category != .all else {
            return true
        }

        if category == .transit, let typeable = poi as? Typeable, typeable.isOfType(.transitStop) {
            return true
        }

        let localizedName = poi.localizedName.lowercasedWithAppLocale()

        if let osm = poi as? GDASpatialDataResultEntity {
            let amenity = osm.amenity.lowercasedWithAppLocale()
            let tag = osm.nameTag.lowercasedWithAppLocale()

            switch category {
            case .all:
                return true
            case .supermarket:
                return amenity.contains("supermarket") || tag.contains("supermarket")
            case .convenience:
                return amenity.contains("convenience") || tag.contains("convenience")
            case .pharmacy:
                return amenity.contains("pharmacy") || amenity.contains("chemist") || tag.contains("pharmacy")
            case .cafe:
                return amenity == "cafe" || tag.contains("cafe")
            case .restaurant:
                return amenity == "restaurant" || tag.contains("restaurant")
            case .transit:
                return superCategoryIsMobility(poi)
            case .parks:
                return amenity == "park" || tag.contains("park")
            }
        }

        if let generic = poi as? GenericLocation {
            let amenity = (generic.amenity ?? "").lowercasedWithAppLocale()

            switch category {
            case .all:
                return true
            case .supermarket:
                return amenity.contains("supermarket") || localizedName.contains("supermarket")
            case .convenience:
                return amenity.contains("convenience") || localizedName.contains("convenience")
            case .pharmacy:
                return amenity.contains("pharmacy") || localizedName.contains("pharmacy")
            case .cafe:
                return amenity.contains("cafe") || localizedName.contains("coffee")
            case .restaurant:
                return amenity.contains("restaurant") || localizedName.contains("restaurant")
            case .transit:
                return amenity.contains("transit") || localizedName.contains("station") || localizedName.contains("stop")
            case .parks:
                return amenity.contains("park") || localizedName.contains("park")
            }
        }

        switch category {
        case .all:
            return true
        case .supermarket:
            return localizedName.contains("supermarket")
        case .convenience:
            return localizedName.contains("convenience")
        case .pharmacy:
            return localizedName.contains("pharmacy")
        case .cafe:
            return localizedName.contains("cafe")
        case .restaurant:
            return localizedName.contains("restaurant")
        case .transit:
            return superCategoryIsMobility(poi)
        case .parks:
            return localizedName.contains("park")
        }
    }

    private func superCategoryIsMobility(_ poi: POI) -> Bool {
        return SuperCategory(rawValue: poi.superCategory) == .mobility
    }

    func inferCategory(for poi: POI) -> ExplorationPOICategory? {
        for category in ExplorationPOICategory.allCases where category != .all {
            if matchesCategory(poi, category: category) {
                return category
            }
        }

        return nil
    }
}

// MARK: Update View Methods

extension HomeViewController {
    
    fileprivate func updateExternalHardwareGeolocationIndicatorView(isExternal: Bool) {
        // Show the external hardware indicator if needed
        if isExternal {
            // Check if the indicator is already showing
            if var rightBarButtonItems = navigationItem.rightBarButtonItems {
                    if rightBarButtonItems.contains(externalGPSBarButtonItem) {
                        return
                    } else {
                        // We add the indicator to the current bar button items
                        rightBarButtonItems.append(externalGPSBarButtonItem)
                        DispatchQueue.main.async { [weak self] in
                            self?.navigationItem.rightBarButtonItems = rightBarButtonItems
                        }
                }
            } else {
                // No other current bar button items. show only the indicator.
                DispatchQueue.main.async { [weak self] in
                    self?.navigationItem.rightBarButtonItem = self?.externalGPSBarButtonItem
                }
            }
        } else {
            // Hide the external hardware indicator if needed
            self.navigationItem.remove(barButtonItem: externalGPSBarButtonItem)
        }
        
        var barButtonItems: [UIBarButtonItem] = []
        
        if isExternal {
            barButtonItems.append(externalGPSBarButtonItem)
        }
        
        navigationItem.rightBarButtonItems = barButtonItems
    }
    
}

// MARK: - DismissableViewControllerDelegate

extension HomeViewController: DismissableViewControllerDelegate {
    
    func onDismissed(_ viewController: UIViewController) {
        // If there is an active route guidance behavior, then unmute the audio beacon
        if AppContext.shared.eventProcessor.activeBehavior is RouteGuidance,
           !AppContext.shared.spatialDataContext.destinationManager.isAudioEnabled {
            AppContext.shared.spatialDataContext.destinationManager.toggleDestinationAudio()
        }
    }
    
}

// MARK: - SearchResultsTableViewControllerDelegate

extension HomeViewController: SearchResultsTableViewControllerDelegate {
    
    func didSelectSearchResult(_ searchResult: POI) {
        let detail = LocationDetail(entity: searchResult, telemetryContext: "search_result")
        performSegue(withIdentifier: "LocationDetailView", sender: detail)
        
        searchController?.isActive = false
    }
    
    var isCachingRequired: Bool {
        // After a result is selected, we will navigate to the detail view for that location
        // The detail view will disable any actions that require caching
        return false
    }
    
    var isAccessibilityActionsEnabled: Bool {
        return true
    }
    
    var telemetryContext: String {
        return "home_screen"
    }
}

// MARK: - LocationActionDelegate

extension HomeViewController: LocationActionDelegate {
    
    func didSelectLocationAction(_ action: LocationAction, detail: LocationDetail) {
        DispatchQueue.main.async { [weak self] in
            guard let `self` = self else {
                return
            }
            
            guard action.isEnabled else {
                // Do nothing if the action is disabled
                return
            }
            
            self.searchController?.isActive = false
            
            do {
                switch action {
                case .save, .edit:
                    // Edit the marker at the given location
                    // Segue to the edit marker view
                    let config = EditMarkerConfig(detail: detail,
                                                  route: nil,
                                                  context: self.telemetryContext,
                                                  addOrUpdateAction: .popToRootViewController,
                                                  deleteAction: .popToRootViewController,
                                                  leftBarButtonItemIsHidden: false)
                    
                    if let vc = MarkerEditViewRepresentable(config: config).makeViewController() {
                        self.navigationController?.pushViewController(vc, animated: true)
                    }
                case .beacon:
                    // Set a beacon on the given location
                    // and segue to the home view
                    try LocationActionHandler.beacon(locationDetail: detail)
                    self.navigationController?.popToRootViewController(animated: true)
                case .preview:
                    self.performSegue(withIdentifier: "PreviewView", sender: detail)
                case .share:
                    // Create a URL to share a marker at the given location
                    let url = try LocationActionHandler.share(locationDetail: detail)
                    // Present the activity view controller
                    let alert = ShareMarkerAlert.shareMarker(url, markerName: detail.displayName)
                    
                    if FirstUseExperience.didComplete(.share) {
                        self.present(alert, animated: true, completion: nil)
                    } else {
                        let firstUseAlert = ShareMarkerAlert.firstUseExperience(dismissHandler: { [weak self] _ in
                            guard let `self` = self else {
                                return
                            }
                            
                            FirstUseExperience.setDidComplete(for: .share)
                            
                            self.present(alert, animated: true, completion: nil)
                        })
                        
                        self.present(firstUseAlert, animated: true, completion: nil)
                    }
                case .openInAppleMaps:
                    try LocationActionHandler.openInAppleMaps(locationDetail: detail)
                case .openInGoogleMaps:
                    try LocationActionHandler.openInGoogleMaps(locationDetail: detail)
                }
            } catch let error as LocationActionError {
                let alert = LocationActionAlert.alert(for: error)
                self.present(alert, animated: true, completion: nil)
            } catch {
                let alert = LocationActionAlert.alert(for: error)
                self.present(alert, animated: true, completion: nil)
            }
        }
    }
    
}

// MARK: - UISearchControllerDelegate

extension HomeViewController: UISearchControllerDelegate {
    
    func willPresentSearchController(_ searchController: UISearchController) {
        // Default navigation bar
        navigationController?.navigationBar.configureAppearance(for: .default)
        
        NSUserActivity(userAction: .search).becomeCurrent()
    }
    
    func willDismissSearchController(_ searchController: UISearchController) {
        // Transparent navigation bar
        navigationController?.navigationBar.configureAppearance(for: .transparentLightTitle)
    }
    
}

// MARK: - LargeBannerContainerView

extension HomeViewController: LargeBannerContainerView {
    
    func setLargeBannerHeight(_ height: CGFloat) {
        largeBannerContainerHeightConstraint.constant = height
    }
    
}

// MARK: - SmallBannerContainerView

extension HomeViewController: SmallBannerContainerView {
    
    func setSmallBannerHeight(_ height: CGFloat) {
        smallBannerContainerHeightConstraint.constant = height
    }
    
}

private extension UIAlertController {
    
    static func activityDidUpdate() -> UIAlertController {
        let alert = UIAlertController(title: GDLocalizedString("route.update.success.title"), message: GDLocalizedString("route.update.success.message"), preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: GDLocalizedString("general.alert.dismiss"), style: .default))
        return alert
    }
    
    static func activityDidFailToUpdate() -> UIAlertController {
        let alert = UIAlertController(title: GDLocalizedString("route.update.fail.title"), message: GDLocalizedString("route.update.fail.message"), preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: GDLocalizedString("general.alert.dismiss"), style: .default))
        return alert
    }
    
    static func activityUpdateUnavailable() -> UIAlertController {
        let alert = UIAlertController(title: GDLocalizedString("route.update.unavailable.title"), message: GDLocalizedString("route.update.unavailable.message"), preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: GDLocalizedString("general.alert.dismiss"), style: .default))
        return alert
    }
    
}

private final class LiveViewNavigationViewController: UIViewController, ARSessionDelegate {
    private let statusLabel = UILabel()
    private let distanceLabel = UILabel()
    private let stepLabel = UILabel()
    private let arrowView = UIImageView(image: UIImage(systemName: "arrow.up.circle.fill"))

    private let speech = AVSpeechSynthesizer()
    private var lastSpokenStep: String?
    private var lastSpokenDate = Date.distantPast
    private var lastSpokenClockPosition: Int?
    private var lastSpokenDistanceBucket: Int?
    private var lastDirectionSpokenDate = Date.distantPast

    private var headingObserver: Heading?
    private var locationObserver: NSObjectProtocol?
    private var stepObserver: NSObjectProtocol?
    private let arSession = ARSession()
    private var arReferenceYaw: CLLocationDirection?
    private var arReferenceHeading: CLLocationDirection?
    private var cameraAssistedHeading: CLLocationDirection?
    private var isUsingGeospatialTracking = false
#if canImport(ARCore)
    private var arCoreSession: GARSession?
    private var isUsingARCoreGeospatial = false
    private var arCoreHorizontalAccuracy: CLLocationAccuracy?
    private var arCoreVerticalAccuracy: CLLocationAccuracy?
    private var arCoreYawAccuracy: CLLocationDirectionAccuracy?
#endif

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()

        title = GDLocalizedString("liveview.screen.title")
        view.backgroundColor = .black

        // Live View is presented modally to avoid nav-bar back button rendering crashes on some iOS versions.
        if presentingViewController != nil || navigationController?.presentingViewController != nil {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close,
                                                               target: self,
                                                               action: #selector(onCloseTouchUpInside))
        }

        configureCameraPreview()
        configureOverlay()
        subscribeUpdates()
        refreshOverlay()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startCameraSessionIfNeeded()
        startCameraAssistedTrackingIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
        arSession.pause()
    }

    deinit {
        if let observer = locationObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        if let observer = stepObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func configureCameraPreview() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            setupCameraSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupCameraSession()
                        self?.startCameraSessionIfNeeded()
                    } else {
                        self?.statusLabel.text = GDLocalizedString("general.error.open_camera")
                    }
                }
            }
        default:
            statusLabel.text = GDLocalizedString("general.error.open_camera")
        }
    }

    private func setupCameraSession() {
        let session = AVCaptureSession()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            statusLabel.text = GDLocalizedString("general.error.open_camera")
            return
        }

        session.addInput(input)

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)

        previewLayer = layer
        captureSession = session
    }

    private func startCameraSessionIfNeeded() {
        guard let session = captureSession, !session.isRunning else {
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    private func startCameraAssistedTrackingIfNeeded() {
        arReferenceYaw = nil
        arReferenceHeading = headingObserver?.value ?? Heading.defaultValue
        cameraAssistedHeading = nil

#if canImport(ARCore)
        if configureARCoreGeospatialSession() {
            guard ARWorldTrackingConfiguration.isSupported else {
                return
            }

            let configuration = ARWorldTrackingConfiguration()
            configuration.worldAlignment = .gravity
            arSession.delegate = self
            arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            return
        }
#endif

        arSession.delegate = self

        if #available(iOS 14.0, *), ARGeoTrackingConfiguration.isSupported {
            let geospatialConfiguration = ARGeoTrackingConfiguration()
            isUsingGeospatialTracking = true
            arSession.run(geospatialConfiguration, options: [.resetTracking, .removeExistingAnchors])
            return
        }

        guard ARWorldTrackingConfiguration.isSupported else {
            return
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        isUsingGeospatialTracking = false
        arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

#if canImport(ARCore)
    private func configureARCoreGeospatialSession() -> Bool {
        let apiKey = SettingsContext.shared.googleARAPIKey
        guard !apiKey.isEmpty else {
            isUsingARCoreGeospatial = false
            statusLabel.text = GDLocalizedString("liveview.status.geospatial_missing_key")
            return false
        }

        do {
            let session = try GARSession(apiKey: apiKey, bundleIdentifier: Bundle.main.bundleIdentifier)
            guard session.isGeospatialModeSupported(.enabled) else {
                isUsingARCoreGeospatial = false
                statusLabel.text = GDLocalizedString("liveview.status.geospatial_unavailable")
                return false
            }

            let configuration = GARSessionConfiguration()
            configuration.geospatialMode = .enabled
            var configurationError: NSError?
            session.setConfiguration(configuration, error: &configurationError)
            if let configurationError {
                throw configurationError
            }

            arCoreSession = session
            isUsingARCoreGeospatial = true
            statusLabel.text = GDLocalizedString("liveview.status.geospatial_localizing")
            return true
        } catch {
            isUsingARCoreGeospatial = false
            statusLabel.text = GDLocalizedString("liveview.status.geospatial_unavailable")
            GDLogAppInfo("LiveView: failed to configure ARCore geospatial session - \(error.localizedDescription)")
            return false
        }
    }

    private func updateARCoreGeospatialPose(from frame: ARFrame) -> Bool {
        guard isUsingARCoreGeospatial,
              let session = arCoreSession else {
            return false
        }

        do {
            let garFrame = try session.update(frame)

            guard let earth = garFrame.earth,
                  earth.trackingState == .tracking,
                  let geospatial = earth.cameraGeospatialTransform else {
                statusLabel.text = GDLocalizedString("liveview.status.geospatial_localizing")
                return false
            }

            arCoreHorizontalAccuracy = geospatial.horizontalAccuracy
            arCoreVerticalAccuracy = geospatial.verticalAccuracy
            arCoreYawAccuracy = geospatial.orientationYawAccuracy

            // Use ARCore heading only after yaw estimate converges to a stable range.
            if geospatial.orientationYawAccuracy > 0.0 && geospatial.orientationYawAccuracy <= 25.0 {
                cameraAssistedHeading = normalizeDegrees(geospatial.heading)
                return true
            }

            statusLabel.text = GDLocalizedString("liveview.status.geospatial_localizing")
            return false
        } catch {
            statusLabel.text = GDLocalizedString("liveview.status.geospatial_unavailable")
            GDLogAppInfo("LiveView: ARCore frame update failed - \(error.localizedDescription)")
            return false
        }
    }
#endif

    private func configureOverlay() {
        let stack = UIStackView(arrangedSubviews: [statusLabel, distanceLabel, stepLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 10
        stack.alignment = .fill

        [statusLabel, distanceLabel, stepLabel].forEach { label in
            label.numberOfLines = 0
            label.textAlignment = .center
            label.textColor = .white
            label.backgroundColor = UIColor.black.withAlphaComponent(0.45)
            label.layer.cornerRadius = 8
            label.layer.masksToBounds = true
            label.font = UIFont.preferredFont(forTextStyle: .body)
            label.adjustsFontForContentSizeCategory = true
        }

        arrowView.translatesAutoresizingMaskIntoConstraints = false
        arrowView.contentMode = .scaleAspectFit
        arrowView.tintColor = .systemGreen
        arrowView.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        arrowView.layer.cornerRadius = 52
        arrowView.layer.masksToBounds = true

        view.addSubview(arrowView)
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            arrowView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            arrowView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            arrowView.widthAnchor.constraint(equalToConstant: 104),
            arrowView.heightAnchor.constraint(equalToConstant: 104),

            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    private func subscribeUpdates() {
        headingObserver = AppContext.shared.geolocationManager.heading(orderedBy: [.user, .device, .course])
        headingObserver?.onHeadingDidUpdate { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshOverlay()
            }
        }

        locationObserver = NotificationCenter.default.addObserver(forName: .locationUpdated,
                                                                  object: nil,
                                                                  queue: .main) { [weak self] _ in
            self?.refreshOverlay()
        }

        stepObserver = NotificationCenter.default.addObserver(forName: .navigationStepDidUpdate,
                                                              object: nil,
                                                              queue: .main) { [weak self] notification in
            guard let self = self else { return }
            let step = notification.userInfo?[NavigationGuidanceManager.Keys.stepText] as? String
            self.stepLabel.text = step
            self.speakIfNeeded(step)
        }
    }

    private func refreshOverlay() {
        guard let destination = AppContext.shared.spatialDataContext.destinationManager.destination else {
            statusLabel.text = GDLocalizedString("liveview.status.no_destination")
            distanceLabel.text = nil
            arrowView.transform = .identity
            return
        }

        guard let userLocation = AppContext.shared.geolocationManager.location else {
            statusLabel.text = GDLocalizedString("liveview.status.no_location")
            distanceLabel.text = nil
            arrowView.transform = .identity
            return
        }

        let destinationLocation = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        let distance = userLocation.distance(from: destinationLocation)
        statusLabel.text = destination.name
        var distanceText = GDLocalizedString("liveview.status.distance", LanguageFormatter.string(from: distance))

    #if canImport(ARCore)
        if let horizontal = arCoreHorizontalAccuracy,
           let vertical = arCoreVerticalAccuracy,
           let yaw = arCoreYawAccuracy,
           isUsingARCoreGeospatial {
            distanceText += "\n" + GDLocalizedString("liveview.status.geospatial_accuracy",
                                   LanguageFormatter.string(from: horizontal, rounded: true),
                                   LanguageFormatter.string(from: vertical, rounded: true),
                                   String(format: "%.0f", yaw))
        }
    #endif

        distanceLabel.text = distanceText

        let userHeading = cameraAssistedHeading ?? headingObserver?.value ?? Heading.defaultValue
        let bearing = userLocation.bearing(to: destinationLocation)
        let relative = (bearing - userHeading + 360).truncatingRemainder(dividingBy: 360)
        let radians = CGFloat(relative * .pi / 180.0)
        arrowView.transform = CGAffineTransform(rotationAngle: radians)

        speakDirectionIfNeeded(relativeBearing: relative, distance: distance)
    }

    private func speakIfNeeded(_ step: String?) {
        guard let step = step, !step.isEmpty else {
            return
        }

        guard step != lastSpokenStep || Date().timeIntervalSince(lastSpokenDate) > 8 else {
            return
        }

        lastSpokenStep = step
        lastSpokenDate = Date()

        let utterance = AVSpeechUtterance(string: GDLocalizedString("liveview.voice.step", step))
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speech.speak(utterance)
    }

    private func speakDirectionIfNeeded(relativeBearing: CLLocationDirection, distance: CLLocationDistance) {
        let clockPosition = clockFacePosition(from: relativeBearing)
        let distanceBucket = Int(distance / 8.0)
        let now = Date()

        let hasMeaningfulDirectionChange = (clockPosition != lastSpokenClockPosition)
            || (lastSpokenDistanceBucket == nil)
            || abs(distanceBucket - (lastSpokenDistanceBucket ?? distanceBucket)) >= 2

        guard hasMeaningfulDirectionChange,
              now.timeIntervalSince(lastDirectionSpokenDate) > 6 else {
            return
        }

        lastSpokenClockPosition = clockPosition
        lastSpokenDistanceBucket = distanceBucket
        lastDirectionSpokenDate = now

        let distanceText = LanguageFormatter.string(from: distance, rounded: true)
        let voiceText = GDLocalizedString("liveview.voice.direction", String(clockPosition), distanceText)
        let utterance = AVSpeechUtterance(string: voiceText)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speech.speak(utterance)
    }

    private func clockFacePosition(from relativeBearing: CLLocationDirection) -> Int {
        // Map 0...360 degrees to 12 clock-face sectors.
        let normalized = (relativeBearing + 360).truncatingRemainder(dividingBy: 360)
        let index = Int((normalized + 15).truncatingRemainder(dividingBy: 360) / 30)
        let position = (index == 0) ? 12 : index
        return position
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
#if canImport(ARCore)
        if updateARCoreGeospatialPose(from: frame) {
            return
        }
#endif

        // Use camera yaw drift to smooth relative heading changes between compass updates.
        let yaw = normalizeDegrees(Double(frame.camera.eulerAngles.y) * 180.0 / .pi)

        if arReferenceYaw == nil {
            arReferenceYaw = yaw
            return
        }

        guard let referenceYaw = arReferenceYaw,
              let referenceHeading = arReferenceHeading else {
            return
        }

        let delta = normalizeSignedDegrees(yaw - referenceYaw)
        cameraAssistedHeading = normalizeDegrees(referenceHeading + delta)
    }

    @available(iOS 14.0, *)
    func session(_ session: ARSession, didChange geoTrackingStatus: ARGeoTrackingStatus) {
        guard isUsingGeospatialTracking else {
            return
        }

        switch geoTrackingStatus.state {
        case .localized:
            statusLabel.text = GDLocalizedString("liveview.status.geospatial_ready")
        case .localizing:
            statusLabel.text = GDLocalizedString("liveview.status.geospatial_localizing")
        case .notAvailable:
            statusLabel.text = GDLocalizedString("liveview.status.geospatial_unavailable")
        @unknown default:
            statusLabel.text = GDLocalizedString("liveview.status.geospatial_localizing")
        }
    }

    private func normalizeDegrees(_ value: CLLocationDirection) -> CLLocationDirection {
        return (value + 360).truncatingRemainder(dividingBy: 360)
    }

    private func normalizeSignedDegrees(_ value: CLLocationDirection) -> CLLocationDirection {
        var normalized = normalizeDegrees(value)
        if normalized > 180 {
            normalized -= 360
        }

        return normalized
    }

    @objc private func onCloseTouchUpInside() {
        dismiss(animated: true)
    }
}
