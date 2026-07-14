# CI For Godot Projects

Read this reference when setting up automated export or test pipelines. The
official Godot docs cover CLI export but provide no CI guidance, so this page
records the community-standard setup plus a raw fallback.

## Tests + Export On GitHub Actions

```yaml
name: godot-ci
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      # GdUnit4 projects — installs Godot + runs the suite, publishes JUnit:
      - uses: godot-gdunit-labs/gdUnit4-action@v1
        with:
          godot-version: '4.7'
          paths: 'res://tests'

  export:
    runs-on: ubuntu-latest
    # Docker image with Godot + export templates preinstalled:
    container: barichello/godot-ci:4.7
    steps:
      - uses: actions/checkout@v4
      - name: Import assets
        run: godot --headless --import
      - name: Export
        run: |
          mkdir -p build/web
          godot --headless --export-release "Web" build/web/index.html
      - uses: actions/upload-artifact@v4
        with: {name: web-build, path: build/web}
```

- Export container: `abarichello/godot-ci` (Docker Hub `barichello/godot-ci`) — pin the tag to the project's Godot version so export templates match.
- GUT has no first-party action; run it inside the same container: `godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://test -gexit -gjunit_xml_file=/tmp/gut.xml` (exit 0 = pass).
- GdUnit4 action repo: `godot-gdunit-labs/gdUnit4-action` (the project moved from the MikeSchulze org).

## Raw Recipe (No Third-Party Actions)

1. Download the matching editor + export templates:
   ```bash
   VERSION=4.7-stable
   curl -LO https://github.com/godotengine/godot-builds/releases/download/${VERSION}/Godot_v${VERSION}_linux.x86_64.zip
   curl -LO https://github.com/godotengine/godot-builds/releases/download/${VERSION}/Godot_v${VERSION}_export_templates.tpz
   unzip Godot_v${VERSION}_linux.x86_64.zip && sudo mv Godot_* /usr/local/bin/godot
   mkdir -p ~/.local/share/godot/export_templates/${VERSION/-/.}
   unzip Godot_v${VERSION}_export_templates.tpz -d /tmp/tpl
   mv /tmp/tpl/templates/* ~/.local/share/godot/export_templates/${VERSION/-/.}/
   ```
2. `godot --headless --import` before validating or exporting — fresh checkouts have no `.godot/` import cache.
3. Gate merges on the bundled validators: `validate_project.py` (static + C#) and `run_tests.py` (unit tests); both return non-zero on failure.
4. Export with `export_project.py` or raw `godot --headless --export-release "<preset>" <out>`. C# projects need the .NET editor image and a `--build-solutions` pre-step.
5. Keep secrets (Android keystores, Apple certs) in CI secret storage and reference them from `export_presets.cfg` via environment overrides rather than committing them.
