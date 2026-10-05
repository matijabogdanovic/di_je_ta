import SwiftUI
import PhotosUI
import AVFoundation
import UIKit
import WeightCoachAI
import WeightCoachCore

@MainActor @Observable
final class MealPhotoDraft {
    var image:UIImage?
    var isLoading = false
    var isAnalyzing = false
    var result:AnalysisResult?
    var submittedNote:String?
    var error:String?
    private var operation:Task<Void,Never>?
    private var generation = UUID()
    func select(_ picker:PhotosPickerItem) {
        purge(); result = nil; submittedNote = nil; error = nil; isLoading = true
        let version = generation
        operation = Task { @MainActor in
            defer { if version == generation { isLoading = false; operation = nil } }
            do {
                guard let data = try await picker.loadTransferable(type:Data.self), !Task.isCancelled, version == generation else { return }
                guard data.count <= 40_000_000, let image = UIImage(data:data), image.size.width > 0, image.size.height > 0 else { throw AIError.message("Choose a still photo under 40 MB.") }
                self.image = Self.prepared(image)
            } catch { if version == generation && !Task.isCancelled { self.error = "Could not load that photo. Try another image." } }
        }
    }
    func capture(_ image:UIImage) { purge(); result = nil; submittedNote = nil; error = nil; self.image = Self.prepared(image) }
    private static func prepared(_ image:UIImage) -> UIImage {
        let ratio = min(1,1536/max(image.size.width,image.size.height))
        let size = CGSize(width:image.size.width*ratio,height:image.size.height*ratio)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        // Redrawing normalizes orientation and removes source metadata (including GPS).
        return UIGraphicsImageRenderer(size:size,format:format).image { _ in image.draw(in:CGRect(origin:.zero,size:size)) }
    }
    func analyze(provider:any MealRecognizing,note:String,model:String,onResult:@escaping @MainActor (AnalysisResult,String) throws -> Void) {
        guard let image, !isAnalyzing else { return }
        guard let jpeg = image.jpegData(compressionQuality:0.8) else { error = "Could not prepare this photo."; return }
        error = nil; isAnalyzing = true; let version = generation
        operation = Task { @MainActor in
            defer { if version == generation { isAnalyzing = false; operation = nil } }
            do {
                let result = try await provider.recognize(jpeg:jpeg,note:note,model:model)
                try Task.checkCancellation(); guard version == generation else { return }
                try onResult(result,note); self.result = result; submittedNote = note
            } catch is CancellationError { }
            catch { if version == generation { self.error = error.localizedDescription } }
        }
    }
    func cancelAnalysis() { generation = UUID(); operation?.cancel(); operation = nil; isLoading = false; isAnalyzing = false }
    func purge() { cancelAnalysis(); image = nil }
}
struct MealPhotoSection: View {
    @Bindable var draft:MealPhotoDraft
    @Bindable var connection:ChatGPTConnection
    @Binding var meal:Meal
    @Binding var audit:MealEstimateAudit?
    @State private var picker:PhotosPickerItem?
    @State private var camera = false
    @State private var replace = false
    var body: some View {
        Section {
            if let image = draft.image { Image(uiImage:image).resizable().scaledToFit().frame(maxHeight:220).clipShape(RoundedRectangle(cornerRadius:12)) }
            HStack {
                Button { Task { await openCamera() } } label: { Label("Camera",systemImage:"camera") }.buttonStyle(.bordered)
                PhotosPicker(selection:$picker,matching:.images,photoLibrary:.shared()) { Label("Photo library",systemImage:"photo.on.rectangle") }.buttonStyle(.bordered)
            }.disabled(draft.isAnalyzing || draft.isLoading)
            TextField("E.g. butter under the vegetables, about 10 g",text:$meal.notes,axis:.vertical).lineLimit(2...4).disabled(draft.isAnalyzing)
            Text("Mention ingredients the photo can’t show: butter, oil, sauces, sugar, or a known portion size.").font(.caption).foregroundStyle(.secondary)
            if draft.isLoading { ProgressView("Preparing photo…") }
            if draft.isAnalyzing {
                ProgressView("Estimating foods and portions…")
                Button("Cancel analysis") { draft.cancelAnalysis() }
            } else if draft.image != nil {
                Button { if meal.items.contains(where: { !$0.foodName.isEmpty }) { replace = true } else { analyze() } } label: { Label(draft.result == nil ? "Estimate with AI" : "Estimate again",systemImage:"sparkles") }
                    .disabled(connection.accountLabel == nil || connection.selectedModel.isEmpty || meal.notes.count > 2000)
                if connection.accountLabel == nil { Text("Connect ChatGPT in Settings to analyze photos. You can log manually below.").font(.caption).foregroundStyle(.secondary) }
                else if connection.selectedModel.isEmpty { Text("Choose an available model in Settings.").font(.caption).foregroundStyle(.secondary) }
                Text("Tapping Estimate sends this photo and note to OpenAI. The app keeps the photo only in memory and discards it when you save, leave, or background the app.").font(.caption).foregroundStyle(.secondary)
                Button("Remove photo",role:.destructive) { draft.purge(); picker = nil }
            }
            if let result = draft.result {
                Text("Estimate confidence: \(result.recognition.overall_confidence)").font(.subheadline.bold())
                if !result.recognition.assumptions.isEmpty { Text(result.recognition.assumptions).font(.caption).foregroundStyle(.secondary) }
                ForEach(Array(result.recognition.foods.enumerated()),id:\.offset) { _,food in
                    if !food.uncertainty.isEmpty { Text("\(food.name): \(food.uncertainty)").font(.caption).foregroundStyle(.secondary) }
                }
                Text("Review the foods and adjust all amounts below. Photo estimates are approximate.").font(.caption)
                if draft.submittedNote != meal.notes { Text("Your note changed after analysis. The current estimate used the earlier note; analyze again to account for the change.").font(.caption).foregroundStyle(.orange) }
            }
            if let error = draft.error { Text(error).font(.callout).foregroundStyle(.red) }
        } header: { Text("Photo & hidden ingredients") }
        .onChange(of:picker) { _,value in if let value { draft.select(value); picker = nil } }
        .sheet(isPresented:$camera) { CameraCapture { image in camera = false; if let image { draft.capture(image) } } }
        .confirmationDialog("Replace the current food entries with a new estimate?",isPresented:$replace,titleVisibility:.visible) { Button("Replace with estimate") { analyze() } }
    }
    private func analyze() {
        draft.analyze(provider:connection.recognizer,note:meal.notes,model:connection.selectedModel) { result,note in
            let newAudit = try result.audit(note:note)
            meal.items = result.recognition.items; audit = newAudit
        }
    }
    private func openCamera() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { draft.error = "A camera is not available on this device. Choose a photo from your library."; return }
        let status = AVCaptureDevice.authorizationStatus(for:.video)
        let permitted:Bool
        if status == .notDetermined { permitted = await AVCaptureDevice.requestAccess(for:.video) }
        else { permitted = status == .authorized }
        if permitted { camera = true } else { draft.error = "Camera access is off. Enable it in iPhone Settings → Weight Coach → Camera, or use the photo library." }
    }
}
struct CameraCapture:UIViewControllerRepresentable {
    let completion:(UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion:completion) }
    func makeUIViewController(context:Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = .camera; picker.cameraCaptureMode = .photo; picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ uiViewController:UIImagePickerController,context:Context) {}
    final class Coordinator:NSObject,UIImagePickerControllerDelegate,UINavigationControllerDelegate {
        let completion:(UIImage?) -> Void
        init(completion:@escaping (UIImage?) -> Void) { self.completion = completion }
        func imagePickerController(_ picker:UIImagePickerController,didFinishPickingMediaWithInfo info:[UIImagePickerController.InfoKey:Any]) { completion(info[.originalImage] as? UIImage) }
        func imagePickerControllerDidCancel(_ picker:UIImagePickerController) { completion(nil) }
    }
}
struct ChatGPTSettingsView:View {
    @Bindable var connection:ChatGPTConnection
    var body: some View {
        Form {
            Section("ChatGPT plan") {
                if let label = connection.accountLabel {
                    Label(label,systemImage:"checkmark.shield")
                    Button("Reconnect ChatGPT") { connection.connect() }.disabled(connection.isConnecting)
                    Button("Disconnect",role:.destructive) { Task { await connection.disconnect() } }
                } else { Button("Continue with ChatGPT") { connection.connect() }.disabled(connection.isConnecting) }
                if connection.isConnecting { ProgressView("Waiting for sign-in…"); Button("Cancel") { connection.cancel() } }
                Text("Authorize ChatGPT plan usage in the sign-in screen. Eligibility and usage limits depend on your account. Credentials are stored securely on this device.").font(.caption).foregroundStyle(.secondary)
            }
            if connection.accountLabel != nil {
                Section("Meal recognition model") {
                    if !connection.models.isEmpty {
                        Picker("Model",selection:$connection.selectedModel) { ForEach(connection.models) { Text($0.name).tag($0.slug) } }
                    }
                    Button("Refresh available models") { Task { do { try await connection.refreshModels() } catch { connection.error = error.localizedDescription } } }
                    Text("Choose a model that accepts images and structured output. Unsupported requests show an error without saving a meal.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error = connection.error { Section { Text(error).foregroundStyle(.red) } }
        }.navigationTitle("AI recognition")
    }
}
