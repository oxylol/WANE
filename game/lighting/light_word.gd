class_name LightWord
extends RefCounted
## The words a fixture or the command line gives the lighting (docs/adr/0023 Decision 7.3): the Dark
## factor a render is held at. "pitch" is a Dark factor of 0.15 and "dusk" of 1.0, the default;
## "off"
## builds no lighting field at all (the frame bench's baseline). Presentation only.

const PITCH: String = "pitch"
const DUSK: String = "dusk"
const OFF: String = "off"
## The Dark level a word stands for. Pitch begins at D = 2.6, where the factor reaches its floor; a
## Pitch render is held a little past it, on the floor itself.
const PITCH_LEVEL: float = 3.0
const DUSK_LEVEL: float = 1.0


## The Dark level the lighting word asks for, or -1.0 if it is not a word ([constant PITCH],
## [constant DUSK]); "off" and "" are not asks.
static func level_for(word: String) -> float:
	if word == PITCH:
		return PITCH_LEVEL
	if word == DUSK:
		return DUSK_LEVEL
	return -1.0


## Whether [param word] is a lighting word a fixture may use.
static func is_word(word: String) -> bool:
	return level_for(word) >= 0.0


## The Dark level a harness holds the game at for [param word]: Dusk unless it says Pitch.
static func level_or_dusk(word: String) -> float:
	var level: float = level_for(word)
	return level if level >= 0.0 else DUSK_LEVEL
