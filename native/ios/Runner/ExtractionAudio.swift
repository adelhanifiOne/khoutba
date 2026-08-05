import AVFoundation
import Flutter
import UIKit

/// Extrait la piste sonore d'une vidéo dans un fichier .m4a.
///
/// Une vidéo de prêche de 11 min pèse ~700 Mo, sa piste sonore une dizaine.
/// AVAssetExportSession fait le travail hors du fil principal et sans charger
/// le fichier en mémoire — indispensable : iOS tue une app qui essaie.
public class ExtractionAudio: NSObject, FlutterPlugin {
  private let canal: FlutterMethodChannel
  private var minuteur: Timer?

  init(canal: FlutterMethodChannel) {
    self.canal = canal
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let canal = FlutterMethodChannel(
      name: "khoutba/extraction",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(ExtractionAudio(canal: canal), channel: canal)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "espaceLibre" {
      result(espaceLibre())
      return
    }
    guard call.method == "extraire" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let arguments = call.arguments as? [String: Any],
      let source = arguments["source"] as? String,
      let destination = arguments["destination"] as? String
    else {
      result(FlutterError(code: "arguments", message: "source et destination attendues", details: nil))
      return
    }
    extraire(source: source, destination: destination, result: result)
  }

  /// Octets réellement disponibles pour l'app, ou -1 si le système ne le dit
  /// pas. `forImportantUsage` compte la place qu'iOS libérerait en purgeant
  /// ses caches : c'est celle qu'on aura vraiment.
  private func espaceLibre() -> Int64 {
    let url = URL(fileURLWithPath: NSHomeDirectory())
    let valeurs = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    return valeurs?.volumeAvailableCapacityForImportantUsage ?? -1
  }

  private func extraire(source: String, destination: String, result: @escaping FlutterResult) {
    let sortie = URL(fileURLWithPath: destination)
    try? FileManager.default.removeItem(at: sortie)

    let asset = AVURLAsset(url: URL(fileURLWithPath: source))
    guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
    else {
      result(FlutterError(code: "echec", message: "Format vidéo non pris en charge par le système.", details: nil))
      return
    }
    export.outputURL = sortie
    export.outputFileType = .m4a

    // Sans retour visible, une extraction de 30 s passe pour un plantage.
    let minuteur = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self, weak export] _ in
      guard let export = export else { return }
      self?.canal.invokeMethod("progression", arguments: Double(export.progress))
    }
    self.minuteur = minuteur

    export.exportAsynchronously {
      DispatchQueue.main.async { [weak self] in
        minuteur.invalidate()
        self?.minuteur = nil
        switch export.status {
        case .completed:
          self?.canal.invokeMethod("progression", arguments: 1.0)
          result(destination)
        default:
          try? FileManager.default.removeItem(at: sortie)
          let erreur = export.error as NSError?
          // Une vidéo muette : le dire, plutôt que d'envoyer 700 Mo de silence.
          let code = erreur?.code == AVError.Code.noSourceTrack.rawValue ? "sans_audio" : "echec"
          result(
            FlutterError(
              code: code,
              message: erreur?.localizedDescription ?? "Extraction de la piste audio impossible.",
              details: nil
            )
          )
        }
      }
    }
  }
}
