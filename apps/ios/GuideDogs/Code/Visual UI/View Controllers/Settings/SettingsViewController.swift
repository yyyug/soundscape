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
        case callouts = 2
        case streetPreview = 3
        case troubleshooting = 4
        case telemetry = 5
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
        case .audio, .callouts, .streetPreview: return nil
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
    override func viewDidLoad() {
        super.viewDidLoad()
        title = GDLocalizedString("preview.title")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "StreetPreviewCell")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return GDLocalizedString("preview.include_unnamed_roads.subtitle")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
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
        return cell
    }

    @objc private func onSwitchValueChanged(_ sender: UISwitch) {
        SettingsContext.shared.previewIntersectionsIncludeUnnamedRoads = sender.isOn
        GDATelemetry.track("preview.include_unnamed_roads", with: ["value": "\(sender.isOn)", "context": "app_settings"])
    }
}
