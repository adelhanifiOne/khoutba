// Écran des réglages : services IA, clés API, langue, stockage.

import 'package:flutter/material.dart';

import '../etat.dart';
import '../extraction_audio.dart';
import '../fournisseurs.dart';
import '../import_media.dart' show tailleLisible;
import '../stockage.dart';

class EcranReglages extends StatefulWidget {
  const EcranReglages({super.key});

  @override
  State<EcranReglages> createState() => _EcranReglagesState();
}

class _EcranReglagesState extends State<EcranReglages> {
  final etat = EtatApp.instance;
  List<ModeleGemini> _modelesGemini = [];
  String _stockage = '—';

  @override
  void initState() {
    super.initState();
    _chargerModelesGemini();
    _calculerStockage();
  }

  Future<void> _calculerStockage() async {
    final octets = await Stockage.tailleUtilisee();
    final libre = await espaceLibre();
    if (!mounted) return;
    // La place restante à côté : c'est elle qui décide si un import passera.
    setState(() => _stockage = libre == null
        ? tailleLisible(octets)
        : '${tailleLisible(octets)} · ${tailleLisible(libre)} libres');
  }

  /// Liste les modèles Gemini réellement accessibles avec la clé saisie.
  Future<void> _chargerModelesGemini() async {
    final cle = etat.reglages.cles['gemini'] ?? '';
    if (cle.isEmpty) {
      if (mounted) setState(() => _modelesGemini = []);
      return;
    }
    try {
      final liste = await ClientGemini(cle).listerModeles();
      if (mounted) setState(() => _modelesGemini = liste);
    } catch (_) {
      // Silencieux : le choix automatique fonctionne quand même.
    }
  }

  Future<void> _saisirCle(String nom, String libelle, String aide) async {
    final ctrl = TextEditingController(text: etat.reglages.cles[nom] ?? '');
    var visible = false;
    final valeur = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, majEtat) => AlertDialog(
          title: Text(libelle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(aide, style: TextStyle(fontSize: 12.5, color: Theme.of(c).hintColor)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                obscureText: !visible,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: 'Colle ta clé ici',
                  suffixIcon: IconButton(
                    icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => majEtat(() => visible = !visible),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
            TextButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (valeur == null) return;
    await etat.reglages.definirCle(nom, valeur);
    if (nom == 'gemini') await _chargerModelesGemini();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final r = etat.reglages;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          _bloc(
            titre: 'Services IA',
            explication:
                "L'audio est envoyé au service choisi uniquement quand tu lances le traitement. "
                'Une seule clé Gemini suffit pour tout (offre gratuite).',
            enfants: [
              _menu(
                'Transcription (audio → arabe)',
                r.stt,
                const {'': '— choisir —', 'gemini': 'Gemini', 'openai': 'OpenAI Whisper'},
                (v) async {
                  r.stt = v;
                  await r.enregistrer();
                  setState(() {});
                },
              ),
              _menu(
                'Traduction & résumé',
                r.llm,
                const {
                  '': '— choisir —',
                  'gemini': 'Gemini',
                  'anthropic': 'Claude',
                  'openai': 'OpenAI (GPT)',
                },
                (v) async {
                  r.llm = v;
                  await r.enregistrer();
                  setState(() {});
                },
              ),
              if (r.llm == 'anthropic')
                _menu('Modèle Claude', r.modeleClaude, choixModelesClaude, (v) async {
                  r.modeleClaude = v;
                  await r.enregistrer();
                  setState(() {});
                }),
              if (r.utiliseGemini)
                _menu(
                  'Modèle Gemini',
                  r.modeleGemini,
                  {
                    '': _modelesGemini.isEmpty
                        ? 'Automatique (recommandé)'
                        : 'Automatique — ${_modelesGemini.first.id}',
                    for (final m in _modelesGemini) m.id: m.id,
                  },
                  (v) async {
                    r.modeleGemini = v;
                    await r.enregistrer();
                    setState(() {});
                  },
                ),
              _menu('Langue des résultats', r.langue, const {'fr': 'Français', 'en': 'English'},
                  (v) async {
                r.langue = v;
                await r.enregistrer();
                setState(() {});
              }),
            ],
          ),
          _bloc(
            titre: 'Clés API',
            explication: 'Stockées uniquement sur cet appareil (trousseau sécurisé).',
            enfants: [
              _ligneCle('gemini', 'Clé Gemini', 'aistudio.google.com/apikey — gratuit'),
              _ligneCle('openai', 'Clé OpenAI', 'platform.openai.com/api-keys'),
              _ligneCle('anthropic', 'Clé Anthropic', 'console.anthropic.com'),
            ],
          ),
          _bloc(
            titre: 'Divers',
            enfants: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mode démo', style: TextStyle(fontSize: 14.5)),
                subtitle: const Text('Essayer sans clé, avec des textes fictifs',
                    style: TextStyle(fontSize: 12.5)),
                value: r.demo,
                onChanged: (v) async {
                  r.demo = v;
                  await r.enregistrer();
                  setState(() {});
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Stockage utilisé', style: TextStyle(fontSize: 14.5)),
                trailing: Text(_stockage, style: TextStyle(color: theme.hintColor)),
              ),
              const SizedBox(height: 4),
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                onPressed: _toutSupprimer,
                child: const Text('Supprimer tous les enregistrements'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Khoutba — application locale, aucun serveur.\nQu\'Allah agrée vos vendredis 🤲',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: theme.hintColor, height: 1.6),
          ),
        ],
      ),
    );
  }

  Future<void> _toutSupprimer() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Tout supprimer ?'),
        content: const Text('Tous les enregistrements et leurs textes seront effacés définitivement.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Tout supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    await Stockage.toutSupprimer();
    await etat.rafraichir();
    await _calculerStockage();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tout a été supprimé.')));
    }
  }

  Widget _bloc({required String titre, String? explication, required List<Widget> enfants}) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titre, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
            if (explication != null) ...[
              const SizedBox(height: 4),
              Text(explication,
                  style: TextStyle(fontSize: 12.5, color: theme.hintColor, height: 1.4)),
            ],
            const SizedBox(height: 6),
            ...enfants,
          ],
        ),
      ),
    );
  }

  Widget _menu(String libelle, String valeur, Map<String, String> choix, ValueChanged<String> onChange) {
    final valeurSure = choix.containsKey(valeur) ? valeur : choix.keys.first;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(libelle, style: const TextStyle(fontSize: 14.5))),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 175),
            child: DropdownButton<String>(
              value: valeurSure,
              isExpanded: true,
              underline: const SizedBox(),
              items: choix.entries
                  .map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value,
                            overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
                      ))
                  .toList(),
              onChanged: (v) => v == null ? null : onChange(v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ligneCle(String nom, String libelle, String aide) {
    final definie = (etat.reglages.cles[nom] ?? '').isNotEmpty;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(libelle, style: const TextStyle(fontSize: 14.5)),
      subtitle: Text(definie ? 'Clé enregistrée ✓' : aide, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _saisirCle(nom, libelle, aide),
    );
  }
}
