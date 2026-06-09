import Foundation

/// Builds the GUI-free core services the CLI needs. Mirrors the FluidAudio wiring
/// from `AppDependencies.live()` but only the transcription/diarization/export/settings
/// pieces — no recorder, playback, call watcher, or dictation.
struct TranscribeServiceFactory {
    let transcription: any TranscriptionService
    let diarization: any SpeakerDiarizationService
    let exporter: any ExportService
    let settings: AppSettingsStore

    init() {
        #if canImport(FluidAudio)
        _ = TextNormalizationRuntimeSupport.prepare()
        let enrollment = FluidAudioSpeakerEnrollmentService()
        self.transcription = FluidAudioTranscriptionService()
        self.diarization = FluidAudioDiarizationService(enrollmentService: enrollment)
        #else
        self.transcription = MockTranscriptionService()
        self.diarization = MockSpeakerDiarizationService()
        #endif
        self.exporter = MarkdownExportService()
        self.settings = AppSettingsStore()
    }
}
