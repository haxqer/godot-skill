# Tween Recipes (Runtime Animation)

Read this reference when adding juice — punches, fades, shakes, UI slides —
that belongs in code rather than in a stored Animation. A `Tween` is
runtime-only: it comes from `create_tween()` and cannot be serialized into a
scene or resource, so it ships inside scripts via `attach_script`. Prefer
`build_animation` (AnimationPlayer) when designers should be able to retime or
inspect the motion; prefer Tween for one-shot, code-driven reactions.

Common mistake: Godot 3's `interpolate_property`/`Tween` node API is gone.
In 4.x a tween is created, configured, and garbage-collected automatically
when finished.

## Core Patterns

```gdscript
# Scale punch (button feedback, hit reaction)
func punch(node: Node2D) -> void:
    var tween := create_tween()
    tween.tween_property(node, "scale", Vector2(1.15, 1.15), 0.06)
    tween.tween_property(node, "scale", Vector2.ONE, 0.18) \
        .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# Fade out, then free
func fade_out(item: CanvasItem) -> void:
    var tween := create_tween()
    tween.tween_property(item, "modulate:a", 0.0, 0.3)
    tween.tween_callback(item.queue_free)

# Parallel move + fade (chain() returns to sequential)
var tween := create_tween()
tween.set_parallel(true)
tween.tween_property(panel, "position:y", 40.0, 0.25).as_relative()
tween.tween_property(panel, "modulate:a", 1.0, 0.25)

# Screen shake via tween_method
func shake(camera: Camera2D, strength: float = 8.0) -> void:
    var tween := create_tween()
    tween.tween_method(
        func(s: float): camera.offset = Vector2(randf_range(-s, s), randf_range(-s, s)),
        strength, 0.0, 0.4)
    tween.tween_callback(func(): camera.offset = Vector2.ZERO)

# Looping idle bob
var tween := create_tween().set_loops()
tween.tween_property(sprite, "position:y", -4.0, 0.8).as_relative() \
    .set_trans(Tween.TRANS_SINE)
tween.tween_property(sprite, "position:y", 4.0, 0.8).as_relative() \
    .set_trans(Tween.TRANS_SINE)
```

## Rules Of Thumb

- `await tween.finished` sequences gameplay after an effect.
- A tween is bound to the node that created it — freed node kills the tween. Use `get_tree().create_tween()` for scene-independent tweens.
- Kill and replace on re-trigger to avoid stacking: keep `var _tween: Tween`, call `if _tween: _tween.kill()` before creating a new one.
- Subproperty paths work: `"modulate:a"`, `"position:x"`, `"scale:y"`.
- `set_trans` picks the curve family (`TRANS_SINE`, `TRANS_BACK`, `TRANS_ELASTIC`...), `set_ease` picks which end accelerates (`EASE_IN`, `EASE_OUT`, `EASE_IN_OUT`).
