import SwiftUI
import CoreData

struct ContentView: View {
    var body: some View {
        ScannerView()
            .preferredColorScheme(.dark)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
