# Architecture Templates

Use this reference after `architecture_qframework_lite.md` when you need a
concrete folder layout or starter skeletons for a Godot feature.

## Recommended Folder Layout

Use this layout for a medium-sized feature:

```text
features/
  inventory/
    controllers/
      inventory_screen_controller.gd
    commands/
      add_item_command.gd
    queries/
      get_inventory_summary_query.gd
    systems/
      inventory_workflow_system.gd
    models/
      inventory_model.gd
      inventory_state.gd
    events/
      inventory_item_added.gd
    utilities/
      inventory_save_utility.gd
```

Use this app root:

```text
app/
  app_architecture.gd
  shared/
    utilities/
  features/
    inventory/
    quest/
    profile/
```

If the project uses `C#`, keep the same structure and swap extensions to
`.cs`. Do not fork the architecture rules by language unless the repository
already does.

## Architecture Root

Use a single registration or bootstrap point per root:

```gdscript
class_name GameApp
extends Node

var _inventory_model: InventoryModel
var _inventory_system: InventoryWorkflowSystem
var _save_utility: SaveGameUtility

func _ready() -> void:
    _save_utility = SaveGameUtility.new()
    _inventory_model = InventoryModel.new(_save_utility)
    _inventory_system = InventoryWorkflowSystem.new(_inventory_model)

func inventory_model() -> InventoryModel:
    return _inventory_model

func inventory_system() -> InventoryWorkflowSystem:
    return _inventory_system
```

Use an autoload only when the feature truly needs app-wide lifetime.

## Controller Template

Use scene scripts as the edge:

```gdscript
class_name InventoryScreenController
extends Control

@onready var _count_label: Label = %CountLabel
var _app: GameApp

func _ready() -> void:
    _app = get_node("/root/GameApp")
    _app.inventory_model().inventory_changed.connect(_refresh)
    _refresh()

func _on_add_button_pressed() -> void:
    AddItemCommand.new(_app.inventory_model(), _app.inventory_system()).execute("potion")

func _refresh() -> void:
    _count_label.text = str(_app.inventory_model().total_count())
```

Keep controllers small:

- read current state,
- bind observable state,
- dispatch commands,
- avoid business decisions.

## Model Template

Use models to own state:

```gdscript
class_name InventoryModel
extends RefCounted

signal inventory_changed

var _save_utility: SaveGameUtility
var _items: Dictionary = {}

func _init(save_utility: SaveGameUtility) -> void:
    _save_utility = save_utility
    _items = _save_utility.load_inventory()

func can_add_item(item_id: String) -> bool:
    return item_id != ""

func add_item(item_id: String) -> void:
    if not can_add_item(item_id):
        push_error("Invalid item id")
        return
    _items[item_id] = int(_items.get(item_id, 0)) + 1
    _save_utility.save_inventory(_items)
    inventory_changed.emit()

func total_count() -> int:
    var total := 0
    for count in _items.values():
        total += int(count)
    return total
```

Expose stable capabilities, not raw mutable internals.

## System Template

Use systems for shared workflows:

```gdscript
class_name InventoryWorkflowSystem
extends RefCounted

var _inventory_model: InventoryModel

func _init(inventory_model: InventoryModel) -> void:
    _inventory_model = inventory_model

func unlock_tutorial_if_needed(item_id: String) -> void:
    if item_id == "potion" and _inventory_model.total_count() == 1:
        TutorialEvents.inventory_tutorial_unlocked.emit()
```

Keep the system focused on orchestration. If a rule belongs to one state owner
only, prefer the model.

## Command Template

Use commands for writes:

```gdscript
class_name AddItemCommand
extends RefCounted

var _inventory_model: InventoryModel
var _inventory_system: InventoryWorkflowSystem

func _init(inventory_model: InventoryModel, inventory_system: InventoryWorkflowSystem) -> void:
    _inventory_model = inventory_model
    _inventory_system = inventory_system

func execute(item_id: String) -> void:
    _inventory_model.add_item(item_id)
    _inventory_system.unlock_tutorial_if_needed(item_id)
```

Keep commands short-lived. Pass inputs in, execute, and disappear.

## Query Template

Use queries for non-trivial reads:

```gdscript
class_name GetInventorySummaryQuery
extends RefCounted

var _inventory_model: InventoryModel

func _init(inventory_model: InventoryModel) -> void:
    _inventory_model = inventory_model

func execute() -> Dictionary:
    return {
        "total_count": _inventory_model.total_count()
    }
```

If a read is one line and used once, direct model reads can be acceptable. Use
a query once the read stops being trivial.

## Event Template

Use events to publish facts:

```gdscript
class_name InventoryItemAddedEvent
extends RefCounted

var item_id: String

func _init(value: String) -> void:
    item_id = value
```

For Godot-first codebases, a typed signal payload or a simple fact-style signal
name is usually enough.

## Utility Template

Use utilities to isolate infrastructure:

```gdscript
class_name SaveGameUtility
extends RefCounted

func load_inventory() -> Dictionary:
    return {}

func save_inventory(items: Dictionary) -> void:
    pass
```

Utilities should not own game rules.
