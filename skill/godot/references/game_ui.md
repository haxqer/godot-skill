# Game UI (Control Layout, Theme, And Feel)

Read this reference when the task is menus, HUDs, dialogs, inventories, or any
`Control` work. It covers the three things that separate game UI from a default
Godot form: a container-driven layout that never overlaps, a `Theme` that
replaces the gray default, and a feel layer of motion and sound. Everything is
built with the existing `scene_batch` / `configure_control` / `build_theme` /
`project_batch` operations — read `references/automation_api.md` for their full
parameter surface.

Examples verified on Godot `4.7.stable`.

## Layout Doctrine: Containers, Not Coordinates

**The #1 cause of broken game UI is absolute-positioning stacked siblings under
a bare `Control`.** A bare `Control` (or `Node2D`, or `CanvasLayer`) does not
lay out its children. Every `Control` child defaults to the `TOP_LEFT` anchor
with zero offsets, so ten siblings under a bare parent all resolve to `(0, 0)`
and paint on top of each other. Hand-assigning `position` to each one appears to
fix it, then breaks on the next resolution, font change, or translated string.

Containers are the only nodes that position children. Build the spine out of
containers first, then hang leaf controls off it:

```
Root Control            layout_preset FULL_RECT      <- preset lives here
└── MarginContainer     screen-edge breathing room
    └── VBoxContainer   the page rhythm
        ├── Label
        ├── CenterContainer   size_flags_vertical EXPAND_FILL
        │   └── VBoxContainer custom_minimum_size.x = 320
        │       └── Button ×N
        └── Label
```

Rules:

- Set a `layout_preset` **only at a container boundary**: the scene root, a
  direct `Control` child of a `CanvasLayer`, or a full-screen overlay. Never on a
  node that already sits inside a `Container`.
- **Never set `position`, `size`, or `offset_*` on a child of a `Container`.**
  The container overwrites them on every sort. Express intent with
  `custom_minimum_size`, size flags, and `stretch_ratio` instead.
- Pick the container for the job: `VBoxContainer`/`HBoxContainer` for rows and
  columns, `GridContainer` for label/widget settings pairs, `PanelContainer` to
  wrap content in a stylebox that auto-fits it, `MarginContainer` for insets,
  `CenterContainer` to center content whose size you do not know,
  `AspectRatioContainer` for fixed-ratio portraits, `ScrollContainer` for lists
  that can overflow.
- Prefer `CenterContainer` over `PRESET_CENTER`. The preset writes offsets from
  whatever the size happened to be at authoring time; the container re-centers
  every frame as the content's minimum size changes.
- Use a container's `alignment` (`0` begin, `1` center, `2` end) instead of
  inserting empty spacer `Control` nodes.

### Size Flags And Spacing

| Concept | Field | Use |
| --- | --- | --- |
| Fill the cell | `size_flags_*: "FILL"` | Default; stretch to the slot the container gives |
| Claim leftovers | `size_flags_*: "EXPAND_FILL"` | The one child that should absorb free space |
| Keep min size | `size_flags_*: "SHRINK_CENTER"` / `SHRINK_BEGIN` / `SHRINK_END` | Buttons and icons that must not stretch |
| Split leftovers | `stretch_ratio` | Weight between sibling `EXPAND` children |
| Floor a size | `custom_minimum_size` | Menu column width, hotbar slots, text headroom |
| Gap between children | `separation` (Box), `h_separation`/`v_separation` (Grid) | Rhythm inside a container |
| Inset from the edge | `margin_left/top/right/bottom` (Margin) | Rhythm around a container |

Separation and margins are theme constants, so set them globally in the `Theme`
for a consistent rhythm and only override per instance with
`configure_control.theme_overrides.constants` when a spot genuinely differs.

**Pick one base spacing unit and stay on it.** With a base of `4`, every gap and
inset is `4 / 8 / 12 / 16 / 24 / 32 / 48`. Arbitrary values like `7` or `23` are
what make a layout read as "programmer UI" even when nothing overlaps.

### Anchored Controls Must Grow Inward

A `Control` anchored to a right or bottom edge at its minimum size grows
**outward** by default and slides off-screen, because `grow_horizontal` and
`grow_vertical` both default to `END`. Whenever a min-size control is anchored
to a far edge, set the grow direction toward the inside:

| Preset | `grow_horizontal` | `grow_vertical` |
| --- | --- | --- |
| `TOP_LEFT` | `1` (END, default) | `1` (END, default) |
| `TOP_RIGHT` | `0` (BEGIN) | `1` (END) |
| `BOTTOM_LEFT` | `1` (END) | `0` (BEGIN) |
| `CENTER_BOTTOM` | `2` (BOTH) | `0` (BEGIN) |
| `BOTTOM_WIDE` | `1` (END) | `0` (BEGIN) |

`configure_control` has no key for these; set them as ordinary properties in
`add_node.properties` or `configure_node.properties`.

### Overlays Must Not Eat Input

`Control.mouse_filter` defaults to `STOP`. A full-rect background or HUD cluster
therefore swallows every click meant for the game underneath. Set
`"mouse_filter": 2` (IGNORE) on backgrounds, HUD containers, and decorative
labels; leave `STOP` only on things that are actually interactive.

### CanvasLayer For Overlays

Put HUDs, pause menus, and dialog boxes on a `CanvasLayer` so they ignore the
game camera's transform and zoom. Use `layer` to order them (HUD low, dialog
mid, pause high). A pause menu also needs `"process_mode": 2` (WHEN_PAUSED) so
its buttons still respond while `get_tree().paused` is `true`.

## Standard Skeletons

Each block is a complete, runnable `scene_batch`. Replace the two absolute paths
and the placeholder strings.

### Title Screen

Background, centered menu column, footer. The root is the only node carrying a
preset; everything below it is container-driven.

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  scene_batch '{
    "scene_path": "scenes/title.tscn",
    "create_if_missing": true,
    "root_node_type": "Control",
    "root_node_name": "TitleScreen",
    "actions": [
      {"type":"configure_control","node_path":"root","layout_preset":"FULL_RECT"},

      {"type":"add_node","parent_node_path":"root","node_type":"ColorRect","node_name":"Background",
       "properties":{"color":{"__type":"Color","r":0.05,"g":0.063,"b":0.09,"a":1},"mouse_filter":2}},
      {"type":"configure_control","node_path":"root/Background","layout_preset":"FULL_RECT"},

      {"type":"add_node","parent_node_path":"root","node_type":"MarginContainer","node_name":"Frame"},
      {"type":"configure_control","node_path":"root/Frame","layout_preset":"FULL_RECT",
       "theme_overrides":{"constants":{"margin_left":48,"margin_right":48,"margin_top":40,"margin_bottom":32}}},

      {"type":"add_node","parent_node_path":"root/Frame","node_type":"VBoxContainer","node_name":"Column"},
      {"type":"configure_control","node_path":"root/Frame/Column","theme_overrides":{"constants":{"separation":24}}},

      {"type":"add_node","parent_node_path":"root/Frame/Column","node_type":"Label","node_name":"Title",
       "properties":{"text":"EMBER HOLLOW","horizontal_alignment":1,"theme_type_variation":"TitleLabel"}},
      {"type":"add_node","parent_node_path":"root/Frame/Column","node_type":"Label","node_name":"Tagline",
       "properties":{"text":"a lantern is a promise","horizontal_alignment":1,"theme_type_variation":"CaptionLabel"}},

      {"type":"add_node","parent_node_path":"root/Frame/Column","node_type":"CenterContainer","node_name":"MenuSlot"},
      {"type":"configure_control","node_path":"root/Frame/Column/MenuSlot","size_flags_vertical":"EXPAND_FILL"},

      {"type":"add_node","parent_node_path":"root/Frame/Column/MenuSlot","node_type":"VBoxContainer","node_name":"Menu"},
      {"type":"configure_control","node_path":"root/Frame/Column/MenuSlot/Menu",
       "custom_minimum_size":{"__type":"Vector2","x":320,"y":0},
       "theme_overrides":{"constants":{"separation":12}}},

      {"type":"add_node","parent_node_path":"root/Frame/Column/MenuSlot/Menu","node_type":"Button","node_name":"NewGame","properties":{"text":"New Game"}},
      {"type":"add_node","parent_node_path":"root/Frame/Column/MenuSlot/Menu","node_type":"Button","node_name":"Continue","properties":{"text":"Continue","disabled":true}},
      {"type":"add_node","parent_node_path":"root/Frame/Column/MenuSlot/Menu","node_type":"Button","node_name":"Settings","properties":{"text":"Settings"}},
      {"type":"add_node","parent_node_path":"root/Frame/Column/MenuSlot/Menu","node_type":"Button","node_name":"Quit","properties":{"text":"Quit"}},

      {"type":"add_node","parent_node_path":"root/Frame/Column","node_type":"Label","node_name":"Footer",
       "properties":{"text":"v0.1.0  ·  build 240","horizontal_alignment":1,"theme_type_variation":"CaptionLabel"}}
    ]
  }'
```

The `CenterContainer` with `EXPAND_FILL` is what pins the menu to the optical
center while the title stays at the top and the footer at the bottom — no
anchors, no hand-tuned offsets.

### In-Game HUD

A `CanvasLayer` root with three independently anchored clusters: health
top-left, currency top-right, hotbar bottom-center. Each cluster is a
`MarginContainer` at its minimum size, with the grow direction pointed inward.

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  scene_batch '{
    "scene_path": "scenes/hud.tscn",
    "create_if_missing": true,
    "root_node_type": "CanvasLayer",
    "root_node_name": "HUD",
    "actions": [
      {"type":"add_node","parent_node_path":"root","node_type":"MarginContainer","node_name":"TopLeft","properties":{"mouse_filter":2}},
      {"type":"configure_control","node_path":"root/TopLeft","layout_preset":"TOP_LEFT",
       "theme_overrides":{"constants":{"margin_left":24,"margin_top":20,"margin_right":0,"margin_bottom":0}}},
      {"type":"add_node","parent_node_path":"root/TopLeft","node_type":"VBoxContainer","node_name":"Vitals","properties":{"mouse_filter":2}},
      {"type":"configure_control","node_path":"root/TopLeft/Vitals","theme_overrides":{"constants":{"separation":6}}},
      {"type":"add_node","parent_node_path":"root/TopLeft/Vitals","node_type":"Label","node_name":"NameLabel",
       "properties":{"text":"KESTREL","theme_type_variation":"CaptionLabel"}},
      {"type":"add_node","parent_node_path":"root/TopLeft/Vitals","node_type":"ProgressBar","node_name":"HealthBar",
       "properties":{"max_value":100,"value":72,"show_percentage":false}},
      {"type":"configure_control","node_path":"root/TopLeft/Vitals/HealthBar","custom_minimum_size":{"__type":"Vector2","x":260,"y":18}},

      {"type":"add_node","parent_node_path":"root","node_type":"MarginContainer","node_name":"TopRight","properties":{"mouse_filter":2,"grow_horizontal":0,"grow_vertical":1}},
      {"type":"configure_control","node_path":"root/TopRight","layout_preset":"TOP_RIGHT",
       "theme_overrides":{"constants":{"margin_right":24,"margin_top":20,"margin_left":0,"margin_bottom":0}}},
      {"type":"add_node","parent_node_path":"root/TopRight","node_type":"HBoxContainer","node_name":"Purse","properties":{"mouse_filter":2}},
      {"type":"configure_control","node_path":"root/TopRight/Purse","theme_overrides":{"constants":{"separation":8}}},
      {"type":"add_node","parent_node_path":"root/TopRight/Purse","node_type":"Label","node_name":"Icon",
       "properties":{"text":"◆","theme_type_variation":"HeaderLabel"}},
      {"type":"add_node","parent_node_path":"root/TopRight/Purse","node_type":"Label","node_name":"Amount",
       "properties":{"text":"1,240","theme_type_variation":"HeaderLabel"}},

      {"type":"add_node","parent_node_path":"root","node_type":"MarginContainer","node_name":"BottomCenter","properties":{"mouse_filter":2,"grow_horizontal":2,"grow_vertical":0}},
      {"type":"configure_control","node_path":"root/BottomCenter","layout_preset":"CENTER_BOTTOM",
       "theme_overrides":{"constants":{"margin_bottom":28,"margin_left":0,"margin_right":0,"margin_top":0}}},
      {"type":"add_node","parent_node_path":"root/BottomCenter","node_type":"HBoxContainer","node_name":"Hotbar"},
      {"type":"configure_control","node_path":"root/BottomCenter/Hotbar","theme_overrides":{"constants":{"separation":8}}},

      {"type":"add_node","parent_node_path":"root/BottomCenter/Hotbar","node_type":"PanelContainer","node_name":"Slot1"},
      {"type":"configure_control","node_path":"root/BottomCenter/Hotbar/Slot1","custom_minimum_size":{"__type":"Vector2","x":56,"y":56}},
      {"type":"add_node","parent_node_path":"root/BottomCenter/Hotbar/Slot1","node_type":"Label","node_name":"Key",
       "properties":{"text":"1","horizontal_alignment":1,"vertical_alignment":1,"theme_type_variation":"CaptionLabel"}},

      {"type":"add_node","parent_node_path":"root/BottomCenter/Hotbar","node_type":"PanelContainer","node_name":"Slot2"},
      {"type":"configure_control","node_path":"root/BottomCenter/Hotbar/Slot2","custom_minimum_size":{"__type":"Vector2","x":56,"y":56}},
      {"type":"add_node","parent_node_path":"root/BottomCenter/Hotbar/Slot2","node_type":"Label","node_name":"Key",
       "properties":{"text":"2","horizontal_alignment":1,"vertical_alignment":1,"theme_type_variation":"CaptionLabel"}},

      {"type":"add_node","parent_node_path":"root/BottomCenter/Hotbar","node_type":"PanelContainer","node_name":"Slot3"},
      {"type":"configure_control","node_path":"root/BottomCenter/Hotbar/Slot3","custom_minimum_size":{"__type":"Vector2","x":56,"y":56}},
      {"type":"add_node","parent_node_path":"root/BottomCenter/Hotbar/Slot3","node_type":"Label","node_name":"Key",
       "properties":{"text":"3","horizontal_alignment":1,"vertical_alignment":1,"theme_type_variation":"CaptionLabel"}}
    ]
  }'
```

Add the HUD to a level with `instantiate_scene`. Drive the numbers from a script
on the root — never rebuild the scene at runtime to change a label.

### Pause And Settings Panel

Dim overlay plus a centered `PanelContainer` of settings rows. The `GridContainer`
with `columns: 2` is the standard label/widget settings shape.

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  scene_batch '{
    "scene_path": "scenes/pause_menu.tscn",
    "create_if_missing": true,
    "root_node_type": "CanvasLayer",
    "root_node_name": "PauseMenu",
    "actions": [
      {"type":"configure_node","node_path":"root","properties":{"layer":10,"process_mode":2}},

      {"type":"add_node","parent_node_path":"root","node_type":"ColorRect","node_name":"Dim",
       "properties":{"color":{"__type":"Color","r":0,"g":0,"b":0,"a":0.66}}},
      {"type":"configure_control","node_path":"root/Dim","layout_preset":"FULL_RECT"},

      {"type":"add_node","parent_node_path":"root","node_type":"CenterContainer","node_name":"Center"},
      {"type":"configure_control","node_path":"root/Center","layout_preset":"FULL_RECT"},

      {"type":"add_node","parent_node_path":"root/Center","node_type":"PanelContainer","node_name":"Dialog"},
      {"type":"configure_control","node_path":"root/Center/Dialog","custom_minimum_size":{"__type":"Vector2","x":560,"y":0}},

      {"type":"add_node","parent_node_path":"root/Center/Dialog","node_type":"VBoxContainer","node_name":"Body"},
      {"type":"configure_control","node_path":"root/Center/Dialog/Body","theme_overrides":{"constants":{"separation":18}}},

      {"type":"add_node","parent_node_path":"root/Center/Dialog/Body","node_type":"Label","node_name":"Heading",
       "properties":{"text":"PAUSED","horizontal_alignment":1,"theme_type_variation":"HeaderLabel"}},
      {"type":"add_node","parent_node_path":"root/Center/Dialog/Body","node_type":"HSeparator","node_name":"Rule"},

      {"type":"add_node","parent_node_path":"root/Center/Dialog/Body","node_type":"GridContainer","node_name":"Settings",
       "properties":{"columns":2}},
      {"type":"configure_control","node_path":"root/Center/Dialog/Body/Settings","theme_overrides":{"constants":{"h_separation":20,"v_separation":14}}},

      {"type":"add_node","parent_node_path":"root/Center/Dialog/Body/Settings","node_type":"Label","node_name":"MasterLabel","properties":{"text":"Master Volume"}},
      {"type":"add_node","parent_node_path":"root/Center/Dialog/Body/Settings","node_type":"HSlider","node_name":"MasterSlider",
       "properties":{"min_value":0,"max_value":100,"value":80}},
      {"type":"configure_control","node_path":"root/Center/Dialog/Body/Settings/MasterSlider","size_flags_horizontal":"EXPAND_FILL","size_flags_vertical":"SHRINK_CENTER"},

      {"type":"add_node","parent_node_path":"root/Center/Dialog/Body/Settings","node_type":"Label","node_name":"MusicLabel","properties":{"text":"Music"}},
      {"type":"add_node","parent_node_path":"root/Center/Dialog/Body/Settings","node_type":"HSlider","node_name":"MusicSlider",
       "properties":{"min_value":0,"max_value":100,"value":55}},
      {"type":"configure_control","node_path":"root/Center/Dialog/Body/Settings/MusicSlider","size_flags_horizontal":"EXPAND_FILL","size_flags_vertical":"SHRINK_CENTER"},

      {"type":"add_node","parent_node_path":"root/Center/Dialog/Body/Settings","node_type":"Label","node_name":"ShakeLabel","properties":{"text":"Screen Shake"}},
      {"type":"add_node","parent_node_path":"root/Center/Dialog/Body/Settings","node_type":"Button","node_name":"ShakeToggle",
       "properties":{"text":"ON","toggle_mode":true,"button_pressed":true}},
      {"type":"configure_control","node_path":"root/Center/Dialog/Body/Settings/ShakeToggle","size_flags_horizontal":"SHRINK_BEGIN"},

      {"type":"add_node","parent_node_path":"root/Center/Dialog/Body","node_type":"HBoxContainer","node_name":"Actions"},
      {"type":"configure_control","node_path":"root/Center/Dialog/Body/Actions","theme_overrides":{"constants":{"separation":12}}},
      {"type":"add_node","parent_node_path":"root/Center/Dialog/Body/Actions","node_type":"Button","node_name":"Resume","properties":{"text":"Resume"}},
      {"type":"configure_control","node_path":"root/Center/Dialog/Body/Actions/Resume","size_flags_horizontal":"EXPAND_FILL"},
      {"type":"add_node","parent_node_path":"root/Center/Dialog/Body/Actions","node_type":"Button","node_name":"QuitToTitle",
       "properties":{"text":"Quit To Title","theme_type_variation":"DangerButton"}},
      {"type":"configure_control","node_path":"root/Center/Dialog/Body/Actions/QuitToTitle","size_flags_horizontal":"EXPAND_FILL"}
    ]
  }'
```

The `Dialog` sizes itself to its content; `custom_minimum_size.x` only sets a
floor so short settings lists do not collapse into a narrow strip. Set the root
`visible` to `false` and flip it from the pause handler alongside
`get_tree().paused`.

### Dialog Box

Bottom-anchored panel with speaker name, body `RichTextLabel`, and a continue
indicator parked at the end of the row by container alignment.

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  scene_batch '{
    "scene_path": "scenes/dialog_box.tscn",
    "create_if_missing": true,
    "root_node_type": "CanvasLayer",
    "root_node_name": "DialogBox",
    "actions": [
      {"type":"configure_node","node_path":"root","properties":{"layer":5}},

      {"type":"add_node","parent_node_path":"root","node_type":"MarginContainer","node_name":"Anchor","properties":{"grow_vertical":0}},
      {"type":"configure_control","node_path":"root/Anchor","layout_preset":"BOTTOM_WIDE",
       "theme_overrides":{"constants":{"margin_left":40,"margin_right":40,"margin_top":0,"margin_bottom":32}}},

      {"type":"add_node","parent_node_path":"root/Anchor","node_type":"PanelContainer","node_name":"Box"},

      {"type":"add_node","parent_node_path":"root/Anchor/Box","node_type":"VBoxContainer","node_name":"Body"},
      {"type":"configure_control","node_path":"root/Anchor/Box/Body","theme_overrides":{"constants":{"separation":10}}},

      {"type":"add_node","parent_node_path":"root/Anchor/Box/Body","node_type":"Label","node_name":"Speaker",
       "properties":{"text":"MARROW THE LAMPLIGHTER","theme_type_variation":"HeaderLabel"}},

      {"type":"add_node","parent_node_path":"root/Anchor/Box/Body","node_type":"RichTextLabel","node_name":"Text",
       "properties":{"bbcode_enabled":true,"fit_content":true,"scroll_active":false,"autowrap_mode":3,
        "text":"The hollow keeps what it is given. [color=#ffb02e]Give it nothing[/color], and walk the east stair before the lanterns gutter."}},
      {"type":"configure_control","node_path":"root/Anchor/Box/Body/Text",
       "custom_minimum_size":{"__type":"Vector2","x":0,"y":96},
       "size_flags_horizontal":"EXPAND_FILL"},

      {"type":"add_node","parent_node_path":"root/Anchor/Box/Body","node_type":"HBoxContainer","node_name":"Footer",
       "properties":{"alignment":2}},
      {"type":"add_node","parent_node_path":"root/Anchor/Box/Body/Footer","node_type":"Label","node_name":"Continue",
       "properties":{"text":"▼","theme_type_variation":"CaptionLabel"}}
    ]
  }'
```

`custom_minimum_size.y` on the body reserves height for the longest expected
line count, so the panel does not jump between lines of dialogue. Type-on effects
come from `visible_ratio` / `visible_characters` driven by a Tween, not by
rewriting `text` character by character.

## Theme Doctrine: Never Ship The Default Gray

An unthemed project renders the engine's editor-gray fallback. That single fact
is what makes agent-built UI read as "a web form", regardless of layout quality.
Author a `Theme` before wiring behavior.

Derive a palette from the game's art direction and assign every color a **role**,
then use only those roles:

| Role | Purpose |
| --- | --- |
| `background` | Behind everything; the darkest (or lightest) value |
| `panel` | Raised surfaces: dialogs, cards, slots |
| `border` | Panel and control edges; separates surfaces without a drop shadow |
| `accent` | One brand color for focus, selection, and the primary action |
| `text` | Default readable foreground |
| `muted` | Captions, disabled states, secondary metadata |
| `danger` | Destructive actions and low-health warnings only |

The theme below uses `#0d1017` background, `#182031` panel, `#3a4a68` border,
`#ffb02e` accent, `#e9eff8` text, `#8a9bb5` muted, `#e2564a` danger. Swap the hex
values for the project's palette and the structure carries over unchanged.

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  build_theme '{
    "resource_path": "theme/game.tres",
    "default_font_size": 18,
    "types": {
      "Button": {
        "styleboxes": {
          "normal":   {"bg_color":"#222d42","border_width":2,"border_color":"#3a4a68","corner_radius":4,"content_margin_left":22,"content_margin_right":22,"content_margin_top":10,"content_margin_bottom":10},
          "hover":    {"bg_color":"#2e3c58","border_width":2,"border_color":"#5c76a3","corner_radius":4,"content_margin_left":22,"content_margin_right":22,"content_margin_top":10,"content_margin_bottom":10},
          "pressed":  {"bg_color":"#161d2b","border_width":2,"border_color":"#ffb02e","corner_radius":4,"content_margin_left":22,"content_margin_right":22,"content_margin_top":12,"content_margin_bottom":8},
          "disabled": {"bg_color":"#161b26","border_width":2,"border_color":"#262f40","corner_radius":4,"content_margin_left":22,"content_margin_right":22,"content_margin_top":10,"content_margin_bottom":10},
          "focus":    {"draw_center":false,"border_width":2,"border_color":"#ffd479","corner_radius":4,"expand_margin":3}
        },
        "colors": {
          "font_color":"#e9eff8",
          "font_hover_color":"#ffffff",
          "font_pressed_color":"#ffb02e",
          "font_focus_color":"#ffffff",
          "font_disabled_color":"#5b6478"
        },
        "constants": {"h_separation":10,"outline_size":0},
        "font_sizes": {"font_size":18}
      },
      "Label": {
        "colors": {"font_color":"#e9eff8","font_shadow_color":"#00000099"},
        "constants": {"shadow_offset_x":1,"shadow_offset_y":2,"line_spacing":4},
        "font_sizes": {"font_size":18}
      },
      "PanelContainer": {
        "styleboxes": {
          "panel": {"bg_color":"#182031ee","border_width":2,"border_color":"#3a4a68","corner_radius":6,"content_margin_left":20,"content_margin_right":20,"content_margin_top":16,"content_margin_bottom":16}
        }
      },
      "Panel": {
        "styleboxes": {"panel": {"bg_color":"#0d1017cc","corner_radius":0}}
      },
      "ProgressBar": {
        "styleboxes": {
          "background": {"bg_color":"#0d1017","border_width":2,"border_color":"#3a4a68","corner_radius":3},
          "fill": {"bg_color":"#e2564a","corner_radius":2}
        },
        "colors": {"font_color":"#e9eff8"},
        "font_sizes": {"font_size":14}
      },
      "RichTextLabel": {
        "styleboxes": {"normal":"empty"},
        "colors": {"default_color":"#e9eff8","font_shadow_color":"#00000099"},
        "constants": {"line_separation":4},
        "font_sizes": {"normal_font_size":18,"bold_font_size":18}
      },
      "LineEdit": {
        "styleboxes": {
          "normal": {"bg_color":"#0d1017","border_width":2,"border_color":"#3a4a68","corner_radius":4,"content_margin_left":12,"content_margin_right":12,"content_margin_top":8,"content_margin_bottom":8},
          "focus":  {"draw_center":false,"border_width":2,"border_color":"#ffd479","corner_radius":4,"expand_margin":2},
          "read_only": {"bg_color":"#12161f","border_width":2,"border_color":"#262f40","corner_radius":4}
        },
        "colors": {"font_color":"#e9eff8","font_placeholder_color":"#8a9bb5","caret_color":"#ffb02e","selection_color":"#ffb02e55"},
        "font_sizes": {"font_size":18}
      },
      "HSlider": {
        "styleboxes": {
          "slider": {"bg_color":"#0d1017","border_width":2,"border_color":"#3a4a68","corner_radius":3,"content_margin_top":5,"content_margin_bottom":5},
          "grabber_area": {"bg_color":"#ffb02e","corner_radius":3},
          "grabber_area_highlight": {"bg_color":"#ffd479","corner_radius":3}
        }
      },
      "HSeparator": {
        "styleboxes": {"separator": {"bg_color":"#3a4a68","content_margin_top":1,"content_margin_bottom":1}},
        "constants": {"separation":8}
      },
      "BoxContainer": {"constants": {"separation":12}},
      "GridContainer": {"constants": {"h_separation":12,"v_separation":12}},
      "MarginContainer": {"constants": {"margin_left":24,"margin_right":24,"margin_top":24,"margin_bottom":24}}
    },
    "variations": {
      "TitleLabel":   {"base":"Label","colors":{"font_color":"#ffb02e","font_shadow_color":"#000000cc"},"constants":{"shadow_offset_x":2,"shadow_offset_y":3},"font_sizes":{"font_size":56}},
      "HeaderLabel":  {"base":"Label","colors":{"font_color":"#ffd479"},"font_sizes":{"font_size":26}},
      "CaptionLabel": {"base":"Label","colors":{"font_color":"#8a9bb5"},"font_sizes":{"font_size":13}},
      "DangerButton": {"base":"Button","styleboxes":{"normal":{"bg_color":"#3a1f22","border_width":2,"border_color":"#e2564a","corner_radius":4,"content_margin_left":22,"content_margin_right":22,"content_margin_top":10,"content_margin_bottom":10},"hover":{"bg_color":"#5a2a2d","border_width":2,"border_color":"#ff7a6d","corner_radius":4,"content_margin_left":22,"content_margin_right":22,"content_margin_top":10,"content_margin_bottom":10}},"colors":{"font_color":"#ffd9d4"}}
    }
  }'
```

What makes this a game theme rather than a recolor:

- **All five button states differ.** `normal`, `hover`, `pressed`, `disabled`,
  and `focus` each get their own stylebox. A theme that defines only `normal`
  produces a button that never reacts.
- **`focus` is visibly distinct.** It uses `draw_center: false` plus an accent
  border and a positive `expand_margin`, so it draws as a halo *outside* the
  button and reads clearly on a controller. Keyboard and gamepad players cannot
  navigate a menu whose focus state is invisible — never set `"focus": "empty"`
  in a game that ships with gamepad support.
- **`pressed` shifts the content margins** (`top` 12 / `bottom` 8) so the label
  visually sinks by 2px on click. Free tactility with no code.
- **Three font sizes** form the hierarchy: title `56`, header `26`, body `18`,
  caption `13`. Set `default_font_size` so anything unstyled still lands on the
  scale.
- **Type variations name intent, not appearance.** `TitleLabel`, `HeaderLabel`,
  `CaptionLabel`, `DangerButton` are applied with the `theme_type_variation`
  property (see the skeletons above) and restyled in one place later.

Theme item names are not validated by the engine — a typo silently falls back to
the default gray. Verify against the control's documented item names, or load the
saved theme and assert `Theme.has_stylebox(name, type)` for the items you set.

### Wire It Project-Wide

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  project_batch '{
    "backup_path": "project.godot.bak",
    "actions": [
      {"type":"set_setting","name":"gui/theme/custom","value":"res://theme/game.tres"}
    ]
  }'
```

Every `Control` in the project now inherits it. Assign a per-scene `theme` with
`configure_node` only for a genuinely separate visual context (a retro terminal
minigame inside a modern UI).

### Register A Custom Font

The default font is the single loudest "this is an engine default" signal. Drop a
`.ttf`/`.otf` into the project, let it import, then point the theme at it.
`build_theme` merges into an existing theme, so this can run after the main call:

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  build_theme '{
    "resource_path": "theme/game.tres",
    "default_font": {"__resource":"res://fonts/ui_body.ttf"},
    "default_font_size": 18,
    "variations": {
      "TitleLabel": {
        "base": "Label",
        "fonts": {"font": {"__resource_type":"FontVariation","properties":{"base_font":{"__resource":"res://fonts/ui_body.ttf"},"spacing_glyph":2}}},
        "font_sizes": {"font_size": 56}
      }
    }
  }'
```

- A font file must be imported before `{"__resource": ...}` can load it. Run
  `godot --headless --import --path /absolute/path/to/project` after adding it.
- `FontVariation` gives a display face extra letter-spacing (`spacing_glyph`),
  faux bold (`variation_embolden`), or slant (`variation_transform`) without a
  second font file.
- Use at most two families: one display face for titles, one highly legible face
  for body and HUD numerals.

## Game Feel

### Hover And Press Micro-Animation

Static styleboxes handle state; motion sells it. Use a Tween — see
`references/tween.md` for the full pattern set (punch, fade, shake, parallel
chains, kill-and-replace on re-trigger).

The Godot 4.7 catch: animating `scale` on a control **inside a Container** fights
the container, which resets the transform on every sort. Animate
`offset_transform_scale` instead. It is visual-only by default and pivots from
the control's center (`offset_transform_pivot_ratio` defaults to `0.5, 0.5`), so
container layout is untouched.

```gdscript
extends Button

@export var hover_sfx: AudioStream
@export var press_sfx: AudioStream

var _player: AudioStreamPlayer
var _tween: Tween

func _ready() -> void:
    offset_transform_enabled = true
    _player = AudioStreamPlayer.new()
    _player.bus = "UI"
    add_child(_player)
    mouse_entered.connect(_on_hover)
    focus_entered.connect(_on_hover)
    button_down.connect(_on_press)
    mouse_exited.connect(_settle)
    focus_exited.connect(_settle)

func _on_hover() -> void:
    _scale_to(Vector2(1.05, 1.05), 0.10)
    _play(hover_sfx)

func _on_press() -> void:
    _scale_to(Vector2(0.95, 0.95), 0.06)
    _play(press_sfx)

func _settle() -> void:
    _scale_to(Vector2.ONE, 0.12)

func _scale_to(target: Vector2, time: float) -> void:
    if _tween:
        _tween.kill()
    _tween = create_tween()
    _tween.tween_property(self, "offset_transform_scale", target, time) \
        .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _play(stream: AudioStream) -> void:
    if stream == null:
        return
    _player.stream = stream
    _player.play()
```

Attach it with `attach_script` to every menu button, or make it the script of a
reusable button scene instantiated with `instantiate_scene`. Handling
`focus_entered` as well as `mouse_entered` is what makes the menu feel alive on a
gamepad. Keep menu transitions in the 0.10–0.25s range; anything slower reads as
lag between the click and the response.

### UI Sound Bus

Route UI sound to its own bus so players can mute clicks without muting gameplay:

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  setup_audio_buses '{
    "buses": [
      {"name": "Master", "volume_db": 0.0},
      {"name": "Music", "send": "Master", "volume_db": -6.0},
      {"name": "SFX", "send": "Master", "volume_db": -3.0},
      {"name": "UI", "send": "SFX", "volume_db": -4.0}
    ],
    "save_path": "audio/default_bus_layout.tres",
    "set_project_setting": true
  }'
```

Keep UI sounds short (under 120ms), quiet, and distinct per action — hover,
press, confirm, cancel, error. Reusing one click for everything is worse than
silence. Wire the settings sliders to the bus with
`AudioServer.set_bus_volume_db(AudioServer.get_bus_index("UI"), db)`.

### Ornate 9-Patch Frames

`StyleBoxFlat` covers clean modern UI. For decorated frames — carved wood, riveted
metal, rune-etched borders — use a `StyleBoxTexture` so the art's corners stay
crisp while the middle stretches:

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  build_theme '{
    "resource_path": "theme/game.tres",
    "variations": {
      "OrnateFrame": {
        "base": "PanelContainer",
        "styleboxes": {
          "panel": {
            "__resource_type": "StyleBoxTexture",
            "properties": {
              "texture": {"__resource":"res://ui/frame_9patch.png"},
              "texture_margin_left": 12, "texture_margin_right": 12,
              "texture_margin_top": 12, "texture_margin_bottom": 12,
              "content_margin_left": 20, "content_margin_right": 20,
              "content_margin_top": 16, "content_margin_bottom": 16,
              "axis_stretch_horizontal": 0, "axis_stretch_vertical": 0
            }
          }
        }
      }
    }
  }'
```

- `texture_margin_*` marks the non-stretching corner band; `content_margin_*` is
  the padding for the content inside. They are independent — set content margins
  larger than texture margins so text does not collide with the ornament.
- `axis_stretch_*`: `0` stretch, `1` tile, `2` tile-fit. Tile the edges for
  repeating motifs like chain or rope; stretch for smooth gradients.
- Apply it with `"theme_type_variation": "OrnateFrame"` on a `PanelContainer`.

### Pixel-Art UI

Pixel UI has stricter rules than its art. Break them and the UI looks blurry
next to crisp sprites:

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  project_batch '{
    "backup_path": "project.godot.bak",
    "actions": [
      {"type":"set_setting","name":"rendering/textures/canvas_textures/default_texture_filter","value":0},
      {"type":"set_setting","name":"display/window/stretch/mode","value":"viewport"},
      {"type":"set_setting","name":"display/window/stretch/scale_mode","value":"integer"},
      {"type":"set_setting","name":"gui/theme/default_font_antialiasing","value":0},
      {"type":"set_setting","name":"gui/theme/default_font_subpixel_positioning","value":0},
      {"type":"set_setting","name":"gui/theme/default_font_hinting","value":0}
    ]
  }'
```

- Nearest filtering (`0`) plus `integer` scaling keeps every UI pixel square.
- Turn font antialiasing, subpixel positioning, and hinting off, and use a real
  bitmap or pixel font at its native size (or an exact integer multiple: `8`,
  `16`, `24`). A pixel font at `19px` is mush.
- Borders are `1` or `2` pixels. `corner_radius` is `0`, or at most `1–2`;
  a `6px` radius on a pixel-art panel is an immediate tell.
- Prefer `StyleBoxTexture` 9-patches drawn at 1:1 over `StyleBoxFlat` gradients.
- Keep spacing on the same integer grid as the art (multiples of `4` at 1x).

## Text Robustness

Text is where a passing layout breaks in another language.

| Need | Setting |
| --- | --- |
| Wrap body text | `autowrap_mode`: `0` off, `1` arbitrary, `2` word, `3` word-smart (use `3`) |
| Truncate gracefully | `text_overrun_behavior`: `0` none, `3` ellipsis, `4` word + ellipsis |
| Hard clip | `clip_text: true` on `Label`/`Button` — last resort, prefer a wider min size |
| Cap height | `max_lines_visible` on `Label` |
| Grow the panel to the text | `fit_content: true` on `RichTextLabel` |
| Freeze scrolling | `scroll_active: false` on a dialog `RichTextLabel` |

- **A `Label` with `autowrap_mode: 0` inside a narrow container reports a huge
  minimum width** and stretches its parent off-screen. Wrapping is not cosmetic;
  it is what keeps the container from being forced open.
- Reserve headroom: German and Russian commonly run 30–40% longer than English,
  and CJK needs more line height at the same width. Set `custom_minimum_size.y`
  on text blocks from the *longest* expected translation, not the English one.
- Never derive a panel's size from a measured English string. Set a
  `custom_minimum_size` floor and let the container grow.
- Keep buttons wide enough for the longest label plus ~30%, or accept ellipsis
  via `text_overrun_behavior` deliberately.
- Read `references/localization.md` when actually wiring translations.

## Verify The Layout

Never finish UI work on a successful save. `scene_batch` exiting `0` means the
scene serialized, not that anything is visible or correctly placed.

1. Run the scene and read the layout as text. `run_scenario`'s UI report step
   (`{"type": "ui_report", "fail_on": ["any"]}`) walks the live tree after the
   containers have sorted, reports every control's post-layout rect, and fails
   the run on `zero_size`, `offscreen`, and `overlap` findings. It is the check
   that catches the stacked-at-`(0, 0)` failure, and it needs no rendered
   window. See the `ui_report` section of `references/automation_api.md` for its
   full field list.
2. Assert the specific numbers that matter (a menu column's width, a footer's
   position) so a regression fails loudly instead of drifting.

```json
{
  "scene_path": "scenes/title.tscn",
  "viewport_size": {"width": 1280, "height": 720},
  "settle_frames": 4,
  "steps": [
    {"type": "ui_report", "label": "title", "fail_on": ["any"]},
    {"type": "assert", "assertion": "property",
     "node_path": "Frame/Column/MenuSlot/Menu/NewGame", "property": "size:x",
     "expected": 320.0, "operator": "approx", "tolerance": 1.0}
  ],
  "assertions": [
    {"assertion": "node_exists", "node_path": "Frame/Column/MenuSlot/Menu/Quit"},
    {"assertion": "visible", "node_path": "Frame/Column/Title", "expected": true}
  ]
}
```

```bash
python3 /absolute/path/to/godot/scripts/debug/run_scenario.py \
  /absolute/path/to/project /absolute/path/to/ui_scenario.json --headless --pretty
```

3. Add a `{"type": "screenshot", "path": "/absolute/output/title.png"}` step and
   look at it whenever the host can view images. The runner switches to a
   rendered window automatically when a screenshot step is present.
4. Re-run the report at a second `viewport_size` (for example `1920x1080` and
   `1280x720`) before calling the layout done.
5. Finish with `scripts/debug/validate_project.py` so a stray warning in a UI
   script does not ship.

A layout that reports `findings: 0` at two resolutions, with a theme applied and
a visible focus state, is game UI. Any of those missing and it is a gray form.
