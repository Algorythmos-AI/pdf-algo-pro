# Localisation

How PDF Algo Pro's text is translated: where strings live, how they are exported, translated,
imported and checked, and the conventions each language follows. English is the source; French is
the first translation (NFR-L10N-001, bar item B9 on the TestFlight tracking issue,
[#47](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/47)).

Owner: Product and Design · Reviewed: each milestone, and whenever a language is added

## Where strings live

- Each feature package has one String Catalog, `Resources/Localizable.xcstrings`, and its views
  pass `bundle: .module`.
- The app has two catalogs in `App/PDFAlgoPro/Resources/`:
  - `Localizable.xcstrings`, for the app and for PDFEngine, which has no resource bundle, so its
    `String(localized:)` resolves from the app;
  - `AppShortcuts.xcstrings`, the Siri and Shortcuts phrases.
- Info.plist text (the camera prompt) is translated in `App/PDFAlgoPro/<language>.lproj/InfoPlist.strings`,
  next to `Info.plist`, never in an `InfoPlist.xcstrings`. Xcode syncs the app's names into such a
  catalog on every export and build. The names come from build settings per configuration (Staging
  is "PDF Algo β"), and a localised name would replace them. `invariants.py` fails the build on an
  `InfoPlist.xcstrings`, or on a name key in any `InfoPlist.strings`.
- The languages are declared in `project.yml` (`CFBundleLocalizations`), which writes `Info.plist`.

## Updating translations

1. Export every string, including ones added in code since the catalogs were last updated:
   `xcodebuild -exportLocalizations -project PDFAlgoPro.xcodeproj -scheme PDFAlgoPro -localizationPath build/loc -exportLanguage fr`
   (after `xcodegen generate`).
2. Translate the targets in `build/loc/fr.xcloc/Localized Contents/fr.xliff`, following the
   conventions below.
3. Import:
   `xcodebuild -importLocalizations -project PDFAlgoPro.xcodeproj -localizationPath build/loc/fr.xcloc -mergeImport`.
   Move any string exported under `PDFEngine/Resources` into the app's `Localizable.xcstrings`, and
   do not commit a `Resources` folder in PDFEngine. Leave the app's names untranslated.
4. Export again and run `python3 scripts/ci/untranslated.py "build/loc/fr.xcloc/Localized Contents/fr.xliff"`.
   It lists anything untranslated and exits 1 if there is any.
5. A French speaker reviews every changed string in the pull request before the build reaches
   testers.

## French conventions

- **Terms follow iOS in French:**
  - Settings → Réglages; the Files app → Fichiers;
  - Done → OK; Cancel and Undo → Annuler; Redo → Rétablir;
  - Share → Partager; Delete → Supprimer.
  - Apple Intelligence, Private Cloud Compute and Spotlight stay in English.
- **Typography:**
  - a no-break space (U+00A0) before `:` `?` `!` `;`, and inside « guillemets »;
  - the typographic apostrophe `’`.
- **Plurals.** French uses the singular for 0 and 1 ("one") and has a "many" form for very large
  numbers. Every string with a count has plural variants in English and French.
  - A string with a count and another argument uses a substitution for the count, and refers to the
    other argument by position (`%2$@`).
  - `LibraryFeatureTests` checks both languages.
- **Register.** Address the person as « vous », and keep sentences short and plain, as in English.
