//
//  CafeAnnotation.swift
//  Espressokarte
//
//  Created by Timo Kuehne on 07.01.26.
//

import Foundation
import MapKit

/// Map annotation for displaying a cafe with its espresso price
final class CafeAnnotation: NSObject, MKAnnotation, Identifiable {
    let id: String
    let cafe: Cafe

    var coordinate: CLLocationCoordinate2D {
        cafe.coordinate
    }

    var title: String? {
        cafe.formattedPrice ?? "No price"
    }

    var subtitle: String? {
        cafe.name
    }

    init(cafe: Cafe) {
        self.id = cafe.id
        self.cafe = cafe
        super.init()
    }
}
