# Localization

Read this reference when the task involves translating game text, adding
locales, or wiring translation files into a Godot project.

## Two Supported Formats

**CSV (simplest).** First column header is literally `keys`; other headers are
locale codes:

```csv
keys,en,es,ja
GREET,"Hello, friend!","Hola, amigo!",こんにちは
BYE,Goodbye,Adiós,さようなら
```

On import Godot generates one compressed `.translation` per locale next to the
CSV and registers each in project settings automatically. Run the importer
headlessly after adding or editing the CSV:

```bash
python3 scripts/import/import_project.py /absolute/project
```

**gettext (`.po`/`.mo`)** for external translators. Godot infers the locale
from the PO `Language:` header. Manage `.po` files with the standard gettext
CLI (`msginit`, `msgmerge`, `msgfmt`).

## Registering Translations

CSV import self-registers. For `.po`/`.mo`/`.translation` files added by hand,
register them with `project_batch`:

```json
{"actions": [{"type": "add_translation", "path": "locale/fr.po"}]}
```

The list lives at `internationalization/locale/translations`. Related keys:
`internationalization/locale/fallback`, `internationalization/locale/test`.

## Runtime API

- `tr("KEY")` translates; on Nodes `atr()` respects the node's auto-translate mode. Controls with plain text (`Button.text`, `Label.text`) auto-translate when the key matches.
- Plurals: `tr_n("There is %d apple", "There are %d apples", n)`.
- Named placeholders survive reordering across languages: `tr("{who} picked up the {what}").format({"who": ..., "what": ...})`.
- Switch locale at runtime: `TranslationServer.set_locale("ja")`.

## Known Limitation: POT Generation Is Editor-Only

There is **no `--export-pot` CLI flag** in Godot 4.x (open proposal
godotengine/godot-proposals#10986). Generating a `.pot` template from scenes
and scripts requires the editor UI: Project Settings → Localization →
POT Generation. Plan translation-template extraction as a manual editor step;
everything else on this page automates headlessly.
