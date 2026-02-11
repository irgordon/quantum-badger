import SwiftUI

struct StreamingBufferView: View {
    let text: String
    @State private var displayedText: String = ""
    
    var body: some View {
        Text(displayedText)
            .textSelection(.enabled)
            // Use .task(id:) to restart when text changes
            .task(id: text) {
                // If text was cleared or totally changed (not just appended)
                if !text.hasPrefix(displayedText) {
                    displayedText = ""
                }
                
                // Fast forward if displayed is somehow longer
                if displayedText.count > text.count {
                    displayedText = text
                }
                
                // Typewriter effect
                while displayedText.count < text.count {
                    // Safety check index
                    let nextIndex = text.index(text.startIndex, offsetBy: displayedText.count)
                    // Append the character
                    let nextChar = text[nextIndex]
                    
                    // Simple append to avoid index recalculation issues on 'displayedText'
                    displayedText.append(nextChar)
                    
                    // Dynamic sleep based on length to speed up long responses
                    let sleepTime: UInt64 = text.count > 500 ? 5_000_000 : 18_000_000
                    try? await Task.sleep(nanoseconds: sleepTime)
                }
            }
    }
}
