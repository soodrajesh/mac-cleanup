import SwiftUI

@main
struct DiskSweeperApp: App {
    @StateObject private var model = SweepModel()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(model)
                .frame(minWidth: 680, minHeight: 640)
                .onAppear { model.scanAll() }
        }
        .windowResizability(.contentMinSize)
    }
}
