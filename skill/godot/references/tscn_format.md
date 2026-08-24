# Hand-Writing And Hand-Editing `.tscn` Files

Read this reference when a `.tscn` (or `.tres`) file has to be written or patched
as **text** — the host has no shell and cannot run the bundled dispatcher, or a
brand-new scene is being created wholesale. It documents the Godot 4.x text
format, which mistakes the engine rejects loudly, which it absorbs **silently**,
and the verification loop that is not optional afterwards.

Verified on `godot 4.7.stable`. Every behavior claim below was reproduced by
hand-writing the failure case and loading/instantiating it headlessly.

## Hand-Writing Is The Fallback, Not The Default

- With a shell and a `godot` CLI, the structured operations are **required**:
  `scene_batch`, `add_node`, `configure_control`, `attach_script`,
  `connect_signal`, `reparent_node`. They cannot produce a malformed tree.
- Hand-write text only when (a) the host cannot execute the dispatcher at all,
  or (b) an entire new scene file is being authored from nothing.
- "It feels faster to type the whole scene" is not a reason. The
  hierarchy mistakes below load without a single error message, so the time
  saved is spent debugging an invisible bug.
- Whichever path produced the file, run **[The Verification Loop](#the-verification-loop)**.

## File Header

The first section must be `[gd_scene]`. Everything on it is optional.

```
[gd_scene load_steps=6 format=3 uid="uid://cx8n2vqp1e4ab"]
```

| Attribute | Required | Verified behavior when wrong or absent |
| --- | --- | --- |
| `format=3` | No | Omitting it loads fine. `format=2` also loads fine, including deep `parent="A/B"` nesting. Write `format=3`. |
| `load_steps=N` | No | Pure progress hint. `load_steps=1` with 3 resources, `load_steps=99`, and no `load_steps` at all all load identically and bind every resource. **Never worth counting by hand — omit it.** |
| `uid="uid://…"` | No | Omitting it is normal: **headless saves emit no `uid` at all** — the dispatcher writes bare `[gd_scene format=3]`. A completely bogus scene-level `uid` loads with no warning. |

- Missing the `[gd_scene]` line entirely is a **hard parse error**:
  `Parse Error: Unrecognized file type 'node'` → `load()` returns null.
- Attribute values must be **double-quoted**. `type=Button` (unquoted) and
  `type='Button'` (single quotes) are both hard parse errors.
- Blank lines between sections are cosmetic — a file with none loads fine.
- `;` starts a comment. **`#` does not** — at value position it begins a hex
  color literal, so a `# comment` line fails with `Invalid color code: #`.

## `[ext_resource]` And `[sub_resource]`

Both must be declared **before** the first `[node]` that references them.

```
[ext_resource type="Script" path="res://scripts/menu.gd" id="1_menu"]
[ext_resource type="Texture2D" path="res://art/bg.png" id="2_bg"]
[ext_resource type="PackedScene" path="res://scenes/card.tscn" id="3_card"]

[sub_resource type="StyleBoxFlat" id="SB_panel"]
bg_color = Color(0.2, 0.4, 0.6, 1)
corner_radius_top_left = 8
```

- `id` is an arbitrary string you choose; reference it as `ExtResource("1_menu")`
  / `SubResource("SB_panel")`. Godot's own ids look like `1_a3kq2` — any unique
  token works.
- A `[sub_resource]` declared **after** the node that uses it is a hard parse
  error (`Condition "!int_resources.has(id)" is true` → load fails).
- Referencing an id that was never declared — `ExtResource("9_nope")` — is a
  **hard parse error on the node tag**; the whole scene fails to load.
- `path` is mandatory. A `[ext_resource]` with only `uid` and no `path` is a
  hard parse error: `Missing 'path' in external resource tag`.
- An `[ext_resource]` whose `path` points at a missing file prints
  `Parse Error: [ext_resource] referenced non-existent resource at: …` but the
  scene **still loads and instantiates**, with the property left null. Read the
  log, not just the exit code.

### UID Handling — Omit `uid` When Hand-Writing

Headless-saved scenes and resources carry no `uid`, and a project that has never
been opened in the editor has no UID cache, so hand-written `uid=` values are
usually unresolvable. Verified matrix:

| `[ext_resource]` form | Result |
| --- | --- |
| `path` only | Loads correctly, no diagnostic. **Use this.** |
| `uid` + `path`, uid unregistered or stale | `WARNING: ext_resource, invalid UID: … - using text path instead`. Falls back to the path and loads correctly — self-healing, but noisy. |
| `uid` + `path`, uid registered and matching | Loads correctly, silent. |
| `uid` + `path`, uid registered but pointing at a **different** file | **The uid wins, silently.** A scene declaring `path="res://res/blue.tres"` with red's uid loaded `red.tres` with zero warnings. |
| `uid` only, no `path` | Hard parse error, scene does not load. |

The fourth row is the trap: copy-pasting an `[ext_resource]` line from another
scene and editing only the `path` loads the **original** resource with no
diagnostic whatsoever. **Write `path` and omit `uid`.** Let Godot add uids on its
next save.

Running `godot --headless --path <proj> --import` populates `.godot/uid_cache.bin`
and writes `.uid` sidecars; `get_uid` / `resave_resources` inspect and repair
them.

## Node Hierarchy — The Part That Breaks Silently

This is the section that matters. Godot expresses the tree entirely through the
`parent=` attribute; the order and indentation of `[node]` blocks carry no
nesting meaning.

**The three rules:**

1. The **first** `[node]` is the scene root and has **no** `parent` attribute.
2. Direct children of the root use `parent="."`.
3. Deeper nodes use the path **from the root, excluding the root's own name**,
   with `/` as the **only** separator: `parent="Panel/VBox"`.

```
[node name="Menu" type="Control"]

[node name="Panel" type="PanelContainer" parent="."]

[node name="VBox" type="VBoxContainer" parent="Panel"]

[node name="StartButton" type="Button" parent="Panel/VBox"]
text = "Start"

[node name="QuitButton" type="Button" parent="Panel/VBox"]
text = "Quit"
```

Reading that top to bottom: `Menu` is the root (no `parent`), `Panel` is its
child (`parent="."`), `VBox` is a child of `Panel` (`parent="Panel"` — the root's
name never appears), and both buttons are children of `VBox`
(`parent="Panel/VBox"`).

A node's block must appear **after** its parent's block. Forward references do
not resolve.

Optional `[node]` attributes: `groups=["enemies", "spawnable"]`,
`index="0"` (verified: reorders among siblings), `instance=ExtResource("…")`
(instanced sub-scene; `type=` is then unnecessary), and `unique_id=…` (Godot 4.7
bookkeeping — **omit it**; scenes without it load identically and duplicate
values cause no complaint). `unique_name_in_owner` is a **property line**, not an
attribute — `unique_name_in_owner = true` under the node is what makes `%Name`
resolve.

### What Each Mistake Actually Does

| Written | `load()` | `instantiate()` | Diagnostic | Resulting tree |
| --- | --- | --- | --- | --- |
| every child `parent="."` | OK | OK | **none at all** | flat: all nodes siblings under root → **Controls stack at (0,0)** |
| duplicate sibling names | OK | OK | **none at all** | two nodes literally share a name; `get_node()` only ever finds the first |
| `parent="Panel#VBox"` | OK | OK | `WARNING: Parent path './Panel#VBox' … has vanished` | node lands on the **root**, renamed `Panel#VBox#Name` |
| `parent="Panel.VBox"` | OK | OK | same warning | on the root as `Panel_VBox#Name` |
| `parent="Menu/Panel"` (includes root name) | OK | OK | same warning | on the root as `Menu_Panel#Name` |
| `parent="root"` (dispatcher path style) | OK | OK | same warning | on the root as `root#Name` |
| `parent="Nope"` (unknown node) | OK | OK | same warning | on the root as `Nope#Name` |
| child block **before** parent block | OK | OK | same warning | on the root as `Parent#Name` |
| `parent="/Panel"` (leading slash) | OK | OK | `ERROR: Can't use get_node() with absolute paths…` + vanished warning | on the root, mangled |
| `parent="Panel/"` (trailing slash) | OK | OK | none | **correct** — tolerated |
| root node carries `parent="."` | OK | **null** | `ERROR: Invalid scene: root node X cannot specify a parent node` | scene unusable |
| non-root node with **no** `parent=` | OK | **null** | `ERROR: Invalid scene: node X does not specify its parent node` | scene unusable |

Two things to take from the table:

- **The top two rows are the dangerous ones.** They produce no error, no
  warning, and a scene that loads and runs. A flat tree is exactly the reported
  real-world failure: every `Control` becomes a root sibling, each sizes itself
  to its own content at position (0,0), and the UI piles up on itself.
- Godot's own repair for a vanished parent path is to attach the node to the
  root under a mangled name: the failed path with `/` and `.` replaced by `_`,
  then `#`, then the node's name. **`#` in a runtime node name is Godot's
  "your parent path was wrong" marker — it is never a hierarchy separator.**

### Node Names

The text loader does **not** sanitize names. Whatever is in `name="…"` becomes
the runtime name verbatim — verified for `. / : @ % # $ ( )`, spaces, leading
digits, and CJK, and a headless save round-trip preserves them all.

That leniency is the problem, because addressing still uses NodePath rules:

- **`/` and `:` make a node unreachable.** `/` is the path separator and `:` is
  the subname separator, so a node named `Has/Slash` cannot be a `parent=`
  target (the child gets the vanished warning) and `get_node("Has/Slash")`
  returns null.
- `.` `@` `%` are addressable headlessly, but the engine's own name validator
  rejects them. `String.validate_node_name()` rewrites exactly six characters to
  `_` (verified): **`.` `/` `:` `@` `%` `"`**. That is the definitive
  forbidden-character set — the text loader simply never applies it, which is why
  a hand-written `Has.Dot` survives where the editor would have written
  `Has_Dot`. Any such name is a rename waiting to happen, and every `parent=` and
  `NodePath` referring to it goes stale when it does.
- `#` space `-` `$` `(` `)`, leading digits, and CJK pass the validator unchanged
  and work — but `#` collides with Godot's own mangled-name marker above, so it
  still misleads whoever reads the tree next.

**Restrict names to `[A-Za-z0-9_]`.** Match them exactly in `parent=`,
`[connection]`, and `NodePath(…)` — comparison is case-sensitive.

## Property Assignment

Property lines follow the node they belong to, one `key = value` per line, until
the next `[` section. All of these were written by hand and read back unchanged.

```
[node name="Root" type="Node2D"]
script = ExtResource("1_p")
an_int = 42
a_float = 3.5
a_bool = true
a_string = "he said \"hi\"\nline2"
a_stringname = &"snappy"
a_v2 = Vector2(10, -20.5)
a_v2i = Vector2i(3, 4)
a_v3 = Vector3(1, 2, 3)
a_rect = Rect2(0, 0, 64, 32)
a_color = Color(1, 0.5, 0.25, 0.75)
a_xform = Transform2D(1, 0, 0, 1, 12, 34)
a_nodepath = NodePath("Panel/Inner")
an_array = [1, "two", true, Vector2(5, 6), null]
a_dict = {
"hp": 100,
"name": "orc"
}
a_psa = PackedStringArray("a", "b")
a_pv2a = PackedVector2Array(0, 0, 10, 10)
a_pia = PackedInt32Array(7, 8, 9)
a_texture = ExtResource("2_bg")
a_style = SubResource("SB_panel")
a_null = null
metadata/tier = 3

[node name="Panel" type="Panel" parent="."]
theme_override_colors/font_color = Color(1, 1, 1, 1)
theme_override_styles/panel = SubResource("SB_panel")
```

- Strings are double-quoted with `\"` and `\n` escapes; `&"…"` is a `StringName`.
- Packed arrays take a **flat** comma list, not nested constructors:
  `PackedVector2Array(0, 0, 10, 10)` is two points.
- Dictionaries may span lines; keys are quoted.
- Nested/indexed properties use `/`: `metadata/…`, `theme_override_colors/…`.
- Enums are plain ints (`mouse_filter = 2`).
- Only non-default values need writing. `layout_mode` and `anchors_preset` are
  **editor bookkeeping**: a hand-written Control with `anchor_*` / `offset_*` and
  no `layout_mode` produced byte-identical runtime rects to one with them.

## `[connection]` Blocks

Connections go **after all `[node]` blocks**. `from` and `to` are paths from the
scene root, same rules as `parent=`; `.` means the root.

```
[connection signal="pressed" from="Panel/VBox/StartButton" to="." method="_on_start_pressed"]
[connection signal="pressed" from="Panel/VBox/QuitButton" to="." method="_on_quit_pressed" binds=["quit", 7]]
```

`flags=` (default `2`, `CONNECT_PERSIST`) and `unbinds=` are optional. Both
`binds=[…]` and Godot's own `binds= […]` spacing parse.

Failure modes, all verified by checking live connections after instantiate:

| Written | Diagnostic | Result |
| --- | --- | --- |
| `from="Menu/Panel/Btn" to="Menu"` (includes root name) | **none** | connection stored in the file, **zero live connections** — dead wiring, button does nothing |
| `from="Nope"` or `to="Nope"` | **none** | same: silently dropped |
| `method="_typo"` that does not exist on the target | none at load | connection is made; fails only when the signal fires |
| `signal="not_a_signal"` | `ERROR: Attempt to connect nonexistent signal …` | dropped |

A wrong `from`/`to` path is **completely silent** — the connection survives in
the text and in `inspect_scene`'s `connections` array while doing nothing.
Compare each connection's `source`/`target` against the node paths
`inspect_scene` reports.

## Instanced Sub-Scenes

```
[ext_resource type="PackedScene" path="res://scenes/card.tscn" id="3_card"]

[node name="Card" parent="." instance=ExtResource("3_card")]

[node name="Title" parent="Card/VBox" index="0"]
text = "OVERRIDDEN"

[editable path="Card"]
```

- An `instance=` node needs no `type=`.
- To override a property on a node **inside** the instance, write a `[node]`
  block with just `name` + `parent` (no `type`) addressing it through the
  instance — verified to apply the override.
- `[editable path="Card"]` marks the instance's children editable; it parses and
  is harmless.

## `.tres` Resource Files

Same tokenizer, different sections: header is `[gd_resource type="…" format=3]`,
`[ext_resource]` / `[sub_resource]` declarations follow, and the resource's own
properties live under a single `[resource]` section at the end.

```
[gd_resource type="Theme" load_steps=2 format=3]

[ext_resource type="StyleBox" path="res://ui/frame.tres" id="1_frame"]

[sub_resource type="StyleBoxFlat" id="SB_a"]
bg_color = Color(0, 0, 0, 0.5)

[resource]
Button/styles/normal = SubResource("SB_a")
Panel/styles/panel = ExtResource("1_frame")
Label/colors/font_color = Color(1, 1, 1, 1)
Button/constants/h_separation = 12
```

Header, uid, quoting, comment, and declaration-order rules are identical to
`.tscn`. Prefer `resource_batch` / `build_theme` over hand-writing these.

## Common Agent Mistakes

| Mistake | Load-time symptom | Fix |
| --- | --- | --- |
| Every node gets `parent="."` | **Silent.** Loads clean; all Controls sit at (0,0) and overlap; containers stay empty | Give each node the full path from the root, root name excluded: `parent="Panel/VBox"` |
| `#` used as a hierarchy separator (`parent="Panel#VBox"`) | `WARNING: Parent path … has vanished`; node jumps to the root as `Panel#VBox#Name` | `/` is the only separator. `#` is Godot's marker for a *failed* parent path |
| `.` used as a separator (`parent="Panel.VBox"`) | Same vanished warning; node on root as `Panel_VBox#Name` | Use `/`. `.` alone means "the root" and nothing else |
| Parent path includes the root's name (`parent="Menu/Panel"`) | Same vanished warning; node on root | Drop the root's name — paths are relative to the root, not inclusive of it |
| `parent="root"` copied from dispatcher `node_path` style | Same vanished warning | The dispatcher's `root/Panel` addressing is **not** `.tscn` syntax; in text it is `parent="."` / `parent="Panel"` |
| Child `[node]` block written before its parent's block | Same vanished warning | Emit blocks in tree order, parent before child |
| Non-root node with no `parent=` | `ERROR: Invalid scene: node X does not specify its parent node`; `instantiate()` returns null | Every node but the first needs `parent=` |
| Root node given `parent="."` | `ERROR: Invalid scene: root node X cannot specify a parent node`; unusable | Delete `parent=` from the first `[node]` |
| Duplicate sibling names | **Silent.** Two nodes share a name; `get_node()` finds only the first | Make sibling names unique |
| `ExtResource("id")` never declared | Hard parse error on that node tag; scene does not load | Add the `[ext_resource]` line, before the node |
| `[sub_resource]` after the node that uses it | Hard parse error; scene does not load | Move all declarations above the first `[node]` |
| `load_steps` miscounted | **None** — hint only | Omit `load_steps` entirely when hand-writing |
| `uid=` copied from another resource | **Silent wrong resource** when the uid resolves elsewhere | Write `path` only; omit `uid` |
| `[connection] from=`/`to=` includes the root name or a wrong path | **Silent.** Stored but never connected | Use root-relative paths; `to="."` for the root |
| `#` used to start a comment line | `Invalid color code: #` → hard parse error | Use `;` |
| Single-quoted or unquoted attributes | Hard parse error | Double quotes only |
| Node named with `/` or `:` | Child's parent path vanishes; `get_node()` returns null | Keep names to `[A-Za-z0-9_]` |

## The Verification Loop

After **any** hand-written or hand-edited `.tscn`, run these immediately. Neither
step is optional, and neither alone is sufficient.

**1. `check_project` — catches the parse/resource failures.**

```bash
godot --headless --debug --ignore-error-breaks --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  check_project '{}' 2>&1 \
  | python3 /absolute/path/to/godot/scripts/debug/godot_log_parser.py -
```

Expect `"counts": {"total": 0, …}`. This catches every hard failure above —
missing header, undeclared `ExtResource`, late `[sub_resource]`, missing files,
bad quoting.

**It catches most of the hierarchy mistakes, but not a flat tree.**
`check_project` instantiates every scene it loads (that is the `"instantiate"`
parameter, default `true`), which is what makes the parent-path problems visible
— `load()` alone accepts all of them. With the pass on:

- Root `[node]` with `parent="."`, or a non-root `[node]` with no `parent=` —
  `instantiate()` returns null, the engine prints
  `ERROR: Invalid scene: …`, and the scene is listed in `failed[]` with
  `failed_count` above zero. The error names the *node*, not the scene; read the
  scene path from the `failed[]` entry.
- A `parent=` path that does not exist — the engine prints
  `WARNING: Parent path './VBox' for node 'Label' has vanished when
  instantiating: 'res://…tscn'.` and reparents the node to the root as
  `VBox#Label`. It is a **warning**, so `failed_count` stays 0 and
  `validate_project.py` still reports `ok` unless you pass
  `--warnings-as-errors`. The warning text is the signal — do not skim past it.
- **A fully flat tree still passes silently.** Every node carrying `parent="."`
  is a *valid* scene: it instantiates with no error and no warning. Only step 2
  catches it. This was the state of every hierarchy mistake before the
  instantiate pass existed — a directory of 13 broken scenes reported
  `"failed_count": 0, "ok": 13`.

Instantiating runs each scene root script's `_init()` and its stored-property
setters (not `_ready`). Pass `check_project '{"instantiate": false}'` to skip it,
which also gives up the checks above.

**2. `inspect_scene` — the only thing that reveals a wrong tree.**

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  inspect_scene '{"scene_path":"scenes/menu.tscn","include_properties":false}'
```

Read the `path` of every node and confirm it nests as intended. The failure is
plain in the output:

```
intended:  ".", "./Panel", "./Panel/VBox", "./Panel/VBox/StartButton"
flat bug:  ".", "./Panel", "./VBox", "./StartButton"     <- siblings, will overlap
bad sep:   ".", "./Panel", "./Panel#VBox/StartButton"    <- literal bogus path
```

Also check the `connections` array: every `source` / `target` must match a real
node `path` with the leading `./` removed.

**3. Run the scene when a runtime is available.**

```bash
python3 /absolute/path/to/godot/scripts/debug/run_project.py \
  /absolute/path/to/project res://scenes/menu.tscn --quit-after 120 --timeout 60
```

This adds what neither earlier step sees: the scene actually enters a tree, so
`_ready`, `@onready`, container layout, and signal wiring all run. It reports
**nothing** for a fully flat tree — only step 2 catches that.

**Repair shortcut.** With a shell available, load-and-resave normalizes a
hand-written file into Godot's own canonical form (adds `unique_id`, default
layout properties, regularized ordering), which makes a later diff readable:

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  save_scene '{"scene_path":"scenes/menu.tscn"}'
```

Structural repairs are better done with `reparent_node` / `reorder_node` /
`remove_node` than by editing text a second time.

## When The Layout Still Overlaps And The Tree Is Correct

A correct `.tscn` hierarchy is necessary but not sufficient. Overlapping UI has a
second cause entirely outside this format: absolutely-positioned `Control`
siblings that no container arranges — right tree, wrong layout doctrine. See
`references/game_ui.md` for containers, anchors, and layout rules.
