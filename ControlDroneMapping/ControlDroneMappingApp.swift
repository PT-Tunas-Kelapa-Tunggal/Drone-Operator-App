//
//  ControlDroneMappingApp.swift
//  ControlDroneMapping
//
//  Created by Hatami Sugandi on 10/10/26.
//

import SwiftUI

@main
struct ControlDroneMappingApp: App {
    @StateObject private var model: ControlViewModel
    @StateObject private var location: OperatorLocationViewModel
    @StateObject private var planner: FlightPlannerViewModel
    private let link: LocalLink
    @StateObject private var farms: FarmAreaViewModel

    init() {
        let demo =
            ProcessInfo.processInfo.arguments.contains("--demo")
            || Bundle.main.object(forInfoDictionaryKey: "DroneControlDemoMode") as? Bool == true
        let dependencies = ControlDependencies(demo: demo)
        _location = StateObject(wrappedValue: dependencies.location)
        _planner = StateObject(wrappedValue: dependencies.planner)
        link = dependencies.link
        _farms = StateObject(wrappedValue: dependencies.farms)
        _model = StateObject(wrappedValue: dependencies.viewModel)
    }
    @AppStorage("dashboardAppearance") private var appearance = "light"
    var body: some Scene {
        WindowGroup(model.isDemo ? "Krops - Demo" : "Krops") {
            ContentView(model: model, link: link, farms: farms, location: location, planner: planner)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .tint(KropsStyle.accent)
                .font(.body)
                .controlSize(.regular)
        }.defaultSize(width: 1440, height: 900)
    }
}
