import 'package:flutter/material.dart';
import '../widgets/genie_app_bar.dart';
import '../services/translation_service.dart';

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final List<bool> _isExpanded = List.generate(6, (_) => false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GenieAppBar(title: TranslationService.translate(context, 'help_title')),
      body: SingleChildScrollView(
        child: ExpansionPanelList(
          expansionCallback: (int index, bool isExpanded) {
            setState(() {
              _isExpanded[index] = !_isExpanded[index];
            });
          },
          children: [
            _buildHelpPanel(
              context,
              0,
              TranslationService.translate(context, 'help_topic_add_book'),
              TranslationService.translate(context, 'help_desc_add_book'),
              Icons.add_circle_outline,
            ),
            _buildHelpPanel(
              context,
              1,
              TranslationService.translate(context, 'help_topic_lend'),
              TranslationService.translate(context, 'help_desc_lend'),
              Icons.import_contacts,
            ),
            _buildHelpPanel(
              context,
              2,
              TranslationService.translate(context, 'help_topic_connect'),
              TranslationService.translate(context, 'help_desc_connect'),
              Icons.qr_code,
            ),
            _buildHelpPanel(
              context,
              3,
              'Comment gérer mes contacts ?',
              'Allez dans "Contacts" pour ajouter des amis ou bibliothèques. Vous pouvez ajouter des emprunteurs (qui peuvent emprunter vos livres) ou des bibliothèques (dont vous pouvez consulter le catalogue).',
              Icons.contacts,
            ),
            _buildHelpPanel(
              context,
              4,
              'Comment explorer le réseau ?',
              'La section "Réseau de bibliothèques" vous permet de découvrir et consulter les catalogues de bibliothèques que vous avez ajoutées. Vous pouvez y faire des demandes d\'emprunt.',
              Icons.cloud_sync,
            ),
            _buildHelpPanel(
              context,
              5,
              'Comment gérer mes demandes ?',
              'Dans "Demandes", vous pouvez voir toutes les demandes d\'emprunt entrantes (de personnes qui veulent emprunter vos livres) et sortantes (vos demandes vers d\'autres bibliothèques). Acceptez, refusez, ou marquez comme retournés.',
              Icons.swap_horiz,
            ),
          ],
        ),
      ),
    );
  }

  ExpansionPanel _buildHelpPanel(
    BuildContext context,
    int index,
    String title,
    String description,
    IconData icon,
  ) {
    return ExpansionPanel(
      isExpanded: _isExpanded[index],
      headerBuilder: (BuildContext context, bool isExpanded) {
        return ListTile(
          leading: Icon(icon, color: Theme.of(context).primaryColor),
          title: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        );
      },
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          description,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
