extends RefCounted

## Original, small PCM cues keep the game self-contained without external recordings.

const RATE := 22050


## Whole waveform periods make the quiet engine loop seamless.
static func engine() -> AudioStreamWAV:
	var stream := _tone([80.0], 0.25, true)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = stream.data.size() / 2
	return stream


## Meaningful events also receive visible feedback and the shell's audio captions.
static func cues() -> Dictionary[String, AudioStreamWAV]:
	return {
		"jump": _tone([261.63, 392.0], 0.055),
		"plug": _tone([659.25, 987.77], 0.10),
		"checkpoint": _tone([392.0, 523.25, 659.25], 0.09),
		"crash": _tone([110.0, 73.42], 0.15),
		"recover": _tone([196.0, 293.66], 0.10),
		"finish": _tone([523.25, 659.25, 783.99, 1046.5], 0.14),
	}


static func _tone(notes: Array, duration: float, looping := false) -> AudioStreamWAV:
	var samples_per_note := roundi(RATE * duration)
	var data := PackedByteArray()
	data.resize(samples_per_note * notes.size() * 2)
	for note in notes.size():
		for sample in samples_per_note:
			var time := float(sample) / RATE
			var phase := TAU * float(notes[note]) * time
			var envelope := 0.25 if looping else \
				minf(time * 70.0, 1.0) * pow(1.0 - float(sample) / samples_per_note, 1.5)
			var wave := sin(phase) * 0.55 + sin(phase * 2.0) * 0.22 + sin(phase * 3.0) * 0.10
			data.encode_s16((note * samples_per_note + sample) * 2,
				roundi(wave * envelope * 12000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream
