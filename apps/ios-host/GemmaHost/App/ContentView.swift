import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            TaskInputView()
                .tabItem {
                    Label("New Task", systemImage: "square.and.pencil")
                }

            NavigationStack {
                TaskListView()
            }
            .tabItem {
                Label("Tasks", systemImage: "list.bullet")
            }
        }
        .overlay(alignment: .top) {
            if let registrationError = model.registrationError {
                Text(registrationError)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.red, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
    }
}
