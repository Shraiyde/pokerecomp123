class_name Gen3Randomizer
extends RefCounted

## The ROM's seeded permutation (`randomizer.c`): one seed, fixed at the
## challenge menu when the game starts and carried in the seed vars
## (`RANDOMIZER_VAR_SEED_L/H` = 0x40FA/0x40FB, exactly where the ROM
## keeps it), maps every species and item to another of its kind. Both
## co-op phones share the host's seed through those same vars, so the
## two games randomize identically. Features are gated per kind, as
## `RandomizerFeatureEnabled` gates them on the challenge settings.

const SEED_VAR_L: int = 0x40FA
const SEED_VAR_H: int = 0x40FB

static var _permutations: Dictionary = {}


static func seed_of(events: Gen3EventData) -> int:
	return (events.var_get(SEED_VAR_H) << 16) | events.var_get(SEED_VAR_L)


static func set_seed(events: Gen3EventData, seed: int) -> void:
	events.var_set(SEED_VAR_L, seed & 0xFFFF)
	events.var_set(SEED_VAR_H, (seed >> 16) & 0xFFFF)


static func species_for(events: Gen3EventData, species: int, species_count: int) -> int:
	if species < 1 or species > species_count:
		return species
	return _permutation(seed_of(events), species_count)[species - 1] + 1


static func item_for(events: Gen3EventData, item: int, item_count: int) -> int:
	if item < 1 or item > item_count:
		return item
	# Items permute on their own stream, as the ROM seeds them separately.
	return _permutation(seed_of(events) ^ 0x9E3779B9, item_count)[item - 1] + 1


static func _permutation(seed: int, count: int) -> PackedInt32Array:
	var key: String = "%d:%d" % [seed, count]
	if _permutations.has(key):
		return _permutations[key]
	var out := PackedInt32Array()
	out.resize(count)
	for index: int in count:
		out[index] = index
	var rng := RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else 1
	for index: int in range(count - 1, 0, -1):
		var swap: int = rng.randi_range(0, index)
		var held: int = out[index]
		out[index] = out[swap]
		out[swap] = held
	_permutations[key] = out
	return out
