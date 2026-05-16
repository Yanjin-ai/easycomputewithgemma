import SwiftUI

@main
struct GemmaHostApp: App {
    @StateObject private var model = AppModel()
    @AppStorage(AppConfig.onboardingCompleteKey) private var onboardingComplete = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .fullScreenCover(isPresented: onboardingPresentation) {
                    OnboardingView {
                        onboardingComplete = true
                        _Concurrency.Task {
                            await model.bootstrap()
                        }
                    }
                    .environmentObject(model)
                }
                .task {
                    guard onboardingComplete else { return }
                    await model.bootstrap()
                }
        }
    }

    private var onboardingPresentation: Binding<Bool> {
        Binding(
            get: { !onboardingComplete },
            set: { isPresented in
                if !isPresented {
                    onboardingComplete = true
                }
            }
        )
    }
}
