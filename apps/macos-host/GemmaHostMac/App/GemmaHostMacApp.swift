import SwiftUI

@main
struct GemmaHostMacApp: App {
    @StateObject private var model = MacAppModel()

    var body: some Scene {
        MenuBarExtra("Gemma", systemImage: "cpu.fill") {
            MenuBarView()
                .environmentObject(model)
                .onAppear {
                    _Concurrency.Task {
                        await model.bootstrap()
                    }
                }
        }
        .menuBarExtraStyle(.window)
    }
}
