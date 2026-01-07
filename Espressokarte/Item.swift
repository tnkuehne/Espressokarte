//
//  Item.swift
//  Espressokarte
//
//  Created by Timo Kuehne on 07.01.26.
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
