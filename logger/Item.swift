//
//  Item.swift
//  logger
//
//  Created by Erick Fuentes on 12/1/24.
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
