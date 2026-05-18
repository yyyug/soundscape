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
    
    private enum CalloutsRow: Int, CaseIterable {
        case all = 0
        case poi = 1
        case mobility = 2
        case beacon = 3
    }
    
    private static let cellIdentifiers: [IndexPath: String] = [
        IndexPath(row: 0, section: Section.general.rawValue): "languageAndRegion",
        IndexPath(row: 1, section: Section.general.rawValue): "voice",
        IndexPath(row: 2, section: Section.general.rawValue): "beaconSettings",
        IndexPath(row: 3, section: Section.general.rawValue): "volumeSettings",
        IndexPath(row: 4, section: Section.general.rawValue): "manageDevices",
        IndexPath(row: 7, section: Section.general.rawValue): "siriShortcuts",
        
        IndexPath(row: 0, section: Section.audio.rawValue): "mixAudio",

        IndexPath(row: CalloutsRow.all.rawValue, section: Section.callouts.rawValue): "allCallouts",
        IndexPath(row: CalloutsRow.poi.rawValue, section: Section.callouts.rawValue): "poiCallouts",
        IndexPath(row: CalloutsRow.mobility.rawValue, section: Section.callouts.rawValue): "mobilityCallouts",
        IndexPath(row: CalloutsRow.beacon.rawValue, section: Section.callouts.rawValue): "beaconCallouts",
        
        IndexPath(row: 0, section: Section.streetPreview.rawValue): "streetPreview",
        IndexPath(row: 0, section: Section.troubleshooting.rawValue): "troubleshooting",
        IndexPath(row: 0, section: Section.telemetry.rawValue): "telemetry"
    ]
    
    private static let collapsibleCalloutIndexPaths: [IndexPath] = [
        IndexPath(row: CalloutsRow.poi.rawValue, section: Section.callouts.rawValue),
        IndexPath(row: CalloutsRow.mobility.rawValue, section: Section.callouts.rawValue),
        IndexPath(row: CalloutsRow.beacon.rawValue, section: Section.callouts.rawValue)
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
        case .callouts: return SettingsContext.shared.automaticCalloutsEnabled ? 4 : 1
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

        case .callouts:
            let cell = tableView.dequeueReusableCell(withIdentifier: identifier ?? "default", for: indexPath) as! CalloutSettingsCellView
            cell.delegate = self

            if let rowType = CalloutsRow(rawValue: indexPath.row) {
                switch rowType {
                case .all: cell.type = .all
                case .poi: cell.type = .poi
                case .mobility: cell.type = .mobility
                case .beacon: cell.type = .beacon
                }
            }
            
            return cell
            
        case .telemetry:
            let cell = tableView.dequeueReusableCell(withIdentifier: identifier ?? "default", for: indexPath) as! TelemetrySettingsTableViewCell
            cell.parent = self
            
            return cell
            
        case .audio:
            let cell = tableView.dequeueReusableCell(withIdentifier: identifier ?? "default", for: indexPath) as! MixAudioSettingCell
            cell.delegate = self
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
        case .audio: return GDLocalizedString("settings.audio.media_controls")
        case .callouts: return GDLocalizedString("menu.manage_callouts")
        case .streetPreview: return GDLocalizedString("preview.title")
        case .troubleshooting: return GDLocalizedString("settings.section.troubleshooting")
        case .telemetry: return GDLocalizedString("settings.section.telemetry")
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let sectionType = Section(rawValue: section) else { return nil }

        switch sectionType {
        case .audio: return GDLocalizedString("settings.audio.mix_with_others.description")
        case .general: return nil
        case .streetPreview: return GDLocalizedString("preview.include_unnamed_roads.subtitle")
        case .telemetry: return GDLocalizedString("settings.section.telemetry.footer")
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer {
            tableView.deselectRow(at: indexPath, animated: true)
        }

        guard indexPath.section == Section.general.rawValue else {
            return
        }

        switch indexPath.row {
        case GeneralRow.checkAudio:
            AppContext.process(CheckAudioEvent())
        case GeneralRow.gpsInformation:
            let vc = GPSInformationSettingsViewController(style: .insetGrouped)
            navigationController?.pushViewController(vc, animated: true)
        default:
            return
        }
    }
}

extension SettingsViewController: MixAudioSettingCellDelegate {
    func onSettingValueChanged(_ cell: MixAudioSettingCell, settingSwitch: UISwitch) {
        // Note: The UI for this setting is "Enable Media Controls" but the setting is stored as
        //       "Mixes with Others" (the inverse of "Enable Media Controls")
        
        guard settingSwitch.isOn else {
            // If the setting switch is now off, the user disabled media controls. This doesn't
            // require a warning alert, so just set mixesWithOthers to true and return.
            updateSetting(true)
            return
        }
        
        // Otherwise, the user is turning on media controls, so we need to show a warning to make sure
        // they understand what this change means in terms of how other audio apps will stop Soundscape
        // from playing. This warning was added based on bug bash feedback on 12/3/20.
        // Show an alert indicating that the user can download an enhanced version of the voice in Settings
        let alert = UIAlertController(title: GDLocalizedString("general.alert.confirmation_title"),
                                      message: GDLocalizedString("setting.audio.mix_with_others.confirmation"),
                                      preferredStyle: .alert)
        
        let mixAction = UIAlertAction(title: GDLocalizedString("settings.audio.mix_with_others.title"), style: .default) { [weak self] (_) in
            // Make the setting switch - turn off mixesWithOthers
            self?.updateSetting(false)
            self?.focusOnCell(cell)
        }
        alert.addAction(mixAction)
        alert.preferredAction = mixAction
        
        alert.addAction(UIAlertAction(title: GDLocalizedString("general.alert.cancel"), style: .cancel, handler: { [weak self] (_) in
            // Toggle the setting back off
            settingSwitch.isOn = false
            
            // Track that the user decided not to enable media controls
            GDATelemetry.track("settings.mix_audio.cancel", with: ["context": "app_settings"])
            
            self?.focusOnCell(cell)
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
    
    private func focusOnCell(_ cell: MixAudioSettingCell) {
        DispatchQueue.main.async {
            UIAccessibility.post(notification: .layoutChanged, argument: cell)
        }
    }
}

extension SettingsViewController: CalloutSettingsCellViewDelegate {
    func onCalloutSettingChanged(_ type: CalloutSettingCellType) {
        guard type == .all else {
            return
        }
        
        let indexPaths = SettingsViewController.collapsibleCalloutIndexPaths
        
        if SettingsContext.shared.automaticCalloutsEnabled && !tableView.contains(indexPaths: indexPaths) {
            tableView.insertRows(at: indexPaths, with: .automatic)
        } else if !SettingsContext.shared.automaticCalloutsEnabled && tableView.contains(indexPaths: indexPaths) {
            tableView.deleteRows(at: indexPaths, with: .automatic)
        }
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
        case announceAfterCallouts
        case showFacing
        case showAccuracy
        case showSpeed

        var title: String {
            switch self {
            case .announceAfterCallouts:
                return GDLocalizedString("settings.gps_information.announce_after_callouts")
            case .showFacing:
                return GDLocalizedString("settings.gps_information.show_facing")
            case .showAccuracy:
                return GDLocalizedString("settings.gps_information.show_accuracy")
            case .showSpeed:
                return GDLocalizedString("settings.gps_information.show_speed")
            }
        }

        var telemetryName: String {
            switch self {
            case .announceAfterCallouts:
                return "announce_after_callouts"
            case .showFacing:
                return "show_facing"
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
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Row.allCases.count
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return GDLocalizedString("settings.gps_information.footer")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "GPSInformationCell", for: indexPath)
        guard let row = Row(rawValue: indexPath.row) else {
            return cell
        }

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

    private func isEnabled(_ row: Row) -> Bool {
        switch row {
        case .announceAfterCallouts:
            return SettingsContext.shared.announceFacingAndAccuracyAfterCallouts
        case .showFacing:
            return SettingsContext.shared.gpsFacingEnabled
        case .showAccuracy:
            return SettingsContext.shared.gpsAccuracyEnabled
        case .showSpeed:
            return SettingsContext.shared.gpsSpeedEnabled
        }
    }

    private func setEnabled(_ value: Bool, for row: Row) {
        switch row {
        case .announceAfterCallouts:
            SettingsContext.shared.announceFacingAndAccuracyAfterCallouts = value
        case .showFacing:
            SettingsContext.shared.gpsFacingEnabled = value
        case .showAccuracy:
            SettingsContext.shared.gpsAccuracyEnabled = value
        case .showSpeed:
            SettingsContext.shared.gpsSpeedEnabled = value
        }
    }
}
