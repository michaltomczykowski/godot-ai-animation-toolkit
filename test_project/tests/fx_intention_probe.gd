@tool
extends RefCounted

# Intentionally fixed public history requests; no generated-key reads choose times.
const SCHEDULE := {
 "shake": [[0.05, "Camera2D:position"], [0.4, "Camera2D:position"]],
 "zoom_punch": [[0.075, "Camera2D:zoom"], [0.25, "Camera2D:zoom"]],
 "hit_flash": [[0.09, "Flash:modulate"], [0.18, "Flash:modulate"]],
 "damage_bar": [[0.125, "DamageBar:value"], [0.65, "DamageBar:value"]],
 "typewriter": [[0.0, "TypeLabel:visible_ratio"], [1.5, "TypeLabel:visible_ratio"]],
 "progress_fill": [[0.0, "FillBar:value"], [0.8, "FillBar:value"]],
 "counter": [[0.50001, "ScoreLabel:text"]],
 "dialog_pop": [[0.0, "DialogPanel:scale"], [0.21, "DialogPanel:scale"], [0.35, "DialogPanel:scale"], [0.0, "DialogPanel:modulate:a"], [0.21, "DialogPanel:modulate:a"]],
 "transition": [[0.0, "FadeOverlay:scale"], [0.5, "FadeOverlay:scale"], [0.5, "FadeOverlay:pivot_offset"]],
 "wave": [[0.3, "Card1:position"], [0.3, "Card2:position"], [0.3, "Card3:position"]],
 "spring": [[0.0, "SpringTarget:position"], [0.5, "SpringTarget:position"], [1.0, "SpringTarget:position"]],
 "pendulum": [[0.0, "PendulumTarget:rotation"], [0.5, "PendulumTarget:rotation"]],
 "path_follow": [[0.0, "Drone:position"], [2.0, "Drone:position"]],
 "flipbook": [[0.0, "Sprite2D:frame"], [0.75, "Sprite2D:frame"]],
 "audio_cue": [[0.25, "CuePlayer:playing"]],
}

class ErrorCapture extends Logger:
 var errors: Array[String] = []
 func _log_error(_function: String, _file: String, _line: int, code: String,
   rationale: String, _notify: bool, type: int, _backtraces: Array) -> void:
  if type != 1: errors.append(rationale if not rationale.is_empty() else code)

static func observe(fixture: Node, op: String) -> Dictionary:
 if op == "sprite_frames":
  var sprite := fixture.get_node("SheetSprite") as AnimatedSprite2D
  var frames := sprite.sprite_frames
  var cells: Array = []
  if frames == null or not frames.has_animation("generated"): return {"missing": true}
  for index in frames.get_frame_count("generated"):
   var texture := frames.get_frame_texture("generated", index)
   var cell := {"class": texture.get_class(), "size": texture.get_size(), "duration": frames.get_frame_duration("generated", index)}
   if texture is AtlasTexture:
    cell["atlas"] = texture.atlas.resource_path
    cell["region"] = [texture.region.position.x, texture.region.position.y, texture.region.size.x, texture.region.size.y]
   cells.append(cell)
  return {"resource_class": frames.get_class(), "animation": str(sprite.animation),
   "playing": sprite.is_playing(), "fps": frames.get_animation_speed("generated"),
   "loop": frames.get_animation_loop("generated"), "cells": cells}
 var samples: Array = []
 for item in SCHEDULE.get(op, []):
  var copy: Node = fixture.duplicate()
  copy.name = "FxIntentionProbe"
  fixture.get_parent().add_child(copy)
  var player := copy.get_node("AnimationPlayer") as AnimationPlayer
  player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
  player.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
  player.play("generated")
  if op == "counter" or op == "audio_cue":
   player.advance(float(item[0]))
  else:
   player.seek(float(item[0]), true)
   player.advance(0.0)
  var path := NodePath(item[1])
  var target := copy.get_node(NodePath(path.get_concatenated_names()))
  samples.append({"at": item[0], "path": item[1], "actual": target.get_indexed(NodePath(":" + str(path.get_concatenated_subnames())))})
  player.stop()
  copy.get_parent().remove_child(copy)
  copy.free()
 return {"samples": samples, "probe_mode": "duplicate_generated_fixture_manual_player"}

static func input_hashes() -> Dictionary:
 var out := {}
 for path in ["res://repair_fx_fixture.tscn", "res://tests/fixtures/sheet.png", "res://tests/fixtures/cue.wav"]:
  out[path] = FileAccess.get_sha256(path)
 return out
