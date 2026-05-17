//
//  DismissableViewControllerDelegate.swift
//  Soundscape
//
//  Copyright (c) Microsoft Corporation.
//  Licensed under the MIT License.
//

import Foundation
import UIKit

protocol DismissableViewControllerDelegate: AnyObject {
    func onDismissed(_ viewController: UIViewController)
}
