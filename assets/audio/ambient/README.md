# Ambience beds

Drop looping **ambience** `.ogg` files here, named by **mood** — the quiet environmental bed
that sits under the music (wind, birds, town murmur, cave drips, distant lava rumble...).
`AmbientAudio` (`global/systems/ambient_audio.gd`) auto-discovers them by filename.

Expected files (any you don't add simply stay silent for that mood):

| File          | Plays during                                          |
|---------------|-------------------------------------------------------|
| `menu.ogg`    | the title screen                                      |
| `town.ogg`    | the overworld / town (default mood)                   |
| `dungeon.ogg` | dungeon scenes                                        |
| `combat.ogg`  | the combat arena                                      |

Notes:
- Beds loop automatically and **cross-fade** with the music on mood changes.
- Ambience plays on the **Ambient** audio bus (under Master). Target level is
  `AMBIENT_VOLUME_DB` in `ambient_audio.gd` (quieter than music by default).
- Same mood resolution as music (see `../music/README.md`). You can ship a music track without
  an ambience bed for a mood, or vice-versa — each layer is independent.
