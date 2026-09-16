// Réglages de l'app. Les clés API vont dans le trousseau iOS / keystore
// Android (flutter_secure_storage), le reste dans les préférences.

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'consentement.dart';
import 'fournisseurs.dart';

class Reglages extends ChangeNotifier {
  static const _stockageSecurise = FlutterSecureStorage();

  String stt = '';           // '' | gemini | openai
  String llm = '';           // '' | gemini | openai | anthropic
  String modeleClaude = ModelesParDefaut.claude;
  String modeleGemini = '';  // '' = choix automatique du meilleur disponible
  String langue = 'fr';      // fr | en
  bool demo = false;
  bool accueilVu = false;    // l'écran de bienvenue ne se montre qu'une fois

  // Accord d'envoi vers les services d'IA (règles Apple 5.1.1(i) / 5.1.2(i)).
  // On mémorise *pour qui* l'accord a été donné, pas un simple oui : changer de
  // service change le destinataire, et l'accord doit alors être redemandé.
  String consentementIA = '';
  String consentementDate = ''; // ISO 8601, affiché dans les réglages

  final Map<String, String> cles = {'gemini': '', 'openai': '', 'anthropic': ''};

  Future<void> charger() async {
    final prefs = await SharedPreferences.getInstance();
    stt = prefs.getString('stt') ?? '';
    llm = prefs.getString('llm') ?? '';
    modeleClaude = prefs.getString('modeleClaude') ?? ModelesParDefaut.claude;
    modeleGemini = prefs.getString('modeleGemini') ?? '';
    langue = prefs.getString('langue') ?? 'fr';
    demo = prefs.getBool('demo') ?? false;
    accueilVu = prefs.getBool('accueilVu') ?? false;
    consentementIA = prefs.getString('consentementIA') ?? '';
    consentementDate = prefs.getString('consentementDate') ?? '';
    for (final nom in cles.keys) {
      try {
        cles[nom] = await _stockageSecurise.read(key: 'cle_$nom') ?? '';
      } catch (_) {
        cles[nom] = ''; // trousseau indisponible : on continue sans clé
      }
    }
    notifyListeners();
  }

  Future<void> enregistrer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('stt', stt);
    await prefs.setString('llm', llm);
    await prefs.setString('modeleClaude', modeleClaude);
    await prefs.setString('modeleGemini', modeleGemini);
    await prefs.setString('langue', langue);
    await prefs.setBool('demo', demo);
    await prefs.setBool('accueilVu', accueilVu);
    await prefs.setString('consentementIA', consentementIA);
    await prefs.setString('consentementDate', consentementDate);
    notifyListeners();
  }

  Future<void> definirCle(String nom, String valeur) async {
    cles[nom] = valeur.trim();
    try {
      if (valeur.trim().isEmpty) {
        await _stockageSecurise.delete(key: 'cle_$nom');
      } else {
        await _stockageSecurise.write(key: 'cle_$nom', value: valeur.trim());
      }
    } catch (_) {}
    if (nom == 'gemini') ClientGemini.reinitialiser();
    notifyListeners();
  }

  /// Vrai si un traitement peut être lancé (fournisseurs et clés en place).
  bool get pretPourTraitement {
    if (demo) return true;
    if (stt.isEmpty || llm.isEmpty) return false;
    return (cles[stt] ?? '').isNotEmpty && (cles[llm] ?? '').isNotEmpty;
  }

  bool get utiliseGemini => stt == 'gemini' || llm == 'gemini';

  /// Services qui recevront effectivement quelque chose lors d'un traitement.
  /// Vide en mode démo : rien ne sort de l'appareil.
  List<DestinataireIA> get destinatairesIA =>
      demo ? const [] : destinatairesPour(stt, llm);

  /// Empreinte de la configuration d'envoi actuelle.
  ///
  /// Le mode démo a la sienne pour que l'écran d'explication soit vu une fois
  /// même sans clé — c'est par là que passe le testeur d'Apple, et il doit
  /// pouvoir constater que l'app demande l'accord.
  String get signatureConsentement {
    if (demo) return 'demo';
    return signatureDestinataires(destinatairesIA.map((d) => d.id));
  }

  /// Vrai si l'utilisateur a déjà accepté d'envoyer à *ces* destinataires-là.
  bool get consentementIAValide {
    final signature = signatureConsentement;
    return signature.isNotEmpty && consentementIA == signature;
  }

  Future<void> accorderConsentementIA() async {
    consentementIA = signatureConsentement;
    consentementDate = DateTime.now().toIso8601String();
    await enregistrer();
  }

  Future<void> revoquerConsentementIA() async {
    consentementIA = '';
    consentementDate = '';
    await enregistrer();
  }
}
