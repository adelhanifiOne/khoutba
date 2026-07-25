// Réglages de l'app. Les clés API vont dans le trousseau iOS / keystore
// Android (flutter_secure_storage), le reste dans les préférences.

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fournisseurs.dart';

class Reglages extends ChangeNotifier {
  static const _stockageSecurise = FlutterSecureStorage();

  String stt = '';           // '' | gemini | openai
  String llm = '';           // '' | gemini | openai | anthropic
  String modeleClaude = ModelesParDefaut.claude;
  String modeleGemini = '';  // '' = choix automatique du meilleur disponible
  String langue = 'fr';      // fr | en
  bool demo = false;

  final Map<String, String> cles = {'gemini': '', 'openai': '', 'anthropic': ''};

  Future<void> charger() async {
    final prefs = await SharedPreferences.getInstance();
    stt = prefs.getString('stt') ?? '';
    llm = prefs.getString('llm') ?? '';
    modeleClaude = prefs.getString('modeleClaude') ?? ModelesParDefaut.claude;
    modeleGemini = prefs.getString('modeleGemini') ?? '';
    langue = prefs.getString('langue') ?? 'fr';
    demo = prefs.getBool('demo') ?? false;
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
}
