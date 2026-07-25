// Enregistrement audio, y compris écran éteint et app en arrière-plan.
//
// C'est tout l'intérêt de la version native par rapport au site web :
//  - Android : un service au premier plan (type « microphone ») garde le
//    processus vivant ; une notification permanente informe l'utilisateur.
//  - iOS : le mode « audio » en arrière-plan (UIBackgroundModes dans
//    Info.plist) laisse la capture continuer écran verrouillé.
//
// L'audio est écrit directement dans un fichier .m4a au fil de l'enregistrement :
// si l'app est tuée, le fichier reste sur le disque et on le récupère au
// prochain lancement (voir `recupererSessionInterrompue`).

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'modeles.dart';
import 'stockage.dart';

/// Arrêt automatique de sécurité (une khoutba dure rarement plus d'une heure).
const dureeMax = Duration(hours: 3);

class ErreurEnregistrement implements Exception {
  final String message;
  ErreurEnregistrement(this.message);
  @override
  String toString() => message;
}

class Enregistreur extends ChangeNotifier {
  final AudioRecorder _recorder = AudioRecorder();

  bool actif = false;
  bool enPause = false;
  Duration duree = Duration.zero;
  double niveau = 0; // 0 → 1, pour le vu-mètre

  String? _id;
  String? _chemin;
  DateTime? _debutSegment;
  Duration _cumul = Duration.zero;
  Timer? _minuteur;
  StreamSubscription<Amplitude>? _abonnementNiveau;
  void Function()? onArretAuto;

  static const _cleSession = 'session_en_cours';

  Future<bool> permissionMicro() => _recorder.hasPermission();

  Future<void> demarrer() async {
    if (actif) return;
    if (!await _recorder.hasPermission()) {
      throw ErreurEnregistrement(
        "Accès au micro refusé. Autorise le micro pour Khoutba dans les réglages du téléphone.",
      );
    }

    _id = const Uuid().v4();
    _chemin = '${(await Stockage.dossierAudio()).path}/$_id.m4a';

    // Android : démarrer le service AVANT la capture, pour que le micro reste
    // autorisé quand l'écran s'éteint.
    await _demarrerServicePremierPlan();

    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 32000,   // ≈ 14 Mo par heure : suffisant pour la voix
          sampleRate: 44100,
          numChannels: 1,   // mono
          // La voix de l'imam vient de loin ou des haut-parleurs : on garde le
          // gain automatique, mais pas les filtres pensés pour la visio, qui
          // dégradent la parole lointaine.
          autoGain: true,
          echoCancel: false,
          noiseSuppress: false,
        ),
        path: _chemin!,
      );
    } catch (e) {
      await _arreterServicePremierPlan();
      throw ErreurEnregistrement("Impossible de démarrer l'enregistrement : $e");
    }

    // Trace de secours : permet de récupérer le fichier si l'app est tuée.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_cleSession, [_id!, _chemin!, DateTime.now().toIso8601String()]);

    actif = true;
    enPause = false;
    _cumul = Duration.zero;
    _debutSegment = DateTime.now();

    _minuteur = Timer.periodic(const Duration(milliseconds: 500), (_) {
      duree = _dureeCourante();
      if (duree >= dureeMax) {
        onArretAuto?.call();
        return;
      }
      notifyListeners();
    });

    _abonnementNiveau =
        _recorder.onAmplitudeChanged(const Duration(milliseconds: 200)).listen((a) {
      // `current` est en dBFS (≈ -60 silence → 0 saturation).
      final db = a.current.isFinite ? a.current : -60.0;
      niveau = enPause ? 0 : ((db + 50) / 50).clamp(0.0, 1.0);
      notifyListeners();
    });

    notifyListeners();
  }

  Duration _dureeCourante() {
    var d = _cumul;
    if (actif && !enPause && _debutSegment != null) {
      d += DateTime.now().difference(_debutSegment!);
    }
    return d;
  }

  Future<void> pause() async {
    if (!actif || enPause) return;
    _cumul = _dureeCourante();
    enPause = true;
    niveau = 0;
    await _recorder.pause();
    notifyListeners();
  }

  Future<void> reprendre() async {
    if (!actif || !enPause) return;
    enPause = false;
    _debutSegment = DateTime.now();
    await _recorder.resume();
    notifyListeners();
  }

  /// Termine l'enregistrement et renvoie la fiche sauvegardée.
  Future<Enregistrement?> arreter() async {
    if (!actif) return null;
    final secondes = _dureeCourante().inSeconds;
    final id = _id!;
    final chemin = _chemin!;

    await _nettoyer();
    try {
      await _recorder.stop();
    } catch (_) {
      // Même si l'arrêt se passe mal, le fichier écrit reste exploitable.
    }
    await _arreterServicePremierPlan();
    await _effacerTraceSession();

    final fichier = File(chemin);
    if (!await fichier.exists() || await fichier.length() < 1024) {
      if (await fichier.exists()) await fichier.delete();
      return null;
    }

    final rec = Enregistrement(
      id: id,
      titre: titreParDefaut(DateTime.now()),
      creeLe: DateTime.now(),
      cheminAudio: chemin,
      dureeSecondes: secondes,
    );
    await Stockage.sauver(rec);
    return rec;
  }

  /// Abandonne l'enregistrement en cours et supprime le fichier.
  Future<void> annuler() async {
    if (!actif) return;
    final chemin = _chemin;
    await _nettoyer();
    try {
      await _recorder.stop();
    } catch (_) {}
    await _arreterServicePremierPlan();
    await _effacerTraceSession();
    if (chemin != null) {
      final f = File(chemin);
      if (await f.exists()) await f.delete();
    }
  }

  Future<void> _nettoyer() async {
    actif = false;
    enPause = false;
    niveau = 0;
    _minuteur?.cancel();
    _minuteur = null;
    await _abonnementNiveau?.cancel();
    _abonnementNiveau = null;
    notifyListeners();
  }

  Future<void> _effacerTraceSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cleSession);
  }

  @override
  void dispose() {
    _minuteur?.cancel();
    _abonnementNiveau?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  // --------------------------------------------------- service au premier plan

  static void initialiserService() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'khoutba_enregistrement',
        channelName: 'Enregistrement en cours',
        channelDescription: "Affiché pendant l'enregistrement d'une khoutba.",
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,  // le processeur reste éveillé, écran éteint
        allowWifiLock: false,
      ),
    );
  }

  Future<void> _demarrerServicePremierPlan() async {
    if (!Platform.isAndroid) return; // iOS : géré par UIBackgroundModes audio
    try {
      if (await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.startService(
        serviceTypes: [ForegroundServiceTypes.microphone],
        notificationTitle: 'Khoutba — enregistrement en cours',
        notificationText: "Le prêche est enregistré, même écran éteint.",
      );
    } catch (_) {
      // Le service peut échouer (autorisation notifications refusée) :
      // l'enregistrement fonctionne quand même tant que l'app reste ouverte.
    }
  }

  Future<void> _arreterServicePremierPlan() async {
    if (!Platform.isAndroid) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {}
  }

  // ------------------------------------------------------------- récupération

  /// Après un arrêt brutal (batterie vide, app tuée), récupère le fichier
  /// laissé sur le disque et l'ajoute à la liste.
  static Future<Enregistrement?> recupererSessionInterrompue() async {
    final prefs = await SharedPreferences.getInstance();
    final trace = prefs.getStringList(_cleSession);
    if (trace == null || trace.length < 2) return null;
    await prefs.remove(_cleSession);

    final id = trace[0];
    final chemin = trace[1];
    final debut = trace.length > 2 ? DateTime.tryParse(trace[2]) : null;

    final fichier = File(chemin);
    if (!await fichier.exists() || await fichier.length() < 1024) return null;

    // Déjà enregistré dans l'index (arrêt normal mais trace non effacée) ?
    final existants = await Stockage.lister();
    if (existants.any((e) => e.id == id)) return null;

    final rec = Enregistrement(
      id: id,
      titre: 'Enregistrement récupéré',
      titrePerso: true,
      creeLe: debut ?? DateTime.now(),
      cheminAudio: chemin,
      // Durée réelle recalculée à l'ouverture de la fiche (lecteur audio).
      dureeSecondes: 0,
    );
    await Stockage.sauver(rec);
    return rec;
  }
}

String titreParDefaut(DateTime date) {
  const jours = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
  const mois = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
    'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'
  ];
  return 'Khoutba du ${jours[date.weekday - 1]} ${date.day} ${mois[date.month - 1]}';
}
