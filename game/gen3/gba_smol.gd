class_name GbaSmol
extends RefCounted

## smol compression (pokeemerald-expansion): an 8-byte SmolHeader, then mode-dependent
## data. Mode 1 (BASE_ONLY, .fastSmol) stores a raw u16 symbol vector and a raw byte
## instruction vector; modes 2-6 tANS-encode one or both vectors over a shared
## bitstream. Heart & Soul stores its tileset tiles as .fastSmol, with a few
## .smol tilesets using mode 6 (ENCODE_BOTH_DELTA_SYMS). Only the data path is
## decoded here (tilemaps use a separate header and are not needed for tilesets).
static func decompress(data: PackedByteArray, offset: int, limit: int = 0x8000) -> PackedByteArray:
	if offset < 0 or offset + 8 > data.size():
		return PackedByteArray()
	var w0: int = data.decode_u32(offset)
	var w1: int = data.decode_u32(offset + 4)
	var mode: int = w0 & 0xF
	if mode < 1 or mode > 6:
		return PackedByteArray()
	var image_size: int = (w0 >> 4) & 0x3FFF
	var sym_size: int = (w0 >> 18) & 0x3FFF
	var lo_size: int = (w1 >> 19) & 0x1FFF
	var size: int = image_size * 4
	if size <= 0 or size > limit:
		return PackedByteArray()
	var lo: PackedByteArray
	var sym: PackedByteArray
	if mode == 1:
		var sym_at: int = offset + 8
		var lo_at: int = sym_at + sym_size * 2
		if lo_at + lo_size > data.size():
			return PackedByteArray()
		sym = data.slice(sym_at, sym_at + sym_size * 2)
		lo = data.slice(lo_at, lo_at + lo_size)
	else:
		var decoded: Dictionary = _decode_tans_vectors(data, offset, mode, sym_size, lo_size)
		if decoded.is_empty():
			return PackedByteArray()
		sym = decoded["sym"]
		lo = decoded["lo"]
	return _decode_instructions(lo, sym, size)


## The instruction decoder (DecodeInstructions): a byte vector of length/offset pairs
## and a u16 symbol vector produce the output u16s. Returns empty on bad input.
static func _decode_instructions(lo: PackedByteArray, sym: PackedByteArray, size: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(size)
	var dest: int = 0
	var sym_pos: int = 0
	var lo_pos: int = 0
	var lo_end: int = lo.size()
	while lo_pos < lo_end:
		var curr_length: int
		var curr_offset: int
		if lo[lo_pos] & 0x80 != 0:
			if lo_pos + 3 > lo_end:
				return PackedByteArray()
			curr_length = (lo[lo_pos] & 0x7F) | (lo[lo_pos + 1] << 7)
			curr_offset = lo[lo_pos + 2] & 0x7F
			if lo[lo_pos + 2] & 0x80 != 0:
				if lo_pos + 4 > lo_end:
					return PackedByteArray()
				curr_offset |= lo[lo_pos + 3] << 7
				lo_pos += 4
			else:
				lo_pos += 3
		else:
			if lo_pos + 2 > lo_end:
				return PackedByteArray()
			curr_length = lo[lo_pos] & 0x7F
			curr_offset = lo[lo_pos + 1] & 0x7F
			if lo[lo_pos + 1] & 0x80 != 0:
				if lo_pos + 3 > lo_end:
					return PackedByteArray()
				curr_offset |= lo[lo_pos + 2] << 7
				lo_pos += 3
			else:
				lo_pos += 2
		if curr_length != 0:
			if sym_pos + 2 > sym.size() or dest + 2 > size:
				return PackedByteArray()
			var sym_val: int = sym.decode_u16(sym_pos)
			out.encode_u16(dest, sym_val)
			dest += 2
			sym_pos += 2
			if curr_offset == 1:
				if dest + curr_length * 2 > size:
					return PackedByteArray()
				for repeat: int in curr_length:
					out.encode_u16(dest, sym_val)
					dest += 2
			else:
				if dest + curr_length * 2 > size or curr_offset * 2 > dest:
					return PackedByteArray()
				for copied: int in curr_length:
					out.encode_u16(dest, out.decode_u16(dest - curr_offset * 2))
					dest += 2
		else:
			if sym_pos + curr_offset * 2 > sym.size() or dest + curr_offset * 2 > size:
				return PackedByteArray()
			for copied: int in curr_offset:
				out.encode_u16(dest, sym.decode_u16(sym_pos))
				dest += 2
				sym_pos += 2
	if dest != size:
		return PackedByteArray()
	return out


## tANS decoding for modes 2-6. The LO and symbol vectors share one bitstream and one
## decoder state (initialState, bit position); the LO vector is decoded first.
static func _decode_tans_vectors(data: PackedByteArray, offset: int, mode: int, sym_size: int, lo_size: int) -> Dictionary:
	var w1: int = data.decode_u32(offset + 4)
	var bitstream_size: int = (w1 >> 6) & 0x1FFF
	var lo_encoded: bool = mode in [4, 5, 6]
	var sym_encoded: bool = mode in [2, 3, 5, 6]
	var sym_delta: bool = mode in [3, 6]
	# Frequency tables come first (3 u32s each), then the bitstream.
	var freq_at: int = offset + 8
	var stream_at: int = freq_at + (12 if lo_encoded else 0) + (12 if sym_encoded else 0)
	if stream_at + bitstream_size * 4 > data.size():
		return {}
	var ctx: Dictionary = {"words": data.slice(stream_at, stream_at + bitstream_size * 4),
		"bit_pos": 0, "state": w1 & 0x3F}
	var lo: PackedByteArray
	if lo_encoded:
		var lo_freqs: Array = _read_words(data, freq_at, 3)
		lo = _decode_lo(ctx, _tans_table(lo_freqs), lo_size)
		if lo.is_empty() and lo_size > 0:
			return {}
	else:
		# Raw LO follows the bitstream (after a raw symbol vector, if there is one).
		var lo_at: int = stream_at + bitstream_size * 4 + (sym_size * 2 if not sym_encoded else 0)
		if lo_at + lo_size > data.size():
			return {}
		lo = data.slice(lo_at, lo_at + lo_size)
	var sym: PackedByteArray
	if sym_encoded:
		var sym_freqs: Array = _read_words(data, freq_at + (12 if lo_encoded else 0), 3)
		sym = _decode_sym(ctx, _tans_table(sym_freqs), sym_size, sym_delta)
		if sym.is_empty() and sym_size > 0:
			return {}
	else:
		# Raw symbols follow the bitstream directly.
		var sym_at: int = stream_at + bitstream_size * 4
		if sym_at + sym_size * 2 > data.size():
			return {}
		sym = data.slice(sym_at, sym_at + sym_size * 2)
	return {"lo": lo, "sym": sym}


static func _read_words(data: PackedByteArray, at: int, count: int) -> Array:
	var out: Array = []
	for i: int in count:
		out.append(data.decode_u32(at + i * 4))
	return out


## One tANS step: read the symbol for the current state, then advance the state by
## the next k bits. Bits are LSB-first across the u32 word stream.
static func _tans_step(ctx: Dictionary, table: Array) -> int:
	var yk: int = table[ctx["state"]]
	var sym: int = (yk & 0xFF) >> 3
	var k: int = yk & 7
	var y: int = (yk >> 8) & 0xFF
	var mask: int = yk >> 16
	ctx["state"] = y + (_read_bits(ctx, k) & mask)
	return sym


static func _read_bits(ctx: Dictionary, k: int) -> int:
	if k == 0:
		return 0
	var words: PackedByteArray = ctx["words"]
	var pos: int = ctx["bit_pos"]
	var wi: int = pos / 32
	var off: int = pos % 32
	if wi >= words.size() / 4:
		return 0
	var value: int
	if off + k <= 32:
		value = (words.decode_u32(wi * 4) >> off) & ((1 << k) - 1)
	else:
		var low: int = (words.decode_u32(wi * 4) >> off) & ((1 << (32 - off)) - 1)
		var high: int = words.decode_u32((wi + 1) * 4) & ((1 << (off + k - 32)) - 1)
		value = low | (high << (32 - off))
	ctx["bit_pos"] = pos + k
	return value


## Decode count LO bytes; each byte packs two tANS nibbles, low nibble first.
static func _decode_lo(ctx: Dictionary, table: Array, count: int) -> PackedByteArray:
	var out := PackedByteArray()
	for pair: int in count / 2:
		var value: int = 0
		for nibble: int in 4:
			value |= _tans_step(ctx, table) << (nibble * 4)
		out.append(value & 0xFF)
		out.append((value >> 8) & 0xFF)
	if count % 2 != 0:
		var value: int = 0
		for nibble: int in 2:
			value |= _tans_step(ctx, table) << (nibble * 4)
		out.append(value & 0xFF)
	return out


## Decode count u16 symbols; each u16 packs four tANS nibbles. With delta encoding,
## each nibble adds to a running value (mod 16) instead of replacing it.
static func _decode_sym(ctx: Dictionary, table: Array, count: int, delta: bool) -> PackedByteArray:
	var out := PackedByteArray()
	var curr: int = 0
	for pair: int in count / 2:
		var value: int = 0
		for nibble: int in 8:
			var step: int = _tans_step(ctx, table)
			curr = (curr + step) & 0xF if delta else step
			value |= curr << (nibble * 4)
		out.append(value & 0xFF)
		out.append((value >> 8) & 0xFF)
		out.append((value >> 16) & 0xFF)
		out.append((value >> 24) & 0xFF)
	if count % 2 != 0:
		var value: int = 0
		for nibble: int in 4:
			var step: int = _tans_step(ctx, table)
			curr = (curr + step) & 0xF if delta else step
			value |= curr << (nibble * 4)
		out.append(value & 0xFF)
		out.append((value >> 8) & 0xFF)
	return out


## Build the 64-entry tANS decode table from three packed frequency u32s. Each packed
## word holds five 6-bit frequencies; the top two bits of each word add into symbol 15.
static func _tans_table(packed: Array) -> Array:
	var freqs: Array = []
	freqs.resize(16)
	freqs.fill(0)
	for i: int in 3:
		var word: int = packed[i]
		for j: int in 5:
			freqs[i * 5 + j] = (word >> (6 * j)) & 0x3F
		freqs[15] += (word & 0xC0000000) >> (30 - 2 * i)
	var table: Array = []
	table.resize(64)
	table.fill(0)
	var pos: int = 0
	for i: int in 16:
		var f: int = freqs[i]
		for j: int in f:
			table[pos] = _yk_template(f + j) | (i << 3)
			pos += 1
	return table


## One sYkTemplate entry: k = 7 - bit_length(n), y = (n << k) - 64, mask = (1 << k) - 1.
static func _yk_template(n: int) -> int:
	if n == 0:
		return 0
	var bits: int = 0
	var v: int = n
	while v > 0:
		bits += 1
		v >>= 1
	var k: int = 7 - bits
	var y: int = (n << k) - 64
	var mask: int = (1 << k) - 1
	return (k & 7) | (y << 8) | (mask << 16)
