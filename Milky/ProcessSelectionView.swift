import SwiftUI

@MainActor
struct ProcessSelectionView: View {
    @State private var processController = AudioProcessController()
    @State private var tap: ProcessTap?
    @State private var selectedProcess: AudioProcess?

    var body: some View {
        
        Section {
            Picker("App", selection: $selectedProcess) {
                Text("Select…")
                    .tag(Optional<AudioProcess>.none)

                ForEach(processController.processes) { process in
                    HStack {
                        Image(nsImage: process.icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)

                        Text(process.name)
                    }
                    .tag(Optional<AudioProcess>.some(process))
                }
            }
            .disabled(tap != nil)
            .task { processController.activate() }
            .onChange(of: selectedProcess) { oldValue, newValue in
                guard newValue != oldValue else { return }

                if let newValue {
                    setupVisualization(for: newValue)
                }
            }
        } header: {
            Text("Audio Capture Source")
                .font(.headline)
        }

        if tap != nil {
            ConfigView( appIcon: selectedProcess!.icon, isRecording: tap != nil)
        }
    }

    private func setupVisualization(for process: AudioProcess) {
        let newTap = ProcessTap(process: process)
        self.tap = newTap
        newTap.activate()
    }
}
