// Premier lancement : expliquer, puis lever le seul vrai obstacle — la clé.
//
// Sans cet écran, l'app s'ouvre sur un bouton micro et un message d'erreur au
// premier traitement (« configure d'abord les services IA »). Le nouvel
// utilisateur doit alors deviner qu'il lui faut une clé Google, où la trouver,
// et laquelle des trois cases remplir. C'est là que la plupart s'arrêtent.
//
// On propose donc d'abord de **voir un exemple** — rien à configurer, et le
// testeur de l'App Store peut juger l'app sans clé — puis, pour de bon, un
// bouton qui ouvre la bonne page Google et un champ qui vérifie ce qui est
// collé avant d'accepter.

import 'package:flutter/material.dart';

import '../cle_api.dart';
import '../consentement.dart';
import '../etat.dart';
import '../exemple.dart';
import '../theme.dart';
import 'consentement_ia.dart';

class EcranBienvenue extends StatefulWidget {
  const EcranBienvenue({super.key});

  @override
  State<EcranBienvenue> createState() => _EcranBienvenueState();
}

class _EcranBienvenueState extends State<EcranBienvenue> {
  final etat = EtatApp.instance;
  final _cle = TextEditingController();
  bool _etapeCle = false;
  bool _ouvertureEchouee = false;

  @override
  void initState() {
    super.initState();
    _cle.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _cle.dispose();
    super.dispose();
  }

  /// [idOuvrir] : fiche que l'écran d'accueil doit ouvrir dans la foulée.
  Future<void> _terminer([String? idOuvrir]) async {
    etat.reglages.accueilVu = true;
    await etat.reglages.enregistrer();
    if (mounted) Navigator.pop(context, idOuvrir);
  }

  Future<void> _voirExemple() async {
    // L'accord d'envoi est demandé ici, sur le chemin que tout le monde prend,
    // et pas seulement devant le bouton « Transcrire & traduire » : la khoutba
    // d'exemple arrive déjà traitée, personne n'appuie sur « Retraiter », et
    // l'écran restait donc invisible — y compris pour le testeur d'Apple, qui
    // a refusé la 1.0 (4) faute de l'avoir rencontré.
    etat.reglages.demo = true;
    if (!await demanderConsentementIA(context, etat.reglages)) {
      etat.reglages.demo = false;
      return;
    }
    // La fiche est créée avant de fermer : on enchaîne directement sur une
    // khoutba traitée, au lieu de renvoyer sur une liste vide.
    final rec = await creerExemple();
    await etat.rafraichir();
    await _terminer(rec.id);
  }

  /// Accord pour le parcours « pour de vrai », qui mène toujours à Gemini.
  ///
  /// L'accord n'est pas mémorisé ici : les réglages ne portent pas encore le
  /// service, et la signature enregistrée serait celle d'une configuration
  /// vide. Il l'est à l'enregistrement de la clé, juste après.
  Future<void> _versEtapeCle() async {
    final accepte = await demanderConsentementIA(
      context,
      etat.reglages,
      destinatairesForces: [destinatairesConnus['gemini']!],
      memoriser: false,
    );
    if (accepte && mounted) setState(() => _etapeCle = true);
  }

  Future<void> _enregistrerCle() async {
    final r = etat.reglages;
    // Une clé Gemini suffit pour les deux étapes : on évite à l'utilisateur
    // d'avoir à comprendre la différence entre transcription et traduction.
    r.stt = 'gemini';
    r.llm = 'gemini';
    r.demo = false;
    await r.definirCle('gemini', _cle.text);
    // Maintenant seulement la signature correspond à ce qui a été accepté à
    // l'écran précédent : Google Gemini, pour la transcription et la rédaction.
    await r.accorderConsentementIA();
    await _terminer();
  }

  Future<void> _coller() async {
    final texte = await pressePapiers();
    if (texte.isNotEmpty) _cle.text = texte;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // Les deux pages placent leurs boutons en bas d'un grand écran, mais
        // sur un iPhone SE le contenu ne tient pas : il doit alors défiler.
        // Sans ça, le tout premier écran de l'app débordait de 203 pixels.
        child: LayoutBuilder(
          builder: (context, contraintes) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: contraintes.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: _etapeCle ? _pageCle(context) : _pagePresentation(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ présentation

  Widget _pagePresentation(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        const Spacer(),
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Image.asset('assets/logo.png', width: 92, height: 92),
        ),
        const SizedBox(height: 18),
        Text('Khoutba',
            style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Text(
          'Enregistre le prêche du vendredi. De retour chez toi, '
          'retrouve-le en français.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: theme.hintColor, height: 1.5),
        ),
        const SizedBox(height: 28),
        const _Etape(Icons.mic_none, 'Enregistre à la mosquée',
            'Même écran éteint, téléphone dans la poche.'),
        const _Etape(Icons.translate, 'Transcrit et traduit',
            "Le texte arabe intégral, puis la traduction."),
        const _Etape(Icons.menu_book_outlined, 'Résume l’essentiel',
            'Points clés, versets et hadiths cités, conseils.'),
        const Spacer(),
        Text(
          'Tout reste sur ton téléphone. L’audio n’est envoyé qu’au service '
          'd’IA que tu choisis, au moment du traitement.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: theme.hintColor, height: 1.5),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _voirExemple,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
            child: const Text('Voir un exemple'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _versEtapeCle,
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
            child: const Text('Commencer pour de vrai'),
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------- clé

  Widget _pageCle(BuildContext context) {
    final theme = Theme.of(context);
    final saisie = _cle.text.trim();
    final valide = clePlausible('gemini', saisie);
    // Avertissement seulement : Google est déjà passé de « AIza » à « AQ. »,
    // et refuser sur le préfixe bloquait des clés parfaitement valides.
    final inattendue = valide && cleInattendue('gemini', saisie);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => setState(() => _etapeCle = false),
          ),
        ),
        const SizedBox(height: 4),
        Text('Une clé Google, gratuite',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Text(
          'Khoutba confie l’audio à l’IA de Google pour le transcrire et le '
          'traduire. La clé sert à relier ces traitements à ton compte Google. '
          'L’offre gratuite couvre largement une khoutba par semaine.',
          style: TextStyle(fontSize: 14.5, color: theme.hintColor, height: 1.55),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () async {
              final ok = await ouvrirPageCle('gemini');
              if (!ok && mounted) setState(() => _ouvertureEchouee = true);
            },
            icon: const Icon(Icons.open_in_new, size: 18),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
            label: const Text('Ouvrir la page Google'),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _ouvertureEchouee
              ? 'Ouvre cette adresse dans ton navigateur :\n$urlCleGemini'
              : 'Sur la page : « Create API key », puis copie la clé.',
          style: TextStyle(fontSize: 12.5, color: theme.hintColor, height: 1.5),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _cle,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: 'Colle ta clé ici',
            hintText: 'AIza…',
            // Le retour est immédiat : une clé tronquée se voit tout de suite,
            // au lieu de produire une erreur 400 au premier traitement.
            suffixIcon: saisie.isEmpty
                ? IconButton(
                    icon: const Icon(Icons.content_paste),
                    tooltip: 'Coller',
                    onPressed: _coller,
                  )
                : Icon(
                    !valide
                        ? Icons.error_outline
                        : inattendue
                            ? Icons.help_outline
                            : Icons.check_circle,
                    color: valide ? accentTexte(context) : theme.colorScheme.error,
                  ),
          ),
        ),
        if (saisie.isNotEmpty && !valide) ...[
          const SizedBox(height: 8),
          Text(
            'Ça ne ressemble pas à une clé. Sur la page Google, utilise le '
            'bouton Copier à côté de la clé — celle affichée à l’écran est '
            'abrégée et ne fonctionnera pas.',
            style: TextStyle(fontSize: 12.5, color: theme.colorScheme.error, height: 1.5),
          ),
        ] else if (inattendue) ...[
          const SizedBox(height: 8),
          Text(
            'Cette clé n’a pas la forme habituelle d’une clé Google, mais tu '
            'peux continuer : elle sera essayée telle quelle.',
            style: TextStyle(fontSize: 12.5, color: theme.hintColor, height: 1.5),
          ),
        ],
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: valide ? _enregistrerCle : null,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
            child: const Text('Terminer'),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: TextButton(
            onPressed: _voirExemple,
            child: const Text('Voir plutôt un exemple'),
          ),
        ),
      ],
    );
  }
}

class _Etape extends StatelessWidget {
  final IconData icone;
  final String titre;
  final String detail;
  const _Etape(this.icone, this.titre, this.detail);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 22, color: accentTexte(context)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                Text(detail,
                    style: TextStyle(fontSize: 12.5, color: theme.hintColor, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
