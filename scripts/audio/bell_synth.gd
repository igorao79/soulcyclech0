class_name SoulcycleBellSynth
extends RefCounted

# Удар колокола собран из негармонических обертонов, как и всё остальное — в коде.
static func create(pitch: float = 1.0) -> AudioStreamWAV:
	const RATE := 22050
	const PARTIALS := [
		[110.0, 1.00, 1.1], [220.0, 0.75, 1.5], [264.0, 0.55, 2.2],
		[331.0, 0.42, 2.8], [442.0, 0.30, 3.6], [587.0, 0.18, 5.0],
	]
	var count := RATE * 5
	var data := PackedByteArray()
	data.resize(count * 2)
	for index in range(count):
		var t := float(index) / RATE
		var value := 0.0
		for partial: Array in PARTIALS:
			value += sin(TAU * partial[0] * pitch * t) * partial[1] * exp(-t * partial[2])
		value *= 0.3 * minf(t * 200.0, 1.0)
		data.encode_s16(index * 2, int(clampf(value, -1.0, 1.0) * 32000.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream
