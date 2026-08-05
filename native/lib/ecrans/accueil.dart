// Écran d'accueil : bouton d'enregistrement et liste des khoutbas.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../enregistreur.dart';
import '../etat.dart';
import '../extraction_audio.dart';
import '../import_media.dart';
import '../modeles.dart';
import '../theme.dart';
import 'detail.dart';
import 'reglages_ecran.dart';

String formaterDuree(int secondes) {
  final s = math.max(0, secondes);
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  final mm = m.toString().padLeft(2, '0'), ss = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
}

String formaterDate(DateTime d, {bool avecHeure = true}) {
  final f = DateFormat(avecHeure ? "EEEE d MMMM 'à' HH:mm" : 'EEEE d MMMM', 'fr_FR');
  final t = f.format(d);
  return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
}

class EcranAccueil extends StatefulWidget {
  const EcranAccueil({super.key});

  @override
  State<EcranAccueil> createState() => _EcranAccueilState();
}

class _EcranAccueilState extends State<EcranAccueil> {
  final etat = EtatApp.instance;
  bool _demarrageAnnonce = false;

  @override
  void initState() {
    super.initState();
    etat.enregistreur.onArretAuto = _terminer;
  }

  /// Appelé une fois le chargement terminé — pas au premier frame : à ce
  /// moment-là `initialiser()` n'a pas encore fini et il n'y a rien à dire.
  void _signalerDemarrage() {
    if (!mounted) return;
    if (etat.messageRecuperation != null) {
      etat.messageRecuperation = null;
      _message('Un enregistrement interrompu a été récupéré ✓');
      return;
    }
    if (etat.octetsLiberes >= 50 * 1024 * 1024) {
      final rendus = tailleLisible(etat.octetsLiberes);
      etat.octetsLiberes = 0;
      _message('$rendus rendus au téléphone (fichiers d’imports abandonnés).');
    }
  }

  void _message(String texte) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texte)));
  }

  Future<void> _demarrer() async {
    final enr = etat.enregistreur;
    if (enr.actif) return;
    if (!await enr.permissionMicro()) {
      _message("Accès au micro refusé. Autorise-le dans les réglages du téléphone.");
      return;
    }
    // Android 13+ : la notification est requise pour le service au premier plan.
    if (Platform.isAndroid) {
      final statut = await Permission.notification.status;
      if (statut.isDenied) await Permission.notification.request();
    }
    try {
      await enr.demarrer();
      if (mounted) setState(() {});
    } on ErreurEnregistrement catch (e) {
      _message(e.message);
    }
  }

  Future<void> _terminer() async {
    final rec = await etat.enregistreur.arreter();
    await etat.rafraichir();
    if (!mounted) return;
    setState(() {});
    if (rec == null) {
      _message('Enregistrement vide.');
      return;
    }
    _message('Enregistrement sauvegardé ✓');
    _ouvrir(rec);
  }

  Future<void> _annuler() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Abandonner cet enregistrement ?'),
        content: const Text('Le fichier sera supprimé définitivement.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Continuer')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Abandonner')),
        ],
      ),
    );
    if (ok != true) return;
    await etat.enregistreur.annuler();
    if (mounted) setState(() {});
  }

  void _ouvrir(Enregistrement rec) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EcranDetail(idEnregistrement: rec.id)),
    ).then((_) => mounted ? setState(() {}) : null);
  }

  // ------------------------------------------------------------------ import

  /// Propose les deux sources : l'app Fichiers ne montre pas les vidéos de la
  /// galerie sur iPhone, et inversement.
  Future<void> _importer() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Fichiers'),
              subtitle: const Text('Audio ou vidéo — dictaphone, WhatsApp, iCloud…'),
              onTap: () => Navigator.pop(c, 'fichiers'),
            ),
            ListTile(
              leading: const Icon(Icons.perm_media_outlined),
              title: const Text('Galerie'),
              subtitle: const Text('Une vidéo filmée avec le téléphone'),
              onTap: () => Navigator.pop(c, 'galerie'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final navigateur = Navigator.of(context, rootNavigator: true);
    // Le dialogue est le seul auditeur et se retire tout seul : pas de dispose,
    // qui casserait la fermeture animée.
    final avancement = ValueNotifier<({String libelle, double? progression})>(
      (libelle: 'Préparation…', progression: null),
    );
    var dialogueOuvert = false;

    void fermerDialogue() {
      if (!dialogueOuvert) return;
      dialogueOuvert = false;
      navigateur.pop();
    }

    try {
      final fichier = source == 'galerie'
          ? await choisirVideoGalerie()
          : await choisirDansFichiers();
      if (fichier == null || !mounted) return; // annulé

      // Isoler la piste sonore d'une vidéo prend quelques dizaines de secondes :
      // sans progression affichée, l'app a l'air plantée.
      dialogueOuvert = true;
      unawaited(showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _DialogueImport(avancement: avancement),
      ));

      final resultat = await importer(
        fichier,
        onProgression: (etape, p) =>
            avancement.value = (libelle: etape.libelle, progression: p),
      );
      fermerDialogue(); // avant d'ouvrir la fiche, sinon c'est elle qu'on ferme
      await etat.rafraichir();
      if (!mounted) return;
      setState(() {});
      _message(resultat.videoEntiere
          ? "Vidéo importée — piste audio non extraite, l'envoi sera plus lourd."
          : 'Fichier importé ✓');
      _ouvrir(resultat.enregistrement);
    } on ErreurImport catch (e) {
      fermerDialogue();
      _message(e.message);
    } on ErreurExtraction catch (e) {
      fermerDialogue();
      _message(e.message);
    } catch (e) {
      fermerDialogue();
      _message("Import impossible : $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([etat, etat.enregistreur, etat.reglages]),
      builder: (context, _) {
        final enr = etat.enregistreur;
        if (!etat.chargement && !_demarrageAnnonce) {
          _demarrageAnnonce = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => _signalerDemarrage());
        }
        return Scaffold(
          body: SafeArea(
            child: Stack(
              children: [
                _contenu(context),
                if (enr.actif) _voileEnregistrement(context),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _contenu(BuildContext context) {
    final theme = Theme.of(context);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _entete(context)),
        if (etat.reglages.demo)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Couleurs.or.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('Mode démo actif — les textes générés sont fictifs.'),
              ),
            ),
          ),
        SliverToBoxAdapter(child: _boutonMicro(context)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text('Mes khoutbas',
                style: theme.textTheme.titleSmall?.copyWith(color: theme.hintColor)),
          ),
        ),
        if (etat.chargement)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (etat.enregistrements.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                "Aucun enregistrement pour l'instant.\nVendredi prochain, in cha Allah 🌙",
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.hintColor, height: 1.6),
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: etat.enregistrements.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: _carte(context, etat.enregistrements[i]),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Text(
              "Tout reste sur ton téléphone. L'audio n'est envoyé qu'au service d'IA "
              "que tu choisis, au moment du traitement.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: theme.hintColor),
            ),
          ),
        ),
      ],
    );
  }

  Widget _entete(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset('assets/logo.png', width: 44, height: 44),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Khoutba', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
                Text('Enregistre, comprends, retiens.',
                    style: TextStyle(fontSize: 12.5, color: theme.hintColor)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Réglages',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EcranReglages()),
            ).then((_) => mounted ? setState(() {}) : null),
          ),
        ],
      ),
    );
  }

  Widget _boutonMicro(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          GestureDetector(
            onTap: _demarrer,
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [Couleurs.accentSombre, Couleurs.accentFonce],
                  center: Alignment(-0.3, -0.4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Couleurs.accent.withValues(alpha: 0.4),
                    blurRadius: 22,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(Icons.mic, color: Colors.white, size: 40),
            ),
          ),
          const SizedBox(height: 12),
          Text('Appuie pour enregistrer le prêche',
              style: TextStyle(color: Theme.of(context).hintColor)),
          const SizedBox(height: 2),
          TextButton.icon(
            onPressed: _importer,
            icon: const Icon(Icons.file_upload_outlined, size: 18),
            label: const Text('ou importer un audio / une vidéo'),
            style: TextButton.styleFrom(foregroundColor: accentTexte(context)),
          ),
        ],
      ),
    );
  }

  Widget _carte(BuildContext context, Enregistrement rec) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _ouvrir(rec),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rec.titre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${formaterDate(rec.creeLe)} · ${formaterDuree(rec.dureeSecondes)}',
                      style: TextStyle(fontSize: 12.5, color: theme.hintColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              BadgeStatut(statut: rec.statut),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------- panneau d'enregistrement

  Widget _voileEnregistrement(BuildContext context) {
    final enr = etat.enregistreur;
    final theme = Theme.of(context);
    return Positioned.fill(
      child: Container(
        color: theme.scaffoldBackgroundColor.withValues(alpha: 0.94),
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _PointRouge(),
                  const SizedBox(height: 10),
                  const Text('Enregistrement en cours',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    formaterDuree(enr.duree.inSeconds),
                    style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w300),
                  ),
                  SizedBox(
                    height: 52,
                    child: CustomPaint(
                      size: const Size(double.infinity, 52),
                      painter: _VuMetre(niveau: enr.niveau, couleur: theme.colorScheme.primary),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    Platform.isAndroid
                        ? "Tu peux éteindre l'écran et ranger le téléphone :\nl'enregistrement continue."
                        : "Tu peux verrouiller l'écran :\nl'enregistrement continue.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: theme.hintColor, height: 1.5),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton(onPressed: _annuler, child: const Text('Annuler')),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => enr.enPause ? enr.reprendre() : enr.pause(),
                        child: Text(enr.enPause ? 'Reprendre' : 'Pause'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC73A2E)),
                        onPressed: _terminer,
                        child: const Text('Terminer'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Attente de l'import : étape en cours et progression quand elle est connue.
class _DialogueImport extends StatelessWidget {
  final ValueListenable<({String libelle, double? progression})> avancement;
  const _DialogueImport({required this.avancement});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false, // l'extraction continue de toute façon : ne pas la masquer
      child: AlertDialog(
        content: ValueListenableBuilder(
          valueListenable: avancement,
          builder: (context, v, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: v.progression, borderRadius: BorderRadius.circular(4)),
              const SizedBox(height: 18),
              Text(v.libelle, textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(
                v.progression == null ? '' : '${(v.progression! * 100).round()} %',
                style: TextStyle(color: theme.hintColor, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BadgeStatut extends StatelessWidget {
  final Statut statut;
  const BadgeStatut({super.key, required this.statut});

  @override
  Widget build(BuildContext context) {
    final sombre = Theme.of(context).brightness == Brightness.dark;
    late String libelle;
    late Color couleur;
    switch (statut) {
      case Statut.pret:
        libelle = 'À traiter';
        couleur = Theme.of(context).hintColor;
      case Statut.transcription:
      case Statut.traduction:
      case Statut.synthese:
        libelle = 'En cours…';
        couleur = accentTexte(context); // lisible en petit, y compris sur fond sombre
      case Statut.transcrit:
        libelle = 'Transcrit';
        couleur = orLisible(context);
      case Statut.traduit:
        libelle = 'Traduit';
        couleur = orLisible(context);
      case Statut.termine:
        libelle = 'Terminé';
        couleur = accentTexte(context);
      case Statut.erreur:
        libelle = 'Erreur';
        couleur = sombre ? Couleurs.rougeSombre : Couleurs.rouge;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        libelle,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: couleur),
      ),
    );
  }
}

class _PointRouge extends StatefulWidget {
  const _PointRouge();

  @override
  State<_PointRouge> createState() => _PointRougeState();
}

class _PointRougeState extends State<_PointRouge> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: 1, end: 0.25).animate(_ctrl),
        child: Container(
          width: 12,
          height: 12,
          decoration: const BoxDecoration(color: Color(0xFFDD3333), shape: BoxShape.circle),
        ),
      );
}

/// Petit vu-mètre : historique glissant du niveau sonore.
class _VuMetre extends CustomPainter {
  final double niveau;
  final Color couleur;
  static final List<double> _historique = List.filled(48, 0.02, growable: true);

  _VuMetre({required this.niveau, required this.couleur}) {
    _historique.add(niveau.clamp(0.0, 1.0));
    if (_historique.length > 48) _historique.removeAt(0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final peinture = Paint()..color = couleur;
    final largeur = size.width / _historique.length;
    for (var i = 0; i < _historique.length; i++) {
      final h = math.max(3.0, _historique[i] * size.height);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(i * largeur + largeur * 0.2, (size.height - h) / 2, largeur * 0.6, h),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, peinture);
    }
  }

  @override
  bool shouldRepaint(covariant _VuMetre ancien) => true;
}
