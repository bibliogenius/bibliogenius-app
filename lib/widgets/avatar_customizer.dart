import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/avatar_config.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class AvatarCustomizer extends StatefulWidget {
  final AvatarConfig initialConfig;
  final Function(AvatarConfig) onConfigChanged;

  const AvatarCustomizer({
    super.key,
    required this.initialConfig,
    required this.onConfigChanged,
  });

  @override
  State<AvatarCustomizer> createState() => _AvatarCustomizerState();
}

class _AvatarCustomizerState extends State<AvatarCustomizer> {
  late AvatarConfig _config;

  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig;
  }

  void _updateConfig(AvatarConfig newConfig) {
    setState(() {
      _config = newConfig;
    });
    widget.onConfigChanged(newConfig);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final lang = themeProvider.locale.languageCode;
    final isGenie = _config.style == 'genie';
    final isHuman = ['man', 'woman', 'boy', 'girl', 'grandfather', 'grandmother'].contains(_config.style);
    
    return Column(
      children: [
        // Avatar Preview
        Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            color: isGenie 
                ? Color(int.parse('FF${_config.genieBackground ?? "fbbf24"}', radix: 16))
                : Colors.grey[100],
            shape: BoxShape.circle,
          ),
          child: ClipOval(
            child: isGenie
                ? Image.asset(
                    'assets/genie_mascot.jpg',
                    width: 200,
                    height: 200,
                    fit: BoxFit.cover,
                  )
                : Image.network(
                    _config.toUrl(size: 200, format: 'png'),
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Center(child: CircularProgressIndicator());
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(child: Icon(Icons.error));
                    },
                  ),
          ),
        ),
        const SizedBox(height: 24),

        // Customization Options
        Expanded(
          child: ListView(
            children: [
              // Style Selector (Human vs Genie)
              _buildSection(
                'Avatar Style',
                AvatarOptions.getAvatarStyles(lang),
                _config.style,
                (value) {
                  // Apply preset defaults if available
                  final preset = AvatarOptions.presets[value];
                  if (preset != null) {
                    _updateConfig(preset.copyWith(seed: _config.seed));
                  } else {
                    _updateConfig(_config.copyWith(style: value));
                  }
                },
              ),
              
              if (isGenie) ...[
                _buildColorSection(
                  'Background Color',
                  AvatarOptions.genieBackgrounds,
                  _config.genieBackground ?? 'fbbf24',
                  (value) => _updateConfig(_config.copyWith(genieBackground: value)),
                ),
                // Genie doesn't really have other customizable parts yet since it's a static image
                // We could add "Expression" if we had multiple images
              ] else if (isHuman) ...[
                _buildSection(
                  'Expression',
                  AvatarOptions.getMouthOptions(lang),
                  _config.mouth ?? 'smile',
                  (value) => _updateConfig(_config.copyWith(mouth: value)),
                ),
                _buildSection(
                  'Cheveux',
                  AvatarOptions.getHairStyles(lang),
                  _config.hairStyle ?? 'shortFlat',
                  (value) => _updateConfig(_config.copyWith(hairStyle: value)),
                ),
                _buildSection(
                  'Barbe/Moustache',
                  AvatarOptions.getFacialHairStyles(lang),
                  _config.facialHair ?? 'none',
                  (value) => _updateConfig(_config.copyWith(facialHair: value)),
                ),
                _buildColorSection(
                  'Couleur de peau',
                  AvatarOptions.getSkinColors(lang),
                  _config.skinColor ?? 'ffdbb4',
                  (value) => _updateConfig(_config.copyWith(skinColor: value)),
                ),
                _buildColorSection(
                  'Couleur des cheveux',
                  AvatarOptions.hairColors,
                  _config.hairColor ?? '4a312c',
                  (value) => _updateConfig(_config.copyWith(hairColor: value)),
                ),
                _buildSection(
                  'Accessoires',
                  AvatarOptions.getAccessoriesOptions(lang),
                  _config.accessories ?? 'none',
                  (value) => _updateConfig(_config.copyWith(accessories: value)),
                ),
                _buildSection(
                  'Vêtements',
                  AvatarOptions.getClothingOptions(lang),
                  _config.clothing ?? 'hoodie',
                  (value) => _updateConfig(_config.copyWith(clothing: value)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSection(
    String title,
    Map<String, String> options,
    String currentValue,
    Function(String) onChanged,
  ) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: options.entries.map((entry) {
                final isSelected = entry.key == currentValue;
                return ChoiceChip(
                  label: Text(entry.value),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) onChanged(entry.key);
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorSection(
    String title,
    Map<String, String> colors,
    String currentValue,
    Function(String) onChanged,
  ) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: colors.entries.map((entry) {
                final isSelected = entry.key == currentValue;
                return GestureDetector(
                  onTap: () => onChanged(entry.key),
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Color(int.parse('FF${entry.key}', radix: 16)),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.blue : Colors.grey[300]!,
                        width: isSelected ? 3 : 1,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
