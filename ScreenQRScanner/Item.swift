//
//  Item.swift
//  ScreenQRScanner
//
//  Created by haojieli on 2025/12/29.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
