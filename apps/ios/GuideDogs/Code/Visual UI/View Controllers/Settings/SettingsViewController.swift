//
//  SettingsViewController.swift
//  Soundscape
//
//  Copyright (c) Microsoft Corporation.
//  Licensed under the MIT License.
//

import UIKit

import AppCenterAnalytics

class SettingsViewController: BaseTableViewController {
    private enum GeneralRow {
        static let checkAudio = 5
        static let gpsInformation = 6
    }
    
    private enum Section: Int, CaseIterable {
        case general = 0
        case audio = 1
        case navigation = 2
        case callouts = 3
        case streetPreview = 4
        case troubleshooting = 5
        case telemetry = 6
    }
    
    private static let cellIdentifiers: [IndexPath: String] = [
        IndexPath(row: 0, section: Section.general.rawValue): "languageAndRegion",
        IndexPath(row: 1, section: Section.general.rawValue): "voice",
        IndexPath(row: 2, section: Section.general.rawValue): "beaconSettings",
        IndexPath(row: 3, section: Section.general.rawValue): "volumeSettings",
        IndexPath(row: 4, section: Section.general.rawValue): "manageDevices",
        IndexPath(row: 7, section: Section.general.rawValue): "siriShortcuts",

        IndexPath(row: 0, section: Section.troubleshooting.rawValue): "troubleshooting",
        IndexPath(row: 0, section: Section.telemetry.rawValue): "telemetry"
    ]
    
    // MARK: Properties

    @IBOutlet weak var largeBannerContainerView: UIView!

    // MARK: View Life Cycle

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        GDLogActionInfo("Opened 'Settings'")

        GDATelemetry.trackScreenView("settings")

        self.title = GDLocalizedString("settings.screen_title")
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sectionType = Section(rawValue: section) else { return 0 }
        
        switch sectionType {
        case .general: return 8
        case .audio: return 1
        case .navigation: return 1
        case .callouts: return 1
        case .streetPreview: return 1
        case .troubleshooting: return 1
        case .telemetry: return 1
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let identifier = SettingsViewController.cellIdentifiers[indexPath]
        
        guard let sectionType = Section(rawValue: indexPath.section) else {
            return tableView.dequeueReusableCell(withIdentifier: identifier ?? "default", for: indexPath)
        }

        switch sectionType {
        case .general where indexPath.row == GeneralRow.checkAudio:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.backgroundColor = Colors.Background.primary
            cell.textLabel?.text = GDLocalizedString("troubleshooting.check_audio")
            cell.textLabel?.textColor = Colors.Foreground.primary
            cell.textLabel?.adjustsFontForContentSizeCategory = true
            cell.accessoryType = .none
            cell.selectionStyle = .default
            cell.accessibilityTraits = [.button]
            return cell

        case .general where indexPath.row == GeneralRow.gpsInformation:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.backgroundColor = Colors.Background.primary
            cell.textLabel?.text = GDLocalizedString("settings.gps_information.menu")
            cell.textLabel?.textColor = Colors.Foreground.primary
            cell.textLabel?.numberOfLines = 0
            cell.textLabel?.adjustsFontForContentSizeCategory = true
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
            return cell

        case .audio:
            return makeEntryCell(title: GDLocalizedString("settings.audio.media_controls"))

        case .navigation:
            return makeEntryCell(title: GDLocalizedString("settings.navigation.menu"))

        case .callouts:
            return makeEntryCell(title: GDLocalizedString("menu.manage_callouts"))

        case .streetPreview:
            return makeEntryCell(title: GDLocalizedString("preview.title"))

        case .telemetry:
            let cell = tableView.dequeueReusableCell(withIdentifier: identifier ?? "default", for: indexPath) as! TelemetrySettingsTableViewCell
            cell.parent = self
            
            return cell
            
        default:
            return tableView.dequeueReusableCell(withIdentifier: identifier ?? "default", for: indexPath)
        }
        
    }
    
    // MARK: UITableViewDataSource

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sectionType = Section(rawValue: section) else { return nil }

        switch sectionType {
        case .general: return GDLocalizedString("settings.section.general")
        case .audio, .navigation, .callouts, .streetPreview: return nil
        case .troubleshooting: return GDLocalizedString("settings.section.troubleshooting")
        case .telemetry: return GDLocalizedString("settings.section.telemetry")
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let sectionType = Section(rawValue: section) else { return nil }

        switch sectionType {
        case .general, .audio, .callouts, .streetPreview: return nil
        case .telemetry: return GDLocalizedString("settings.section.telemetry.footer")
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer {
            tableView.deselectRow(at: indexPath, animated: true)
        }

        guard let section = Section(rawValue: indexPath.section) else {
            return
        }

        switch section {
        case .general:
            switch indexPath.row {
            case GeneralRow.checkAudio:
                AppContext.process(CheckAudioEvent())
            case GeneralRow.gpsInformation:
                let vc = GPSInformationSettingsViewController(style: .insetGrouped)
                navigationController?.pushViewController(vc, animated: true)
            default:
                return
            }
        case .audio:
            navigationController?.pushViewController(MediaControlsSettingsViewController(style: .insetGrouped), animated: true)
        case .navigation:
            navigationController?.pushViewController(NavigationSettingsViewController(style: .insetGrouped), animated: true)
        case .callouts:
            navigationController?.pushViewController(ManageCalloutsSettingsViewController(style: .insetGrouped), animated: true)
        case .streetPreview:
            navigationController?.pushViewController(StreetPreviewSettingsViewController(style: .insetGrouped), animated: true)
        case .troubleshooting, .telemetry:
            return
        }
    }

    private func makeEntryCell(title: String) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = Colors.Background.primary
        cell.textLabel?.text = title
        cell.textLabel?.textColor = Colors.Foreground.primary
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
        return cell
    }
}

extension SettingsViewController: LargeBannerContainerView {
    
    func setLargeBannerHeight(_ height: CGFloat) {
        largeBannerContainerView.setHeight(height)
        tableView.reloadData()
    }
    
}

private final class NavigationSettingsViewController: UITableViewController {
    private enum Row: Int, CaseIterable {
        case provider
        case googleMapsPlatformAPIKey
        case googleMapsPlatformSecret
        case googleARAPIKey
        case googleARSecret

        var title: String {
            switch self {
            case .provider:
                return GDLocalizedString("settings.navigation.provider")
            case .googleMapsPlatformAPIKey:
                return GDLocalizedString("settings.navigation.google.maps_api_key")
            case .googleMapsPlatformSecret:
                return GDLocalizedString("settings.navigation.google.maps_api_secret")
            case .googleARAPIKey:
                return GDLocalizedString("settings.navigation.google.ar_api_key")
            case .googleARSecret:
                return GDLocalizedString("settings.navigation.google.ar_api_secret")
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = GDLocalizedString("settings.navigation.title")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "NavigationSettingsCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "NavigationSettingsValueCell")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Row.allCases.count
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return GDLocalizedString("settings.navigation.footer")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let row = Row(rawValue: indexPath.row) else {
            return tableView.dequeueReusableCell(withIdentifier: "NavigationSettingsCell", for: indexPath)
        }

        let cell = UITableViewCell(style: .value1, reuseIdentifier: "NavigationSettingsValueCell")
        cell.backgroundColor = Colors.Background.primary
        cell.textLabel?.text = row.title
        cell.textLabel?.textColor = Colors.Foreground.primary
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.detailTextLabel?.textColor = Colors.Foreground.secondary
        cell.detailTextLabel?.adjustsFontForContentSizeCategory = true
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default

        switch row {
        case .provider:
            cell.detailTextLabel?.text = SettingsContext.shared.navigationRouteProvider.localizedName
        case .googleMapsPlatformAPIKey:
            cell.detailTextLabel?.text = summarize(SettingsContext.shared.googleMapsPlatformAPIKey)
        case .googleMapsPlatformSecret:
            cell.detailTextLabel?.text = summarizeSecret(SettingsContext.shared.googleMapsPlatformSecret)
        case .googleARAPIKey:
            cell.detailTextLabel?.text = summarize(SettingsContext.shared.googleARAPIKey)
        case .googleARSecret:
            cell.detailTextLabel?.text = summarizeSecret(SettingsContext.shared.googleARSecret)
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer {
            tableView.deselectRow(at: indexPath, animated: true)
        }

        guard let row = Row(rawValue: indexPath.row) else {
            return
        }

        switch row {
        case .provider:
            presentProviderSelector()
        case .googleMapsPlatformAPIKey:
            presentTextInput(for: row,
                             initialValue: SettingsContext.shared.googleMapsPlatformAPIKey,
                             isSecret: false) { value in
                SettingsContext.shared.googleMapsPlatformAPIKey = value
            }
        case .googleMapsPlatformSecret:
            presentTextInput(for: row,
                             initialValue: SettingsContext.shared.googleMapsPlatformSecret,
                             isSecret: true) { value in
                SettingsContext.shared.googleMapsPlatformSecret = value
            }
        case .googleARAPIKey:
            presentTextInput(for: row,
                             initialValue: SettingsContext.shared.googleARAPIKey,
                             isSecret: false) { value in
                SettingsContext.shared.googleARAPIKey = value
            }
        case .googleARSecret:
            presentTextInput(for: row,
                             initialValue: SettingsContext.shared.googleARSecret,
                             isSecret: true) { value in
                SettingsContext.shared.googleARSecret = value
            }
        }
    }

    private func presentProviderSelector() {
        let alert = UIAlertController(title: GDLocalizedString("settings.navigation.provider"),
                                      message: nil,
                                      preferredStyle: .actionSheet)

        for provider in [SettingsContext.NavigationRouteProvider.appleMaps, .googleRoutesAPI] {
            let selected = provider == SettingsContext.shared.navigationRouteProvider
            let title = selected ? "\u{2713} \(provider.localizedName)" : provider.localizedName

            alert.addAction(UIAlertAction(title: title, style: .default, handler: { [weak self] _ in
                SettingsContext.shared.navigationRouteProvider = provider
                GDATelemetry.track("settings.navigation.provider", with: ["provider": provider.rawValue])
                self?.tableView.reloadData()
            }))
        }

        alert.addAction(UIAlertAction(title: GDLocalizedString("general.alert.cancel"), style: .cancel))

        if let popover = alert.popoverPresentationController,
           let cell = tableView.cellForRow(at: IndexPath(row: Row.provider.rawValue, section: 0)) {
            popover.sourceView = cell
            popover.sourceRect = cell.bounds
        }

        present(alert, animated: true)
    }

    private func presentTextInput(for row: Row,
                                  initialValue: String,
                                  isSecret: Bool,
                                  save: @escaping (String) -> Void) {
        let alert = UIAlertController(title: row.title,
                                      message: GDLocalizedString("settings.navigation.input.message"),
                                      preferredStyle: .alert)

        alert.addTextField { textField in
            textField.text = initialValue
            textField.clearButtonMode = .whileEditing
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
            textField.spellCheckingType = .no
            textField.isSecureTextEntry = isSecret
            textField.placeholder = GDLocalizedString("settings.navigation.input.placeholder")
        }

        alert.addAction(UIAlertAction(title: GDLocalizedString("general.alert.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: GDLocalizedString("general.alert.done"), style: .default, handler: { [weak self] _ in
            let value = alert.textFields?.first?.text ?? ""
            save(value)
            GDATelemetry.track("settings.navigation.value_updated", with: ["field": String(describing: row)])
            self?.tableView.reloadData()
        }))

        present(alert, animated: true)
    }

    private func summarize(_ value: String) -> String {
        guard !value.isEmpty else {
            return GDLocalizedString("settings.navigation.not_set")
        }

        if value.count <= 8 {
            return value
        }

        let start = value.prefix(4)
        let end = value.suffix(4)
        return "\(start)…\(end)"
    }

    private func summarizeSecret(_ value: String) -> String {
        guard !value.isEmpty else {
            return GDLocalizedString("settings.navigation.not_set")
        }

        return String(repeating: "•", count: min(value.count, 12))
    }
}

private final class GPSInformationSettingsViewController: UITableViewController {
    private enum Row: Int, CaseIterable {
        case announceGPSInformation
        case announcementInterval
        case showAccuracy
        case showSpeed

        var title: String {
            switch self {
            case .announceGPSInformation:
                return GDLocalizedString("settings.gps_information.announce_after_callouts")
            case .announcementInterval:
                return GDLocalizedString("settings.gps_information.interval")
            case .showAccuracy:
                return GDLocalizedString("settings.gps_information.show_accuracy")
            case .showSpeed:
                return GDLocalizedString("settings.gps_information.show_speed")
            }
        }

        var telemetryName: String {
            switch self {
            case .announceGPSInformation:
                return "announce_gps_information"
            case .announcementInterval:
                return "announcement_interval"
            case .showAccuracy:
                return "show_accuracy"
            case .showSpeed:
                return "show_speed"
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = GDLocalizedString("settings.gps_information.title")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "GPSInformationCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "GPSInformationValueCell")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Row.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let row = Row(rawValue: indexPath.row) else {
            return tableView.dequeueReusableCell(withIdentifier: "GPSInformationCell", for: indexPath)
        }

        if row == .announcementInterval {
            let cell = UITableViewCell(style: .value1, reuseIdentifier: "GPSInformationValueCell")
            cell.backgroundColor = Colors.Background.primary
            cell.textLabel?.text = row.title
            cell.textLabel?.textColor = Colors.Foreground.primary
            cell.textLabel?.numberOfLines = 0
            cell.textLabel?.adjustsFontForContentSizeCategory = true
            cell.detailTextLabel?.text = intervalLabel(SettingsContext.shared.gpsInformationAnnouncementIntervalMeters)
            cell.detailTextLabel?.textColor = Colors.Foreground.secondary
            cell.detailTextLabel?.adjustsFontForContentSizeCategory = true
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "GPSInformationCell", for: indexPath)

        let settingSwitch = UISwitch()
        settingSwitch.tag = row.rawValue
        settingSwitch.isOn = isEnabled(row)
        settingSwitch.addTarget(self, action: #selector(onSwitchValueChanged(_:)), for: .valueChanged)

        cell.backgroundColor = Colors.Background.primary
        cell.textLabel?.text = row.title
        cell.textLabel?.textColor = Colors.Foreground.primary
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.selectionStyle = .none
        cell.accessoryView = settingSwitch

        return cell
    }

    @objc private func onSwitchValueChanged(_ sender: UISwitch) {
        guard let row = Row(rawValue: sender.tag) else {
            return
        }

        setEnabled(sender.isOn, for: row)
        GDATelemetry.track("settings.gps_information", with: [
            "setting": row.telemetryName,
            "value": String(sender.isOn)
        ])
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer {
            tableView.deselectRow(at: indexPath, animated: true)
        }

        guard let row = Row(rawValue: indexPath.row), row == .announcementInterval else {
            return
        }

        presentIntervalSelector()
    }

    private func isEnabled(_ row: Row) -> Bool {
        switch row {
        case .announceGPSInformation:
            return SettingsContext.shared.announceGPSInformation
        case .announcementInterval:
            return true
        case .showAccuracy:
            return SettingsContext.shared.gpsAccuracyEnabled
        case .showSpeed:
            return SettingsContext.shared.gpsSpeedEnabled
        }
    }

    private func setEnabled(_ value: Bool, for row: Row) {
        switch row {
        case .announceGPSInformation:
            SettingsContext.shared.announceGPSInformation = value
        case .announcementInterval:
            return
        case .showAccuracy:
            SettingsContext.shared.gpsAccuracyEnabled = value
        case .showSpeed:
            SettingsContext.shared.gpsSpeedEnabled = value
        }
    }

    private func presentIntervalSelector() {
        let alert = UIAlertController(title: GDLocalizedString("settings.gps_information.interval"),
                                      message: nil,
                                      preferredStyle: .actionSheet)

        [50, 100, 300, 500, 1000].forEach { interval in
            let current = SettingsContext.shared.gpsInformationAnnouncementIntervalMeters
            let title = interval == current ? "✓ \(intervalLabel(interval))" : intervalLabel(interval)

            alert.addAction(UIAlertAction(title: title, style: .default, handler: { [weak self] _ in
                SettingsContext.shared.gpsInformationAnnouncementIntervalMeters = interval
                GDATelemetry.track("settings.gps_information", with: [
                    "setting": Row.announcementInterval.telemetryName,
                    "value": String(interval)
                ])
                self?.tableView.reloadData()
            }))
        }

        alert.addAction(UIAlertAction(title: GDLocalizedString("general.alert.cancel"), style: .cancel))

        if let popover = alert.popoverPresentationController,
           let cell = tableView.cellForRow(at: IndexPath(row: Row.announcementInterval.rawValue, section: 0)) {
            popover.sourceView = cell
            popover.sourceRect = cell.bounds
        }

        present(alert, animated: true)
    }

    private func intervalLabel(_ meters: Int) -> String {
        return GDLocalizedString("settings.gps_information.interval.value", String(meters))
    }
}

private final class MediaControlsSettingsViewController: UITableViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = GDLocalizedString("settings.audio.media_controls")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "MediaControlsCell")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return GDLocalizedString("settings.audio.mix_with_others.description")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "MediaControlsCell", for: indexPath)
        let settingSwitch = UISwitch()
        settingSwitch.isOn = !SettingsContext.shared.audioSessionMixesWithOthers
        settingSwitch.addTarget(self, action: #selector(onSwitchValueChanged(_:)), for: .valueChanged)

        cell.backgroundColor = Colors.Background.primary
        cell.textLabel?.text = GDLocalizedString("settings.audio.mix_with_others.title")
        cell.textLabel?.textColor = Colors.Foreground.primary
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.selectionStyle = .none
        cell.accessoryView = settingSwitch

        return cell
    }

    @objc private func onSwitchValueChanged(_ sender: UISwitch) {
        guard sender.isOn else {
            updateSetting(true)
            return
        }

        let alert = UIAlertController(title: GDLocalizedString("general.alert.confirmation_title"),
                                      message: GDLocalizedString("setting.audio.mix_with_others.confirmation"),
                                      preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: GDLocalizedString("settings.audio.mix_with_others.title"), style: .default, handler: { _ in
            self.updateSetting(false)
            self.tableView.reloadData()
        }))

        alert.addAction(UIAlertAction(title: GDLocalizedString("general.alert.cancel"), style: .cancel, handler: { _ in
            sender.isOn = false
            GDATelemetry.track("settings.mix_audio.cancel", with: ["context": "app_settings"])
        }))

        present(alert, animated: true)
    }

    private func updateSetting(_ newValue: Bool) {
        SettingsContext.shared.audioSessionMixesWithOthers = newValue
        AppContext.shared.audioEngine.mixWithOthers = newValue

        GDATelemetry.track("settings.mix_audio",
                           with: ["value": "\(SettingsContext.shared.audioSessionMixesWithOthers)",
                                  "context": "app_settings"])
    }
}

private final class ManageCalloutsSettingsViewController: UITableViewController {
    private enum Row: Int, CaseIterable {
        case all
        case poi
        case mobility
        case beacon
        case japaneseAddressProcessing

        var title: String {
            switch self {
            case .all: return GDLocalizedString("callouts.turn_on_off")
            case .poi: return GDLocalizedString("callouts.places_and_landmarks")
            case .mobility: return GDLocalizedString("callouts.mobility")
            case .beacon: return GDLocalizedString("callouts.audio_beacon")
            case .japaneseAddressProcessing: return GDLocalizedString("settings.japanese_address_processing")
            }
        }

        var subtitle: String? {
            switch self {
            case .japaneseAddressProcessing:
                return GDLocalizedString("settings.japanese_address_processing.info")
            default:
                return nil
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = GDLocalizedString("menu.manage_callouts")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ManageCalloutsCell")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Row.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let row = Row(rawValue: indexPath.row) else {
            return tableView.dequeueReusableCell(withIdentifier: "ManageCalloutsCell", for: indexPath)
        }

        let cellStyle: UITableViewCell.CellStyle = row == .japaneseAddressProcessing ? .subtitle : .default
        let cell = UITableViewCell(style: cellStyle, reuseIdentifier: "ManageCalloutsCell")
        let settingSwitch = UISwitch()
        settingSwitch.tag = row.rawValue
        settingSwitch.isOn = isEnabled(row)
        settingSwitch.isEnabled = row == .all || row == .japaneseAddressProcessing || SettingsContext.shared.automaticCalloutsEnabled
        settingSwitch.addTarget(self, action: #selector(onSwitchValueChanged(_:)), for: .valueChanged)

        cell.backgroundColor = Colors.Background.primary
        cell.textLabel?.text = row.title
        cell.textLabel?.textColor = Colors.Foreground.primary
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.detailTextLabel?.text = row.subtitle
        cell.detailTextLabel?.textColor = Colors.Foreground.secondary
        cell.detailTextLabel?.numberOfLines = 0
        cell.detailTextLabel?.adjustsFontForContentSizeCategory = true
        cell.selectionStyle = .none
        cell.accessoryView = settingSwitch
        return cell
    }

    @objc private func onSwitchValueChanged(_ sender: UISwitch) {
        guard let row = Row(rawValue: sender.tag) else {
            return
        }

        let isOn = sender.isOn

        switch row {
        case .all:
            SettingsContext.shared.automaticCalloutsEnabled = isOn
            GDATelemetry.track("settings.allow_callouts", value: isOn.description)
        case .poi:
            SettingsContext.shared.placeSenseEnabled = isOn
            SettingsContext.shared.landmarkSenseEnabled = isOn
            SettingsContext.shared.informationSenseEnabled = isOn
        case .mobility:
            SettingsContext.shared.mobilitySenseEnabled = isOn
            SettingsContext.shared.safetySenseEnabled = isOn
            SettingsContext.shared.intersectionSenseEnabled = isOn
        case .japaneseAddressProcessing:
            SettingsContext.shared.japaneseAddressProcessingEnabled = isOn
            GDATelemetry.track("settings.japanese_address_processing", value: isOn.description)
        case .beacon:
            SettingsContext.shared.destinationSenseEnabled = isOn
        }

        tableView.reloadData()
    }

    private func isEnabled(_ row: Row) -> Bool {
        switch row {
        case .all: return SettingsContext.shared.automaticCalloutsEnabled
        case .poi: return SettingsContext.shared.placeSenseEnabled
        case .mobility: return SettingsContext.shared.mobilitySenseEnabled
        case .beacon: return SettingsContext.shared.destinationSenseEnabled
        case .japaneseAddressProcessing: return SettingsContext.shared.japaneseAddressProcessingEnabled
        }
    }
}

private final class StreetPreviewSettingsViewController: UITableViewController {
    private enum Row: Int, CaseIterable {
        case includeUnnamedRoads
        case steeringMode
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = GDLocalizedString("preview.title")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "StreetPreviewCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "StreetPreviewValueCell")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Row.allCases.count
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return GDLocalizedString("preview.steering_mode.subtitle")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let row = Row(rawValue: indexPath.row) else {
            return tableView.dequeueReusableCell(withIdentifier: "StreetPreviewCell", for: indexPath)
        }

        switch row {
        case .includeUnnamedRoads:
            let cell = tableView.dequeueReusableCell(withIdentifier: "StreetPreviewCell", for: indexPath)
            let settingSwitch = UISwitch()
            settingSwitch.isOn = SettingsContext.shared.previewIntersectionsIncludeUnnamedRoads
            settingSwitch.addTarget(self, action: #selector(onSwitchValueChanged(_:)), for: .valueChanged)

            cell.backgroundColor = Colors.Background.primary
            cell.textLabel?.text = GDLocalizedString("preview.include_unnamed_roads.title")
            cell.textLabel?.textColor = Colors.Foreground.primary
            cell.textLabel?.numberOfLines = 0
            cell.textLabel?.adjustsFontForContentSizeCategory = true
            cell.selectionStyle = .none
            cell.accessoryView = settingSwitch
            cell.detailTextLabel?.text = nil
            return cell

        case .steeringMode:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: "StreetPreviewValueCell")
            cell.backgroundColor = Colors.Background.primary
            cell.textLabel?.text = GDLocalizedString("preview.steering_mode.title")
            cell.textLabel?.textColor = Colors.Foreground.primary
            cell.textLabel?.numberOfLines = 0
            cell.textLabel?.adjustsFontForContentSizeCategory = true
            cell.detailTextLabel?.text = SettingsContext.shared.previewSteeringMode.localizedName
            cell.detailTextLabel?.textColor = Colors.Foreground.secondary
            cell.detailTextLabel?.adjustsFontForContentSizeCategory = true
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
            return cell
        }
    }

    @objc private func onSwitchValueChanged(_ sender: UISwitch) {
        SettingsContext.shared.previewIntersectionsIncludeUnnamedRoads = sender.isOn
        GDATelemetry.track("preview.include_unnamed_roads", with: ["value": "\(sender.isOn)", "context": "app_settings"])
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer {
            tableView.deselectRow(at: indexPath, animated: true)
        }

        guard let row = Row(rawValue: indexPath.row), row == .steeringMode else {
            return
        }

        let alert = UIAlertController(title: GDLocalizedString("preview.steering_mode.title"),
                                      message: nil,
                                      preferredStyle: .actionSheet)

        [SettingsContext.PreviewSteeringMode.deviceOrientation, SettingsContext.PreviewSteeringMode.buttonSteering].forEach { mode in
            let current = SettingsContext.shared.previewSteeringMode
            let title = mode == current ? "✓ \(mode.localizedName)" : mode.localizedName
            alert.addAction(UIAlertAction(title: title, style: .default, handler: { [weak self] _ in
                SettingsContext.shared.previewSteeringMode = mode
                GDATelemetry.track("preview.steering_mode", with: [
                    "value": mode.rawValue,
                    "context": "app_settings"
                ])
                self?.tableView.reloadData()
            }))
        }

        alert.addAction(UIAlertAction(title: GDLocalizedString("general.alert.cancel"), style: .cancel))

        if let popover = alert.popoverPresentationController,
           let cell = tableView.cellForRow(at: indexPath) {
            popover.sourceView = cell
            popover.sourceRect = cell.bounds
        }

        present(alert, animated: true)
    }
}
