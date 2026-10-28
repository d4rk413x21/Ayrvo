import SwiftUI

struct CalendarTemplateOptions: View {
    let names: [String]
    let selected: String?
    let onSelect: (String?) -> Void

    var body: some View {
        ForEach(names, id: \.self) { name in
            Button { onSelect(name) } label: {
                if name == selected {
                    Label(name, systemImage: "checkmark")
                } else {
                    Text(name)
                }
            }
        }
        if selected != nil {
            Divider()
            Button { onSelect(nil) } label: {
                Label("Use default", systemImage: "arrow.counterclockwise")
            }
        }
    }
}
