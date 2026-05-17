//
//  SmallBannerContainerView.swift
//  Soundscape
//
//  Copyright (c) Microsoft Corporation.
//  Licensed under the MIT License.
//

import Foundation
import UIKit

protocol SmallBannerContainerView {
    var smallBannerContainerView: UIView! { get }
    func setSmallBannerHeight(_ height: CGFloat)
}
