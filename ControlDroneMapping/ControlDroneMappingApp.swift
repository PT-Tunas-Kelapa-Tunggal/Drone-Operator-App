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
        // Exercise the actual signed app and inherited helper sandbox without opening a window.
        let checkFeatures = ProcessInfo.processInfo.arguments.contains("--check-orthomosaic-features")
        if checkFeatures || ProcessInfo.processInfo.arguments.contains("--check-orthomosaic-engine") {
            do {
                guard let runtime = BundledOrthomosaicEngine.embeddedDirectory,
                    let worker = Bundle.main.url(forResource: "orthomosaic_worker", withExtension: "py")
                else { throw MappingError.invalid("Engine bawaan belum disertakan dalam build.") }
                let message = try LocalOrthomosaicProcessor(worker: worker).check(
                    runtime: runtime, cancellation: OrthomosaicCancellation(), features: checkFeatures)
                print(message)
                exit(0)
            } catch {
                FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
                exit(1)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--check-qgc-engine") {
            do {
                let message = try BundledQGCEngine.check()
                print(message)
                exit(0)
            } catch {
                FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
                exit(1)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--check-vari-engine") {
            do {
                let message = try BundledVariEngine.check()
                print(message)
                exit(0)
            } catch {
                FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
                exit(1)
            }
        }
        let demo =
            ProcessInfo.processInfo.arguments.contains("--demo")
            || Bundle.main.object(forInfoDictionaryKey: "DroneControlDemoMode") as? Bool == true
        let dependencies = ControlDependencies(demo: demo)
        _location = StateObject(wrappedValue: dependencies.location)
        _planner = StateObject(wrappedValue: dependencies.planner)
        link = dependencies.link
        _farms = StateObject(wrappedValue: dependencies.farms)
        _model = StateObject(wrappedValue: dependencies.viewModel)

        // Auto-start QGC companion engine on normal launch
        QGCEngineManager.shared.startEngine()

        // Clean teardown on app exit
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                QGCEngineManager.shared.stopEngine()
            }
        }
    }
    @AppStorage("dashboardAppearance") private var appearance = "light"
    var body: some Scene {
        WindowGroup(model.isDemo ? "Krops - Demo" : "Krops") {
            ContentView(model: model, link: link, farms: farms, location: location, planner: planner)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .tint(KropsStyle.accent)
                // Every bordered and glass button is a capsule; icon-only buttons opt into a circle.
                .buttonBorderShape(.capsule)
                .font(.body)
                .controlSize(.regular)
        }.defaultSize(width: 1440, height: 900)
    }
}
