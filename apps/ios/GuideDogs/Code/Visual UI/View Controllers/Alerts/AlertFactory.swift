//
//  AlertFactory.swift
//  Soundscape
//
//  Copyright (c) Microsoft Corporation.
//  Licensed under the MIT License.
//

import Foundation
import UIKit

protocol AlertFactory {
    typealias ActionHandler = (UIAlertAction) -> Void
}
