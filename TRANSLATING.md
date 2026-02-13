# BiblioGenius — Translation Guide

This guide explains how to contribute translations to BiblioGenius without any programming knowledge.

## Overview

Translations are stored as `.po` files in `assets/i18n/`. Each language has its own file:

| File | Language | Status |
|------|----------|--------|
| `en.po` | English | Complete (reference) |
| `fr.po` | French | Complete |
| `es.po` | Spanish | Complete |
| `de.po` | German | Complete |
| `it.po` | Italian | Empty (ready for contribution) |

## Getting Started

### 1. Install Poedit

Download and install [Poedit](https://poedit.net/) (free version is sufficient).

### 2. Open a .po file

1. Open Poedit
2. File > Open > navigate to `assets/i18n/`
3. Select the `.po` file for your language (e.g., `it.po`)

### 3. Translate

In Poedit, you will see three columns:

- **Source text** (left): The translation key (e.g., `app_title`)
- **Notes** (bottom): The English text for reference
- **Translation** (right): Where you type the translation

For each entry:
1. Read the English reference text in the notes
2. Type the translation in your language
3. Save when done (Ctrl+S / Cmd+S)

### 4. Placeholders

Some strings contain placeholders like `{count}`, `{name}`, or `{title}`. These are replaced at runtime with actual values. **Keep them exactly as-is** in your translation:

```
English note: "{count} books imported successfully."
Your translation: "{count} libri importati con successo."
```

### 5. Validate completeness

From the `bibliogenius-app/` directory, run:

```bash
dart tools/validate_po.dart
```

This shows a coverage report for each language.

## Submitting Your Translation

### Option A: Pull Request (preferred)

1. Fork the repository
2. Edit the `.po` file for your language
3. Run `dart tools/validate_po.dart` to check coverage
4. Submit a pull request with your changes

### Option B: Email

Send the modified `.po` file by email to the project maintainer.

## Adding a New Language

1. Copy `assets/i18n/messages.pot` to `assets/i18n/{lang}.po`
2. Replace the header `Language:` value with the new language code
3. Translate the entries
4. Add the language code to `TranslationService.supportedLocales` in `lib/services/translation_service.dart` — this is the **single source of truth** (main.dart and theme_provider.dart derive from it automatically)

## Technical Notes

- Files use UTF-8 encoding
- Empty `msgstr ""` entries fall back to English at runtime
- Multi-line strings use `\n` for line breaks inside the PO value
- The `.pot` file is the reference template (all keys, no translations)
- Run `dart tools/extract_po.dart` to regenerate `.po` files from the Dart source (one-time migration tool)
