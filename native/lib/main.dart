// Khoutba — enregistre le prêche du vendredi, comprends-le en rentrant.
// Application locale : enregistrements et clés API restent sur le téléphone.

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'ecrans/accueil.dart';
import 'enregistreur.dart';
import 'etat.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Sans ça, les dates en français (« Vendredi 25 juillet ») lèvent une
  // exception : les symboles de la locale doivent être chargés explicitement.
  await initializeDateFormatting('fr_FR', null);
  Enregistreur.initialiserService();
  runApp(const AppKhoutba());
}

class AppKhoutba extends StatefulWidget {
  const AppKhoutba({super.key});

  @override
  State<AppKhoutba> createState() => _AppKhoutbaState();
}

class _AppKhoutbaState extends State<AppKhoutba> {
  @override
  void initState() {
    super.initState();
    EtatApp.instance.initialiser();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Khoutba',
      debugShowCheckedModeBanner: false,
      theme: themeClair(),
      darkTheme: themeSombre(),
      themeMode: ThemeMode.system,
      home: const EcranAccueil(),
    );
  }
}
