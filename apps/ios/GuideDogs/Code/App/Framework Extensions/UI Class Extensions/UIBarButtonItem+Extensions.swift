//
//  UIBarButtonItem+Extensions.swift
//  Soundscape
//
//  Copyright (c) Microsoft Corporation.
//  Licensed under the MIT License.
//

import Foundation
import UIKit

extension UIBarButtonItem {
    
    static var defaultBackBarButtonItem: UIBarButtonItem {
        let item = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
        item.accessibilityLabel = nil
        return item
    }
    
}
