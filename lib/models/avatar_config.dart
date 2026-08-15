import 'dart:convert';

class AvatarConfig {
  final String style; // 'avataaars', 'lorelei', 'adventurer', 'genie'
  final String? hairStyle;
  final String? facialHair;
  final String? facialHairColor;
  final String? skinColor;
  final String? hairColor;
  final String? accessories;
  final String? clothing;
  final String? clothingColor;
  final String? mouth; // Parameter for facial expression
  final String? eyes; // Parameter for eye type (default = open eyes)
  final String? eyebrows; // Parameter for eyebrows (default = default)

  // Genie-specific options
  final String? genieColor; // For genie avatar
  final String? genieBackground; // For genie avatar
  final String? genieExpression; // 'happy', 'excited', 'focused'

  final String seed;

  const AvatarConfig({
    this.style = 'avataaars',
    this.hairStyle,
    this.facialHair,
    this.facialHairColor,
    this.skinColor,
    this.hairColor,
    this.accessories,
    this.clothing,
    this.clothingColor,
    this.genieColor,
    this.genieBackground,
    this.genieExpression,
    this.mouth,
    this.eyes = 'default', // Default to open eyes
    this.eyebrows = 'default',
    required this.seed,
  });

  /// Returns true if this is the Genie mascot avatar (local asset)
  bool get isGenie => style == 'genie';

  /// Returns true if this avatar should use a local asset (currently only genie)
  bool get isAsset => isGenie;

  /// Returns the asset path if isAsset is true
  String get assetPath => 'assets/genie_mascot.jpg';

  // Generate DiceBear API URL or local asset path
  String toUrl({int size = 200, String format = 'png'}) {
    // For genie avatar, use local asset
    if (style == 'genie') {
      return 'assets/genie_mascot.jpg';
    }

    // Map presets to actual API styles
    String apiStyle = style;
    if ([
      'man',
      'woman',
      'boy',
      'girl',
      'grandfather',
      'grandmother',
    ].contains(style)) {
      apiStyle = 'avataaars';
    }

    // Common params
    final params = <String, String>{'seed': seed, 'size': size.toString()};

    // Robot specific mappings (bottts)
    if (apiStyle == 'bottts') {
      if (hairStyle != null) params['top'] = hairStyle!;
      if (skinColor != null) params['baseColor'] = skinColor!;
      if (mouth != null) params['mouth'] = mouth!;
      if (eyes != null) params['eyes'] = eyes!;
      // Robots support texture probability, but we can default to 100 if needed, usually just top/baseColor/mouth/eyes is enough.
      // Do NOT add human params like facialHair, clothing, etc.
    }
    // Initials specific mappings
    else if (apiStyle == 'initials') {
      // Initials only support seed, size, and basic colors (background)
      // We explicitly exclude physical attributes to avoid API errors
      if (genieColor != null) params['backgroundColor'] = genieColor!;
    }
    // Human mappings (avataaars, lorelei, adventurer)
    else {
      if (hairStyle != null) {
        if (hairStyle == 'none') {
          params['topProbability'] = '0';
        } else {
          params['top'] = hairStyle!;
          params['topProbability'] = '100';
        }
      }

      if (facialHair != null) {
        if (facialHair == 'none') {
          params['facialHairProbability'] = '0';
        } else {
          params['facialHair'] = facialHair!;
          params['facialHairProbability'] = '100';
        }
      }

      if (facialHairColor != null) params['facialHairColor'] = facialHairColor!;

      if (skinColor != null) params['skinColor'] = skinColor!;
      if (hairColor != null) params['hairColor'] = hairColor!;

      if (accessories != null && accessories != 'none') {
        params['accessories'] = accessories!;
        params['accessoriesProbability'] = '100';
      } else {
        // Default: no accessories unless explicitly selected
        params['accessoriesProbability'] = '0';
      }
      if (clothing != null) params['clothing'] = clothing!;
      if (clothingColor != null) params['clothingColor'] = clothingColor!;

      if (mouth != null) params['mouth'] = mouth!;
      if (eyes != null) params['eyes'] = eyes!;
      if (eyebrows != null) params['eyebrows'] = eyebrows!;
    }

    final queryString = params.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');

    // The style is encoded like every query parameter: a config parsed from a
    // hub profile or a peer record is remote data, and an unencoded style
    // would let it steer the path and the query string of the request. The
    // host itself is not reachable that way (the prefix is fixed), but there
    // is no reason to let a peer choose what we ask DiceBear for.
    return 'https://api.dicebear.com/7.x/'
        '${Uri.encodeComponent(apiStyle)}/$format?$queryString';
  }

  // Convert to JSON for storage
  Map<String, dynamic> toJson() => {
    'style': style,
    'hairStyle': hairStyle,
    'facialHair': facialHair,
    'facialHairColor': facialHairColor,
    'skinColor': skinColor,
    'hairColor': hairColor,
    'accessories': accessories,
    'clothing': clothing,
    'clothingColor': clothingColor,
    'genieColor': genieColor,
    'genieBackground': genieBackground,
    'genieExpression': genieExpression,
    'mouth': mouth,
    'eyes': eyes,
    'eyebrows': eyebrows,
    'seed': seed,
  };

  // Create from JSON
  factory AvatarConfig.fromJson(Map<String, dynamic> json) => AvatarConfig(
    style: json['style'] ?? 'avataaars',
    hairStyle: json['hairStyle'],
    facialHair: json['facialHair'],
    facialHairColor: json['facialHairColor'],
    skinColor: json['skinColor'],
    hairColor: json['hairColor'],
    accessories: json['accessories'],
    clothing: json['clothing'],
    clothingColor: json['clothingColor'],
    genieColor: json['genieColor'],
    genieBackground: json['genieBackground'],
    genieExpression: json['genieExpression'],
    mouth: json['mouth'],
    eyebrows: json['eyebrows'] ?? 'default',
    eyes: json['eyes'] ?? 'default',
    seed: json['seed'] ?? 'default',
  );

  /// Parse an `avatar_config` JSON string as stored on the hub profile, the
  /// peer record or SharedPreferences. Returns null when the string is absent,
  /// empty or not a valid config, so callers can fall back to initials.
  static AvatarConfig? tryParse(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      return AvatarConfig.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  // Create copy with changes
  AvatarConfig copyWith({
    String? style,
    String? hairStyle,
    String? facialHair,
    String? facialHairColor,
    String? skinColor,
    String? hairColor,
    String? accessories,
    String? clothing,
    String? clothingColor,
    String? genieColor,
    String? genieBackground,
    String? genieExpression,
    String? mouth,
    String? eyes,
    String? eyebrows,
    String? seed,
  }) => AvatarConfig(
    style: style ?? this.style,
    hairStyle: hairStyle ?? this.hairStyle,
    facialHair: facialHair ?? this.facialHair,
    facialHairColor: facialHairColor ?? this.facialHairColor,
    skinColor: skinColor ?? this.skinColor,
    hairColor: hairColor ?? this.hairColor,
    accessories: accessories ?? this.accessories,
    clothing: clothing ?? this.clothing,
    clothingColor: clothingColor ?? this.clothingColor,
    genieColor: genieColor ?? this.genieColor,
    genieBackground: genieBackground ?? this.genieBackground,
    genieExpression: genieExpression ?? this.genieExpression,
    mouth: mouth ?? this.mouth,
    eyes: eyes ?? this.eyes,
    eyebrows: eyebrows ?? this.eyebrows,
    seed: seed ?? this.seed,
  );

  // Default config - using neutral "initials" style instead of random human avatars
  static AvatarConfig get defaultConfig =>
      AvatarConfig(seed: 'bibliogenius', style: 'initials');
}

// Available options for customization
class AvatarOptions {
  static Map<String, String> getAvatarStyles(String lang) {
    if (lang == 'fr') {
      return {
        'initials': 'Initiales (Neutre)',
        'man': 'Homme',
        'woman': 'Femme',
        'boy': 'Garçon',
        'girl': 'Fille',
        'grandfather': 'Grand-père',
        'grandmother': 'Grand-mère',
        'bottts': 'Robot',
      };
    } else if (lang == 'es') {
      return {
        'initials': 'Iniciales (Neutro)',
        'man': 'Hombre',
        'woman': 'Mujer',
        'boy': 'Niño',
        'girl': 'Niña',
        'grandfather': 'Abuelo',
        'grandmother': 'Abuela',
        'bottts': 'Robot',
      };
    } else if (lang == 'de') {
      return {
        'initials': 'Initialen (Neutral)',
        'man': 'Mann',
        'woman': 'Frau',
        'boy': 'Junge',
        'girl': 'Mädchen',
        'grandfather': 'Großvater',
        'grandmother': 'Großmutter',
        'bottts': 'Roboter',
      };
    }
    return {
      'initials': 'Initials (Neutral)',
      'man': 'Man',
      'woman': 'Woman',
      'boy': 'Boy',
      'girl': 'Girl',
      'grandfather': 'Grandfather',
      'grandmother': 'Grandmother',
      'bottts': 'Robot',
    };
  }

  static Map<String, String> getMouthOptions(String lang) {
    if (lang == 'fr') {
      return {
        'twinkle': 'Sourire',
        'smile': 'Sourire léger',
        'default': 'Neutre',
        'tongue': 'Tirer la langue',
        'grimace': 'Grimace',
        'serious': 'Sérieux',
      };
    }
    return {
      'twinkle': 'Smile',
      'smile': 'Slight Smile',
      'default': 'Neutral',
      'tongue': 'Tongue Out',
      'grimace': 'Grimace',
      'serious': 'Serious',
    };
  }

  static Map<String, String> getEyebrowStyles(String lang) {
    if (lang == 'fr') {
      return {
        'default': 'Naturel',
        'defaultNatural': 'Naturel (Doux)',
        'upDown': 'Expressif',
        'upDownNatural': 'Expressif (Naturel)',
        'flatNatural': 'Plat / Calme',
        'raisedExcited': 'Joyeux / Surpris',
        'raisedExcitedNatural': 'Joyeux (Naturel)',
        'sadConcerned': 'Triste / Inquiet',
        'sadConcernedNatural': 'Triste (Naturel)',
        'angry': 'Fâché',
        'angryNatural': 'Fâché (Naturel)',
      };
    }
    return {
      'default': 'Natural',
      'defaultNatural': 'Natural (Soft)',
      'upDown': 'Expressive',
      'upDownNatural': 'Expressive (Natural)',
      'flatNatural': 'Flat / Calm',
      'raisedExcited': 'Happy / Surprised',
      'raisedExcitedNatural': 'Happy (Natural)',
      'sadConcerned': 'Sad / Concerned',
      'sadConcernedNatural': 'Sad (Natural)',
      'angry': 'Angry',
      'angryNatural': 'Angry (Natural)',
    };
  }

  static Map<String, String> getHairStyles(String lang) {
    if (lang == 'fr') {
      return {
        'none': 'Chauve',
        'shortFlat': 'Courts',
        'shortCurly': 'Courts bouclés',
        'longButNotTooLong': 'Longs',
        'bun': 'Chignon',
        'hijab': 'Hijab',
        'turban': 'Turban',
        'winterHat1': 'Bonnet (Pois)',
        'winterHat02': 'Bonnet',
        'winterHat03': 'Bonnet (Rayures)',
        'winterHat04': 'Bonnet (Rouge)',
        'hat': 'Chapeau',
      };
    }
    return {
      'none': 'Bald',
      'shortFlat': 'Short',
      'shortCurly': 'Short Curly',
      'longButNotTooLong': 'Long',
      'bun': 'Bun',
      'hijab': 'Hijab',
      'turban': 'Turban',
      'winterHat1': 'Winter Hat (Dots)',
      'winterHat02': 'Winter Hat',
      'winterHat03': 'Winter Hat (Stripes)',
      'winterHat04': 'Winter Hat (Red)',
      'hat': 'Hat',
    };
  }

  static Map<String, String> getFacialHairColors(String lang) {
    // DiceBear uses the same palette as hair
    return hairColors;
  }

  static Map<String, String> getFacialHairStyles(String lang) {
    if (lang == 'fr') {
      return {
        'none': 'Rasé',
        'moustacheFancy': 'Moustache',
        'beardLight': 'Barbe légère',
        'beardMedium': 'Barbe moyenne',
        'beardMajestic': 'Barbe complète',
      };
    }
    return {
      'none': 'Shaved',
      'moustacheFancy': 'Moustache',
      'beardLight': 'Light Beard',
      'beardMedium': 'Medium Beard',
      'beardMajestic': 'Full Beard',
    };
  }

  static Map<String, String> getSkinColors(String lang) {
    if (lang == 'fr') {
      return {
        'ffdbb4': 'Clair',
        'd08b5b': 'Medium',
        'ae5d29': 'Foncé',
        'f4c2be': 'Pâle',
        '614335': 'Très foncé',
      };
    }
    return {
      'ffdbb4': 'Light',
      'd08b5b': 'Medium',
      'ae5d29': 'Dark',
      'f4c2be': 'Pale',
      '614335': 'Very Dark',
    };
  }

  static Map<String, String> getAccessoriesOptions(String lang) {
    if (lang == 'fr') {
      return {
        'none': 'Aucun',
        'prescription01': 'Lunettes',
        'prescription02': 'Lunettes rondes',
        'round': 'Lunettes style',
        'sunglasses': 'Lunettes de soleil',
        'wayfarers': 'Lunettes larges',
      };
    }
    return {
      'none': 'None',
      'prescription01': 'Glasses',
      'prescription02': 'Round Glasses',
      'round': 'Stylish Glasses',
      'sunglasses': 'Sunglasses',
      'wayfarers': 'Wayfarers',
    };
  }

  static Map<String, String> getClothingOptions(String lang) {
    if (lang == 'fr') {
      return {
        'hoodie': 'Sweat à capuche',
        'shirtCrewNeck': 'Chemise',
        'overall': 'Salopette',
        'blazerAndShirt': 'Veste',
      };
    }
    return {
      'hoodie': 'Hoodie',
      'shirtCrewNeck': 'Shirt',
      'overall': 'Overalls',
      'blazerAndShirt': 'Blazer',
    };
  }

  static const Map<String, String> hairColors = {
    '000000': 'Noir',
    '3e2723': 'Brun', // Dark brown
    '795548': 'Châtain', // Brown
    'a0522d': 'Roux', // Sienna/Natural Red
    'e6cea8': 'Blond',
    '9e9e9e': 'Gris',
    'ffffff': 'Blanc',
  };

  // Genie-specific options
  static const Map<String, String> genieColors = {
    '2563eb': 'Bleu',
    '7c3aed': 'Violet',
    'ec4899': 'Rose',
    '10b981': 'Vert',
    'f59e0b': 'Orange',
  };

  // Robot Options (Bottts)
  static Map<String, String> getRobotAccessory(String lang) {
    // Maps to 'top' in DiceBear
    if (lang == 'fr') {
      return {
        'antenna': 'Antenne',
        'antennaCrooked': 'Antenne tordue',
        'bulb01': 'Ampoule',
        'glowingBulb01': 'Ampoule allumée',
        'horns': 'Cornes',
        'lights': 'Lumières',
        'pyramid': 'Pyramide',
        'radar': 'Radar',
      };
    }
    return {
      'antenna': 'Antenna',
      'antennaCrooked': 'Crooked Antenna',
      'bulb01': 'Bulb',
      'glowingBulb01': 'Glowing Bulb',
      'horns': 'Horns',
      'lights': 'Lights',
      'pyramid': 'Pyramid',
      'radar': 'Radar',
    };
  }

  static Map<String, String> getRobotEyes(String lang) {
    if (lang == 'fr') {
      return {
        'eva': 'Eva',
        'frame1': 'Ecran 1',
        'frame2': 'Ecran 2',
        'glow': 'Lueur',
        'happy': 'Joyeux',
        'hearts': 'Coeurs',
        'round': 'Ronds',
        'sensor': 'Capteur',
        'shade01': 'Lunettes de soleil',
      };
    }
    return {
      'eva': 'Eva',
      'frame1': 'Screen 1',
      'frame2': 'Screen 2',
      'glow': 'Glow',
      'happy': 'Happy',
      'hearts': 'Hearts',
      'round': 'Round',
      'sensor': 'Sensor',
      'shade01': 'Sunglass',
    };
  }

  static Map<String, String> getRobotMouths(String lang) {
    if (lang == 'fr') {
      return {
        'bite': 'Morsure',
        'diagram': 'Graphique',
        'grill01': 'Grille 1',
        'grill02': 'Grille 2',
        'smile01': 'Sourire 1',
        'smile02': 'Sourire 2',
        'square01': 'Carré 1',
        'square02': 'Carré 2',
      };
    }
    return {
      'bite': 'Bite',
      'diagram': 'Diagram',
      'grill01': 'Grill 1',
      'grill02': 'Grill 2',
      'smile01': 'Smile 1',
      'smile02': 'Smile 2',
      'square01': 'Square 1',
      'square02': 'Square 2',
    };
  }

  static const Map<String, String> robotColors = {
    'ffc107': 'Ambre',
    '2196f3': 'Bleu',
    '607d8b': 'Bleu Gris',
    '795548': 'Marron',
    '00bcd4': 'Cyan',
    'ff5722': 'Orange Foncé',
    '673ab7': 'Violet Foncé',
    '4caf50': 'Vert',
    '9e9e9e': 'Gris',
    '3f51b5': 'Indigo',
    '03a9f4': 'Bleu Clair',
    '8bc34a': 'Vert Clair',
    'cddc39': 'Citron',
    'ff9800': 'Orange',
    'e91e63': 'Rose',
    '9c27b0': 'Violet',
    'f44336': 'Rouge',
    '009688': 'Sarcelle',
    'ffeb3b': 'Jaune',
  };

  static const Map<String, String> genieBackgrounds = {
    'fbbf24': 'Jaune',
    '06b6d4': 'Cyan',
    'f97316': 'Orange',
    'a855f7': 'Violet',
    'f43f5e': 'Rose',
  };

  static const Map<String, String> genieExpressions = {
    'happy': 'Joyeux',
    'excited': 'Excité',
    'focused': 'Concentré',
  };

  // Default attributes for presets
  static Map<String, AvatarConfig> get presets => {
    'man': AvatarConfig(
      seed: 'man',
      style: 'man',
      hairStyle: 'shortFlat',
      facialHair: 'none',
      mouth: 'smile',
      clothing: 'hoodie',
      skinColor: 'ffdbb4',
    ),
    'woman': AvatarConfig(
      seed: 'woman',
      style: 'woman',
      hairStyle: 'longButNotTooLong',
      facialHair: 'none',
      mouth: 'smile',
      clothing: 'shirtCrewNeck',
      skinColor: 'ffdbb4',
    ),
    'boy': AvatarConfig(
      seed: 'boy',
      style: 'boy',
      hairStyle: 'shortCurly',
      facialHair: 'none',
      mouth: 'smile',
      clothing: 'hoodie',
      skinColor: 'ffdbb4',
    ),
    'girl': AvatarConfig(
      seed: 'girl',
      style: 'girl',
      hairStyle: 'curvy',
      facialHair: 'none',
      mouth: 'smile',
      clothing: 'overall',
      skinColor: 'ffdbb4',
    ),
    'grandfather': AvatarConfig(
      seed: 'grandpa',
      style: 'grandfather',
      hairStyle: 'none',
      facialHair: 'beardMajestic',
      hairColor: 'e8e1e1', // Grey
      mouth: 'smile',
      clothing: 'blazerAndShirt',
      accessories: 'prescription01',
      skinColor: 'ffdbb4',
    ),
    'grandmother': AvatarConfig(
      seed: 'grandma',
      style: 'grandmother',
      hairStyle: 'bun',
      facialHair: 'none',
      hairColor: 'e8e1e1', // Grey
      mouth: 'smile',
      clothing: 'blazerAndShirt',
      accessories: 'prescription01',
      skinColor: 'ffdbb4',
    ),
    'bottts': AvatarConfig(
      seed: 'bibliobot',
      style: 'bottts',
      eyes: null,
      eyebrows: null,
      mouth: null,
    ),
  };
}
