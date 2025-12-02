# Implementation Plan - Integrate Symfony Hub Translations

## Problem

The Flutter application currently relies on a hardcoded map of translations in `TranslationService.dart`. The user has indicated that translation management is implemented in the `bibliogenius-hub` backend (Symfony), and the app should leverage this.

## Proposed Solution

We will refactor the `TranslationService` to fetch translations from the `bibliogenius-hub` API on startup and cache them locally. The hardcoded translations will serve as a fallback/default bundle to ensure the app works offline or before the first fetch.

## Technical Details

### 1. Update `ApiService.dart`

Add a method to fetch translations from the Hub.

- **Endpoint:** `GET /api/translations/{locale}` (on Hub URL)
- **Method:** `getTranslations(String locale)`

### 2. Refactor `TranslationService.dart`

- Change `TranslationService` from a purely static class to a singleton or provider-based service that can hold state.
- Add a `Map<String, Map<String, String>> _dynamicTranslations` to store fetched values.
- Add a `load(String locale)` method that:
    1. Fetches translations from `ApiService`.
    2. Merges them into `_dynamicTranslations`.
    3. (Optional for now, but recommended) Persists them to `SharedPreferences` for offline support.
- Update `translate(BuildContext context, String key)` to check `_dynamicTranslations` first, then fall back to the static `_localizedValues`.

### 3. App Initialization (`main.dart`)

- Initialize `TranslationService` on app startup.
- Trigger a fetch for the current locale.

## Verification Plan

- **Manual Test:**
    1. Start the app.
    2. Verify that translations still work (using hardcoded defaults).
    3. (Mock/Verify) If the Hub returns different values, they should appear after a refresh or restart.
- **Automated Test:**
  - Unit test `TranslationService` to ensure it correctly merges dynamic and static values.

## Questions for User

- Should we cache the translations on disk (e.g., `SharedPreferences`) to persist them across app restarts without network? (Assumed YES for "Local-First" philosophy).
