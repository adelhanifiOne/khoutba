// Aide à l'obtention d'une clé API.
//
// C'est l'étape qui décide de tout pour un nouvel utilisateur : « va créer une
// clé sur aistudio.google.com » suffit à en perdre la plupart. On ouvre donc la
// bonne page d'un bouton, et on vérifie la forme de ce qui est collé avant de
// laisser partir une requête vouée à échouer.

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const urlCleGemini = 'https://aistudio.google.com/apikey';
const urlCleOpenAI = 'https://platform.openai.com/api-keys';
const urlCleClaude = 'https://console.anthropic.com/settings/keys';

String urlCle(String fournisseur) => switch (fournisseur) {
      'openai' => urlCleOpenAI,
      'anthropic' => urlCleClaude,
      _ => urlCleGemini,
    };

/// Vrai si la chaîne ressemble à une clé du fournisseur. Ne garantit pas
/// qu'elle soit valide — seulement qu'elle vaut la peine d'être essayée.
/// Évite le cas courant : une adresse e-mail, une URL, ou un collage à moitié
/// sélectionné, suivi d'une erreur 400 incompréhensible.
bool clePlausible(String fournisseur, String valeur) {
  final v = valeur.trim();
  if (v.contains(RegExp(r'\s')) || v.length < 20) return false;
  return switch (fournisseur) {
    'gemini' => v.startsWith('AIza') && v.length >= 35,
    'openai' => v.startsWith('sk-') && v.length >= 40,
    'anthropic' => v.startsWith('sk-ant-') && v.length >= 40,
    _ => true,
  };
}

/// Ouvre la page de création de clé dans le navigateur.
/// Renvoie faux si le système refuse — l'appelant affiche alors l'adresse.
Future<bool> ouvrirPageCle(String fournisseur) async {
  try {
    return await launchUrl(
      Uri.parse(urlCle(fournisseur)),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}

/// Contenu texte du presse-papiers, vide s'il est inaccessible ou vide.
Future<String> pressePapiers() async {
  try {
    return (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim() ?? '';
  } catch (_) {
    return '';
  }
}
