class_name Sfx
extends Node3D

## Звук печки. Ни одного wav-файла в проекте нет: как и текстуры частиц, все
## шумы, щелчки и гул считаются кодом при запуске. Треск огня, гул в трубе и
## ветер — зацикленные петли с плавным стыком, остальное — короткие выстрелы.

const RATE := 22050
const POOL := 8

var muted := false

var _fire: AudioStreamPlayer3D
var _flue: AudioStreamPlayer3D
var _wind: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer3D] = []
var _next := 0

var _clacks: Array[AudioStreamWAV] = []
var _splat: AudioStreamWAV
var _pour: AudioStreamWAV
var _strike: AudioStreamWAV
var _flare: AudioStreamWAV
var _hiss: AudioStreamWAV
var _crash: AudioStreamWAV
var _boom: AudioStreamWAV
var _steps: Array[AudioStreamWAV] = []

var _steam: AudioStreamPlayer3D
var _whistle: AudioStreamPlayer3D

var _rain: AudioStreamPlayer        ## шум дождя по двору
var _roof: AudioStreamPlayer        ## стук капель по кровле — слышно только внутри
var _howl: AudioStreamPlayer        ## вой ветра в щелях
var _thunders: Array[AudioStreamWAV] = []
var _rain_want := 0.0
var _rain_now := 0.0
var _roof_want := 0.0
var _roof_now := 0.0
var _howl_want := 0.0
var _howl_now := 0.0
var _rain_pitch := 1.0

var _fire_want := 0.0
var _fire_now := 0.0
var _flue_want := 0.0
var _flue_now := 0.0
var _steam_want := 0.0
var _steam_now := 0.0
var _whistle_want := 0.0
var _whistle_now := 0.0
var _flare_cd := 0.0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260915

	for i in 3:
		_clacks.append(_clack_stream(rng, 700.0 + float(i) * 210.0))
	_splat = _splat_stream(rng)
	_pour = _pour_stream(rng)
	_strike = _strike_stream(rng)
	_flare = _flare_stream(rng)
	_hiss = _hiss_stream(rng)
	_crash = _crash_stream(rng)
	_boom = _boom_stream(rng)
	for i in 3:
		_steps.append(_step_stream(rng))

	_fire = _loop_player(_fire_stream(rng), 3.0, 20.0)
	_flue = _loop_player(_flue_stream(rng), 4.5, 26.0)
	_steam = _loop_player(_steam_stream(rng), 1.6, 12.0)
	_whistle = _loop_player(_whistle_stream(rng), 2.2, 24.0)

	_wind = AudioStreamPlayer.new()
	_wind.stream = _wind_stream(rng)
	_wind.volume_db = linear_to_db(0.16)
	add_child(_wind)
	_wind.play()

	# погода звучит поверх всего и без места в пространстве: она везде
	_rain = _flat_loop(_rain_stream(rng))
	_roof = _flat_loop(_roof_stream(rng))
	_howl = _flat_loop(_howl_stream(rng))
	for i in 3:
		_thunders.append(_thunder_stream(rng, i))

	for i in POOL:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 3.0
		p.max_distance = 22.0
		add_child(p)
		_pool.append(p)


func _loop_player(stream: AudioStreamWAV, unit: float, dist: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.unit_size = unit
	p.max_distance = dist
	p.volume_db = -80.0
	add_child(p)
	return p


func _process(delta: float) -> void:
	_flare_cd = maxf(0.0, _flare_cd - delta)
	_fire_now = lerpf(_fire_now, _fire_want, 1.0 - exp(-delta * 4.0))
	_flue_now = lerpf(_flue_now, _flue_want, 1.0 - exp(-delta * 2.5))
	_steam_now = lerpf(_steam_now, _steam_want, 1.0 - exp(-delta * 3.0))
	# свисток набирает голос не сразу, как настоящий
	_whistle_now = lerpf(_whistle_now, _whistle_want, 1.0 - exp(-delta * 1.4))
	_drive(_fire, _fire_now, 1.12, 0.9)
	_drive(_flue, _flue_now, 1.06, 0.88)
	_drive(_steam, _steam_now * 0.55, 1.05, 0.95)
	_drive(_whistle, _whistle_now * 0.4, 0.97, 1.03)
	_wind.volume_db = -80.0 if muted else linear_to_db(0.16)

	_rain_now = lerpf(_rain_now, _rain_want, 1.0 - exp(-delta * 2.2))
	_roof_now = lerpf(_roof_now, _roof_want, 1.0 - exp(-delta * 2.2))
	_howl_now = lerpf(_howl_now, _howl_want, 1.0 - exp(-delta * 1.2))
	_drive_flat(_rain, _rain_now * 0.5, _rain_pitch)
	_drive_flat(_roof, _roof_now * 0.55, _rain_pitch)
	_drive_flat(_howl, _howl_now * 0.42, 0.8 + _howl_now * 0.5)


## Чем больше огня, тем громче и басовитее его голос.
## Петля без места в пространстве: погода звучит одинаково по всему двору.
func _flat_loop(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = -80.0
	add_child(p)
	return p


func _drive_flat(p: AudioStreamPlayer, vol: float, pitch: float) -> void:
	if p == null:
		return
	if vol < 0.008 or muted:
		if p.playing:
			p.stop()
		return
	p.pitch_scale = pitch
	p.volume_db = linear_to_db(clampf(vol, 0.0, 1.0))
	if not p.playing:
		p.play()


## Погода за кадром: сила осадков, слышно ли крышу над головой и вой ветра.
## Крупный град и ливень отличаются не громкостью, а высотой стука.
func set_weather_sound(rain: float, indoors: bool, wind: float, hail: bool) -> void:
	_rain_want = clampf(rain, 0.0, 1.0)
	_roof_want = clampf(rain, 0.0, 1.0) * (1.0 if indoors else 0.25)
	_howl_want = clampf((wind - 0.25) / 0.75, 0.0, 1.0)
	_rain_pitch = 1.35 if hail else lerpf(1.05, 0.85, clampf(rain, 0.0, 1.0))


## Раскат грома. Дальний идёт глухо и долго, близкий бьёт сухо и коротко.
func thunder(power: float, at: Vector3) -> void:
	if _thunders.is_empty():
		return
	var i := 2 if power > 0.7 else (1 if power > 0.35 else 0)
	var p := _shot(_thunders[i], at, clampf(0.35 + power, 0.3, 1.0), randf_range(0.9, 1.08))
	if p != null:
		# гром слышно отовсюду, поэтому дальность у него не как у щелчка кирпича
		p.max_distance = 400.0
		p.unit_size = 60.0


func _drive(p: AudioStreamPlayer3D, vol: float, pitch_lo: float, pitch_hi: float) -> void:
	if vol < 0.01 or muted:
		if p.playing:
			p.stop()
		return
	p.pitch_scale = lerpf(pitch_lo, pitch_hi, clampf(vol, 0.0, 1.0))
	p.volume_db = linear_to_db(clampf(vol, 0.0, 1.0))
	if not p.playing:
		p.play()


# ---------------------------------------------------------------- управление

func set_fire(pos: Vector3, loud: float) -> void:
	_fire_want = clampf(loud, 0.0, 1.0)
	if _fire_want > 0.005:
		_fire.global_position = pos


func set_flue(pos: Vector3, loud: float) -> void:
	_flue_want = clampf(loud, 0.0, 1.0)
	if _flue_want > 0.005:
		_flue.global_position = pos


## Чайник: сперва шелест пара, на закипании — свисток.
func set_kettle(pos: Vector3, steam: float, whistle: float) -> void:
	_steam_want = clampf(steam, 0.0, 1.0)
	_whistle_want = clampf(whistle, 0.0, 1.0)
	if _steam_want > 0.005:
		_steam.global_position = pos
	if _whistle_want > 0.005:
		_whistle.global_position = pos


func clack(pos: Vector3, vol := 1.0) -> void:
	_shot(_clacks[randi() % _clacks.size()], pos, vol, randf_range(0.92, 1.1))


func splat(pos: Vector3) -> void:
	_shot(_splat, pos, 0.9, randf_range(0.94, 1.08))


func pour(pos: Vector3) -> void:
	_shot(_pour, pos, 0.75, randf_range(0.9, 1.12))


func strike(pos: Vector3) -> void:
	_shot(_strike, pos, 0.85, randf_range(0.95, 1.06))


## Вспышка при загорании. Пучок травы ухает громко и низко, щепка — коротко.
func flare(pos: Vector3, big := false) -> void:
	if _flare_cd > 0.0:
		return
	_flare_cd = 0.09
	_shot(_flare, pos, 0.9 if big else 0.45, randf_range(0.8, 0.95) if big else randf_range(1.1, 1.35))


func hiss(pos: Vector3) -> void:
	_shot(_hiss, pos, 0.7, randf_range(0.92, 1.1))


func crash(pos: Vector3, vol := 1.0) -> void:
	_shot(_crash, pos, vol, randf_range(0.88, 1.06))


func boom(pos: Vector3) -> void:
	_shot(_boom, pos, 1.0, randf_range(0.94, 1.04))


func step(pos: Vector3, running: bool) -> void:
	_shot(_steps[randi() % _steps.size()], pos,
		0.5 if running else 0.32, randf_range(0.9, 1.12))


func _shot(stream: AudioStreamWAV, pos: Vector3, vol: float, pitch: float) -> AudioStreamPlayer3D:
	if muted:
		return null
	var p := _pool[_next]
	_next = (_next + 1) % POOL
	# после грома дальность приходится возвращать: игрок один, а голоса общие
	p.max_distance = 22.0
	p.unit_size = 3.0
	p.stream = stream
	p.global_position = pos
	p.pitch_scale = pitch
	p.volume_db = linear_to_db(clampf(vol, 0.01, 1.0))
	p.play()
	return p


# ---------------------------------------------------------------- синтез

## Огонь: глухой рёв в низах, шелест пламени сверху и сухие щелчки поленьев.
func _fire_stream(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var xf := RATE / 4
	var n := RATE * 4 + xf
	var s := PackedFloat32Array()
	s.resize(n)
	var low := 0.0
	var mid := 0.0
	for i in n:
		var w := rng.randf_range(-1.0, 1.0)
		low += (w - low) * 0.012
		mid += (w - mid) * 0.13
		s[i] = low * 3.4 + mid * 0.2
	_crackle(s, rng, int(float(n) / RATE * 17.0), 0.1, 0.5)
	return _wav(_seamless(s, xf), true, 0.85)


## Тяга в трубе: ровный низкий гул, который медленно дышит.
func _flue_stream(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var xf := RATE / 4
	var n := RATE * 3 + xf
	var s := PackedFloat32Array()
	s.resize(n)
	var low := 0.0
	for i in n:
		var t := float(i) / RATE
		low += (rng.randf_range(-1.0, 1.0) - low) * 0.005
		s[i] = low * (0.72 + 0.28 * sin(TAU * 0.17 * t))
	return _wav(_seamless(s, xf), true, 0.8)


## Ветер в щелях сарая: порывами, чтобы фон не был мёртвым.
func _wind_stream(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var xf := RATE / 2
	var n := RATE * 8 + xf
	var s := PackedFloat32Array()
	s.resize(n)
	var low := 0.0
	for i in n:
		var t := float(i) / RATE
		low += (rng.randf_range(-1.0, 1.0) - low) * 0.035
		var gust := 0.5 + 0.5 * sin(TAU * 0.08 * t + sin(TAU * 0.033 * t) * 1.8)
		s[i] = low * (0.3 + 0.7 * gust * gust)
	return _wav(_seamless(s, xf), true, 0.7)


## Свисток чайника. Частоты взяты кратными длине петли, поэтому она сходится
## сама и тон не «квакает» на стыке.
func _whistle_stream(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var xf := RATE / 4
	var n := RATE + xf
	var s := PackedFloat32Array()
	s.resize(n)
	var breath := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 2180.0 * (1.0 + 0.004 * sin(TAU * 5.0 * t))
		breath += (rng.randf_range(-1.0, 1.0) - breath) * 0.5
		s[i] = sin(TAU * f * t) * 0.55 + sin(TAU * f * 2.0 * t) * 0.15 \
			+ sin(TAU * f * 3.0 * t) * 0.05 + breath * 0.1
	return _wav(_seamless(s, xf), true, 0.8)


## Пар из носика: ровный мягкий шелест.
func _steam_stream(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var xf := RATE / 4
	var n := RATE * 3 + xf
	var s := PackedFloat32Array()
	s.resize(n)
	var prev := 0.0
	var band := 0.0
	for i in n:
		var w := rng.randf_range(-1.0, 1.0)
		var hp := w - prev
		prev = w
		band += (hp - band) * 0.35
		s[i] = band
	return _wav(_seamless(s, xf), true, 0.7)


## Кирпич о кирпич: сухой стук с двумя призвуками.
func _clack_stream(rng: RandomNumberGenerator, f: float) -> AudioStreamWAV:
	var n := int(0.2 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var e: float = exp(-t * 44.0)
		var body := sin(TAU * f * t) * 0.6 + sin(TAU * f * 2.7 * t) * 0.22
		s[i] = body * e + rng.randf_range(-1.0, 1.0) * exp(-t * 300.0) * 0.8
	return _wav(s, false, 0.9)


## Цемент: мокрый шлепок мастерка.
func _splat_stream(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(0.32 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.22
		s[i] = lp * exp(-t * 15.0) * minf(t * 240.0, 1.0)
	return _wav(s, false, 0.85)


## Сыпучее: шорох плюс мелкие удары отдельных щепок и пучков.
func _pour_stream(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(0.5 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		var rough := w - prev
		prev = w
		s[i] = rough * 0.35 * sin(PI * clampf(t / 0.5, 0.0, 1.0))
	_crackle(s, rng, 55, 0.08, 0.3)
	return _wav(s, false, 0.8)


## Спичка о коробок: короткий шершавый чирк.
func _strike_stream(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(0.3 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		var rough := w - prev
		prev = w
		s[i] = rough * exp(-t * 20.0) * minf(t * 80.0, 1.0)
	return _wav(s, false, 0.85)


## Вспышка: «ух», у которого низы приходят с запозданием.
func _flare_stream(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(0.75 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var a := lerpf(0.045, 0.34, clampf(t / 0.35, 0.0, 1.0))
		lp += (rng.randf_range(-1.0, 1.0) - lp) * a
		s[i] = lp * sin(PI * clampf(t / 0.75, 0.0, 1.0))
	return _wav(s, false, 0.9)


## Шипение сырого топлива.
func _hiss_stream(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(0.55 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var prev := 0.0
	var band := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		var hp := w - prev
		prev = w
		band += (hp - band) * 0.55
		s[i] = band * sin(PI * clampf(t / 0.55, 0.0, 1.0))
	return _wav(s, false, 0.75)


## Обвал кладки: низкий удар и осыпающаяся крошка.
func _crash_stream(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(1.0 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var low := 0.0
	for i in n:
		var t := float(i) / RATE
		low += (rng.randf_range(-1.0, 1.0) - low) * 0.02
		s[i] = low * 2.6 * exp(-t * 6.5)
	_crackle(s, rng, 34, 0.12, 0.45)
	return _wav(s, false, 0.95)


## Шаг по земле: глухой тычок подошвы и шорох травы под ней.
func _step_stream(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(0.2 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var low := 0.0
	var f := rng.randf_range(58.0, 78.0)
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		low += (w - low) * 0.05
		s[i] = (low * 1.6 + sin(TAU * f * t) * 0.35) * exp(-t * 38.0) \
			+ w * 0.22 * exp(-t * 26.0)
	return _wav(s, false, 0.7)


## Взрыв угольной пыли: щелчок фронта, уходящий вниз тон и долгий раскат.
func _boom_stream(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(1.6 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var low := 0.0
	var mid := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		low += (w - low) * 0.016
		mid += (w - mid) * 0.09
		# тон сползает с 90 до 28 Гц — это и читается как «рвануло»
		phase += TAU * lerpf(90.0, 28.0, minf(t / 0.7, 1.0)) / RATE
		var punch: float = exp(-t * 3.2)
		var crack: float = exp(-t * 120.0)
		s[i] = sin(phase) * 0.7 * punch + low * 2.2 * punch \
			+ mid * 0.5 * crack + w * 0.35 * crack
	_crackle(s, rng, 26, 0.1, 0.4)
	return _wav(s, false, 0.98)


## Дождь по двору: ровный шелест из отфильтрованного шума, без отдельных
## капель — их ухо на таком расстоянии всё равно не различает.
func _rain_stream(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var xf := RATE / 2
	var n := RATE * 6 + xf
	var s := PackedFloat32Array()
	s.resize(n)
	var hp := 0.0
	var lp := 0.0
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		hp = w - prev
		prev = w
		lp += (hp - lp) * 0.42
		# дождь дышит: то припустит, то стихнет
		var swell := 0.75 + 0.25 * sin(TAU * 0.11 * t + sin(TAU * 0.037 * t) * 2.0)
		s[i] = lp * 1.4 * swell
	return _wav(_seamless(s, xf), true, 0.62)


## Стук по кровле: тот же дождь, но с частыми сухими щелчками по доскам.
func _roof_stream(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var xf := RATE / 2
	var n := RATE * 4 + xf
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var prev := 0.0
	for i in n:
		var w := rng.randf_range(-1.0, 1.0)
		var hp := w - prev
		prev = w
		lp += (hp - lp) * 0.3
		s[i] = lp * 0.8
	# по сотне капель в секунду — уже не капли, а барабан
	_crackle(s, rng, 420, 0.05, 0.22)
	return _wav(_seamless(s, xf), true, 0.7)


## Вой ветра в щелях: узкая полоса шума, гуляющая по высоте тона.
func _howl_stream(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var xf := RATE / 2
	var n := RATE * 7 + xf
	var s := PackedFloat32Array()
	s.resize(n)
	var b1 := 0.0
	var b2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		# два резонанса, как две щели разной ширины
		b1 += (w - b1) * 0.06
		b2 += (w - b2) * 0.013
		var swing := 0.5 + 0.5 * sin(TAU * 0.09 * t)
		var tone := sin(TAU * lerpf(210.0, 430.0, swing) * t) * 0.16
		s[i] = (b1 * 1.5 + b2 * 2.2) * (0.4 + 0.6 * swing) + tone * swing
	return _wav(_seamless(s, xf), true, 0.66)


## Гром: три голоса — дальний гул, средний раскат и близкий треск с эхом.
func _thunder_stream(rng: RandomNumberGenerator, near: int) -> AudioStreamWAV:
	var dur: float = [3.4, 2.8, 2.2][near]
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var low := 0.0
	var mid := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		low += (w - low) * [0.008, 0.013, 0.02][near]
		mid += (w - mid) * 0.07
		# дальний гром нарастает медленно, близкий бьёт сразу
		var attack: float = clampf(t / [0.5, 0.2, 0.02][near], 0.0, 1.0)
		var body: float = exp(-t * [1.1, 1.4, 1.9][near])
		var crack: float = exp(-t * 60.0) * float(near) * 0.5
		s[i] = (low * 3.2 + mid * 0.5 * float(near)) * attack * body + w * crack
	# раскаты: три отражения от холмов
	for k in 3:
		var at := int((0.35 + float(k) * 0.42) * RATE)
		var amp := 0.5 / float(k + 1)
		var dec := 0.9 + float(k) * 0.4
		var roll := 0.0
		for i in range(at, n):
			var t := float(i - at) / RATE
			roll += (rng.randf_range(-1.0, 1.0) - roll) * 0.01
			s[i] += roll * 2.4 * amp * exp(-t * dec)
	return _wav(s, false, 0.98)


## Подмешать в дорожку россыпь коротких затухающих щелчков.
func _crackle(s: PackedFloat32Array, rng: RandomNumberGenerator, count: int,
		lo: float, hi: float) -> void:
	var n := s.size()
	for k in count:
		var at := rng.randi_range(0, maxi(n - 900, 0))
		var amp := rng.randf_range(lo, hi)
		var dec := rng.randf_range(0.003, 0.018) * RATE
		var f := rng.randf_range(600.0, 2800.0)
		for j in mini(900, n - at):
			var e: float = exp(-float(j) / dec)
			if e < 0.002:
				break
			s[at + j] += sin(TAU * f * float(j) / RATE) * amp * e


## Хвост подмешиваем в начало: иначе петля щёлкает на стыке.
static func _seamless(s: PackedFloat32Array, xf: int) -> PackedFloat32Array:
	var n := s.size() - xf
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = s[i]
	for j in xf:
		var t := float(j) / float(xf)
		out[j] = s[j] * t + s[n + j] * (1.0 - t)
	return out


static func _wav(s: PackedFloat32Array, loop: bool, peak: float) -> AudioStreamWAV:
	var m := 0.0
	for v in s:
		m = maxf(m, absf(v))
	var k: float = (peak / m) if m > 0.0001 else 1.0
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i] * k, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w
