//
//  DroneMappingApp.swift
//  DroneMapping
//
//  Created by Hatami Sugandi on 10/10/26.
//

import SwiftUI

@main
struct DroneMappingApp: App {
    @StateObject private var model: CameraViewModel
    private let link: LocalLink
    init() {
        let dependencies = CameraDependencies()
        link = dependencies.link
        _model = StateObject(wrappedValue: dependencies.viewModel)
    }
    var body: some Scene {
        WindowGroup {
//            ContentView(model: model, link: link)
//                .preferredColorScheme(.dark)
            TestOrtoView()
        }
    }
}
