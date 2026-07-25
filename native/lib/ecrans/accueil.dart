// Écran d'accueil : bouton d'enregistrement et liste des khoutbas.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../enregistreur.dart';
import '../etat.dart';
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

  @override
  void initState() {
    super.initState();
    etat.enregistreur.onArretAuto = _terminer;
    WidgetsBinding.instance.addPostFrameCallback((_) => _signalerRecuperation());
  }

  void _signalerRecuperation() {
    if (etat.messageRecuperation == null || !mounted) return;
    etat.messageRecuperation = null;
    _message('Un enregistrement interrompu a été récupéré ✓');
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([etat, etat.enregistreur, etat.reglages]),
      builder: (context, _) {
        final enr = etat.enregistreur;
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
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Couleurs.accent, Couleurs.accentFonce],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.mic, color: Colors.white, size: 24),
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
                  colors: [Couleurs.accentClair, Couleurs.accentFonce],
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
        couleur = Theme.of(context).colorScheme.primary;
      case Statut.transcrit:
        libelle = 'Transcrit';
        couleur = sombre ? Couleurs.orSombre : Couleurs.or;
      case Statut.traduit:
        libelle = 'Traduit';
        couleur = sombre ? Couleurs.orSombre : Couleurs.or;
      case Statut.termine:
        libelle = 'Terminé';
        couleur = sombre ? Couleurs.accentClair : Couleurs.accent;
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
