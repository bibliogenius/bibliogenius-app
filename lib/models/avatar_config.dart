class AvatarConfig {
  final String style; // 'avataaars', 'lorelei', 'adventurer', 'genie'
  final String? hairStyle;
  final String? facialHair;
  final String? skinColor;
  final String? hairColor;
  final String? accessories;
  final String? clothing;
  final String? clothingColor;
  final String? mouth; // New parameter for facial expression
  
  // Genie-specific options
  final String? genieColor; // For genie avatar
  final String? genieBackground; // For genie avatar
  final String? genieExpression; // 'happy', 'excited', 'focused'
  
  final String seed;

  const AvatarConfig({
    this.style = 'avataaars',
    this.hairStyle,
    this.facialHair,
    this.skinColor,
    this.hairColor,
    this.accessories,
    this.clothing,
    this.clothingColor,
    this.genieColor,
    this.genieBackground,
    this.genieExpression,
    this.mouth,
    required this.seed,
  });

  // Generate DiceBear API URL or local asset path
  String toUrl({int size = 200, String format = 'png'}) {
    // For genie avatar, use local asset
    if (style == 'genie') {
      return 'assets/genie_mascot.jpg';
    }
    
    // Map presets to actual API styles
    String apiStyle = style;
    if (['man', 'woman', 'boy', 'girl', 'grandfather', 'grandmother'].contains(style)) {
      apiStyle = 'avataaars';
    }

    final params = <String, String>{
      'seed': seed,
      'size': size.toString(),
    };
    
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

    if (skinColor != null) params['skinColor'] = skinColor!;
    if (hairColor != null) params['hairColor'] = hairColor!;
    
    if (accessories != null) {
      if (accessories == 'none') {
        params['accessoriesProbability'] = '0';
      } else {
        params['accessories'] = accessories!;
        params['accessoriesProbability'] = '100';
      }
    }
    if (clothing != null) params['clothing'] = clothing!;
    if (clothingColor != null) params['clothingColor'] = clothingColor!;
    if (mouth != null) params['mouth'] = mouth!;

    final queryString = params.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    return 'https://api.dicebear.com/7.x/$apiStyle/$format?$queryString';
  }

  // Convert to JSON for storage
  Map<String, dynamic> toJson() => {
        'style': style,
        'hairStyle': hairStyle,
        'facialHair': facialHair,
        'skinColor': skinColor,
        'hairColor': hairColor,
        'accessories': accessories,
        'clothing': clothing,
        'clothingColor': clothingColor,

        'mouth': mouth,
        'seed': seed,
      };

  // Create from JSON
  factory AvatarConfig.fromJson(Map<String, dynamic> json) => AvatarConfig(
        style: json['style'] ?? 'avataaars',
        hairStyle: json['hairStyle'],
        facialHair: json['facialHair'],
        skinColor: json['skinColor'],
        hairColor: json['hairColor'],
        accessories: json['accessories'],
        clothing: json['clothing'],
        clothingColor: json['clothingColor'],

        mouth: json['mouth'],
        seed: json['seed'] ?? 'default',
      );

  // Create copy with changes
  AvatarConfig copyWith({
    String? style,
    String? hairStyle,
    String? facialHair,
    String? skinColor,
    String? hairColor,
    String? accessories,
    String? clothing,
    String? clothingColor,
    String? genieColor,
    String? genieBackground,
    String? genieExpression,

    String? mouth,
    String? seed,
  }) =>
      AvatarConfig(
        style: style ?? this.style,
        hairStyle: hairStyle ?? this.hairStyle,
        facialHair: facialHair ?? this.facialHair,
        skinColor: skinColor ?? this.skinColor,
        hairColor: hairColor ?? this.hairColor,
        accessories: accessories ?? this.accessories,
        clothing: clothing ?? this.clothing,
        clothingColor: clothingColor ?? this.clothingColor,
        genieColor: genieColor ?? this.genieColor,
        genieBackground: genieBackground ?? this.genieBackground,
        genieExpression: genieExpression ?? this.genieExpression,
        mouth: mouth ?? this.mouth,
        seed: seed ?? this.seed,
      );

  // Default config - using neutral "initials" style instead of random human avatars
  static AvatarConfig get defaultConfig => AvatarConfig(
        seed: 'bibliogenius',
        style: 'initials',
      );
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
        'notionists': 'Artiste',
        'genie': 'Génie BiblioGenius',
      };
    } else if (lang == 'es') {
      return {
        'man': 'Hombre',
        'woman': 'Mujer',
        'boy': 'Niño',
        'girl': 'Niña',
        'grandfather': 'Abuelo',
        'grandmother': 'Abuela',
        'bottts': 'Robot',
        'notionists': 'Artista',
        'genie': 'Genio BiblioGenius',
      };
    } else if (lang == 'de') {
      return {
        'man': 'Mann',
        'woman': 'Frau',
        'boy': 'Junge',
        'girl': 'Mädchen',
        'grandfather': 'Großvater',
        'grandmother': 'Großmutter',
        'bottts': 'Roboter',
        'notionists': 'Künstler',
        'genie': 'BiblioGenius Genie',
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
      'notionists': 'Artist',
      'genie': 'BiblioGenius Genie',
    };
  }

  static Map<String, String> getMouthOptions(String lang) {
    if (lang == 'fr') {
      return {
        'smile': 'Sourire',
        'default': 'Neutre',
        'twinkle': 'Ravi',
        'tongue': 'Grimace',
        'serious': 'Sérieux',
      };
    }
    // Add other languages... defaulting to English for brevity/fallback
    return {
      'smile': 'Smile',
      'default': 'Neutral',
      'twinkle': 'Happy',
      'tongue': 'Silly',
      'serious': 'Serious',
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
    };
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
        'sunglasses': 'Lunettes de soleil',
      };
    }
    return {
      'none': 'None',
      'prescription01': 'Glasses',
      'sunglasses': 'Sunglasses',
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
    '4a312c': 'Brun', // Colors usually don't need translation or can stay as is for now
    'ffd700': 'Blond',
    'ff0000': 'Roux',
    '000000': 'Noir',
    'a0a0a0': 'Gris',
  };

  // Genie-specific options
  static const Map<String, String> genieColors = {
    '2563eb': 'Bleu',
    '7c3aed': 'Violet',
    'ec4899': 'Rose',
    '10b981': 'Vert',
    'f59e0b': 'Orange',
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
    ),
    'woman': AvatarConfig(
      seed: 'woman',
      style: 'woman',
      hairStyle: 'longButNotTooLong',
      facialHair: 'none',
      mouth: 'smile',
      clothing: 'shirtCrewNeck',
    ),
    'boy': AvatarConfig(
      seed: 'boy',
      style: 'boy',
      hairStyle: 'shortCurly',
      facialHair: 'none',
      mouth: 'smile',
      clothing: 'hoodie',
    ),
    'girl': AvatarConfig(
      seed: 'girl',
      style: 'girl',
      hairStyle: 'curvy',
      facialHair: 'none',
      mouth: 'smile',
      clothing: 'overall',
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
    ),
    'bottts': AvatarConfig(
      seed: 'bot',
      style: 'bottts',
    ),
    'notionists': AvatarConfig(
      seed: 'artist',
      style: 'notionists',
    ),
  };
}
