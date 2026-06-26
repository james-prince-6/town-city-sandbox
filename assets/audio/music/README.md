# Music tracks

Drop looping background-music `.ogg` files here, named by **mood**. `AmbientAudio`
(`global/systems/ambient_audio.gd`) auto-discovers them by filename — no code change needed.

Expected files (any you don't add simply stay silent for that mood):

| File         | Plays during                                              |
|--------------|-----------------------------------------------------------|
| `menu.ogg`   | the title screen (boot)                                   |
| `town.ogg`   | the overworld / town / dev scenes (the default mood)      |
| `dungeon.ogg`| any scene whose path contains "dungeon"                   |
| `combat.ogg` | the combat arena (path contains "arena" or "combat")      |

Notes:
- Tracks are set to **loop** automatically in code; you don't need to pre-trim a loop point.
- Music plays on the **Music** audio bus (see `default_bus_layout.tres`), under Master, so the
  pause-menu master volume governs it. Target level is `MUSIC_VOLUME_DB` in `ambient_audio.gd`.
- Mood switches **cross-fade** over `FADE_TIME` (1.5s). Re-entering the same mood does nothing
  (the score keeps playing), so moving between two town scenes won't restart the music.
- To add a new mood, extend `_mood_for_scene()` in `ambient_audio.gd` and drop `<mood>.ogg` here.
