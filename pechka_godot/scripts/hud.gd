class_name Hud
extends CanvasLayer

## Интерфейс. Шрифт — подключённый TTF с кириллицей, поэтому вместо букв
## никаких вопросительных знаков быть не может.

const CREAM := Color(0.96, 0.92, 0.84)
const DIM := Color(0.74, 0.70, 0.64)
const HOT := Color(1.0, 0.62, 0.25)
const TEMP_MAX := 1000.0

var _font: Font
var _font_bold: Font
var _temp_label: Label
var _temp_fill: ColorRect
var _stats: Label
var _air: Label
var _room: Label
var _flue: Label
var _sky: Label
var _fps: Label
var _frost: TextureRect
var _gas: TextureRect
var _toast: Label
var _toast_time := 0.0
var _slots: Array[Dictionary] = []
var _intro: Control
var _hint: Label
var _chrome: Array[Control] = []   ## панели и прицел — их снимаем на скриншотах
var _chrome_on := true
var _award: Control
var _award_title: Label
var _award_sub: Label
var _award_time := 0.0
var _temp_grad: Gradient
var _quest: Panel
var _quest_step: Label
var _quest_text: Label
var _quest_hint: Label
var _quest_key: Label
var _quest_tick: Label
var _quest_flash := 0.0


func _ready() -> void:
	layer = 10
	_build_temp_gradient()
	_font = _load_font("res://assets/fonts/ui.ttf")
	_font_bold = _load_font("res://assets/fonts/ui_bold.ttf")
	if _font_bold == null:
		_font_bold = _font


## Зоны градусника: до 100 зелёная, до 400 рабочая жёлтая, до 600 оранжевая,
## до 800 красный перегрев, выше — фиолетовое «плавится». Между зонами узкие
## переходы, чтобы цвет не прыгал ступенькой.
func _build_temp_gradient() -> void:
	const GREEN := Color(0.40, 0.84, 0.38)
	const YELLOW := Color(0.95, 0.86, 0.28)
	const ORANGE := Color(1.00, 0.56, 0.14)
	const RED := Color(0.94, 0.22, 0.14)
	const PURPLE := Color(0.72, 0.34, 0.96)
	_temp_grad = Gradient.new()
	_temp_grad.offsets = PackedFloat32Array([
		0.0, 0.10, 0.15, 0.40, 0.44, 0.60, 0.64, 0.80, 0.84, 1.0
	])
	_temp_grad.colors = PackedColorArray([
		GREEN, GREEN, YELLOW, YELLOW, ORANGE, ORANGE, RED, RED, PURPLE, PURPLE
	])


func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		return ResourceLoader.load(path) as Font
	return null


func build(tool_names: Array, tool_keys: Array) -> void:
	_build_gas()   # пелена лежит под панелями, иначе она закрасит цифры
	_build_frost()
	_build_panel_left()
	_build_quest()
	_build_toolbar(tool_names, tool_keys)
	_build_hints()
	_build_crosshair()
	_build_toast()
	_build_intro()


# ---------------------------------------------------------------- блоки

func _build_panel_left() -> void:
	var panel := _panel(Vector2(28, 24), Vector2(330, 250))
	add_child(panel)
	_chrome.append(panel)

	var title := _label("ПЕЧКА", 30, CREAM, _font_bold)
	title.position = Vector2(18, 10)
	panel.add_child(title)

	var sub := _label("сложи из кирпича и затопи", 15, DIM, _font)
	sub.position = Vector2(20, 46)
	panel.add_child(sub)

	_temp_label = _label("20 °C", 20, CREAM, _font_bold)
	_temp_label.position = Vector2(20, 74)
	panel.add_child(_temp_label)

	var track := ColorRect.new()
	track.color = Color(0.12, 0.10, 0.09, 0.85)
	track.position = Vector2(20, 102)
	track.size = Vector2(270, 10)
	panel.add_child(track)

	_temp_fill = ColorRect.new()
	_temp_fill.color = HOT
	_temp_fill.position = Vector2(0, 0)
	_temp_fill.size = Vector2(0, 10)
	track.add_child(_temp_fill)

	_stats = _label("", 15, DIM, _font)
	_stats.position = Vector2(20, 118)
	panel.add_child(_stats)

	_air = _label("", 15, DIM, _font)
	_air.position = Vector2(20, 140)
	panel.add_child(_air)

	_room = _label("", 15, DIM, _font)
	_room.position = Vector2(20, 162)
	panel.add_child(_room)

	_flue = _label("", 15, DIM, _font)
	_flue.position = Vector2(20, 184)
	panel.add_child(_flue)

	_sky = _label("", 15, DIM, _font)
	_sky.position = Vector2(20, 206)
	panel.add_child(_sky)

	_fps = _label("", 13, Color(0.5, 0.52, 0.5), _font)
	_fps.position = Vector2(20, 228)
	panel.add_child(_fps)


## Панель обучения: один шаг за раз. Крупно — что делать, рядом — клавиша,
## мелко — зачем это нужно. Больше на экране ничего не надо: длинный список
## задач новичка пугает ровно так же, как стена текста.
func _build_quest() -> void:
	_quest = _panel(Vector2(28, 288), Vector2(330, 118))
	add_child(_quest)
	_chrome.append(_quest)

	_quest_step = _label("", 13, Color(0.86, 0.66, 0.28), _font)
	_quest_step.position = Vector2(18, 10)
	_quest.add_child(_quest_step)

	_quest_tick = _label("", 22, Color(0.45, 0.85, 0.42), _font_bold)
	_quest_tick.position = Vector2(286, 8)
	_quest.add_child(_quest_tick)

	_quest_text = _label("", 20, CREAM, _font_bold)
	_quest_text.position = Vector2(18, 32)
	_quest_text.size = Vector2(296, 26)
	_quest.add_child(_quest_text)

	_quest_key = _label("", 15, HOT, _font_bold)
	_quest_key.position = Vector2(18, 62)
	_quest.add_child(_quest_key)

	_quest_hint = _label("", 14, DIM, _font)
	_quest_hint.position = Vector2(18, 86)
	_quest_hint.size = Vector2(296, 20)
	_quest_hint.clip_text = true
	_quest.add_child(_quest_hint)
	_quest.visible = false


## Показать текущий шаг. Пустой словарь прячет панель — обучение кончилось.
func set_quest(cur: Dictionary, index: int, total: int) -> void:
	if _quest == null:
		return
	if cur.is_empty() or not _chrome_on:
		_quest.visible = false
		return
	_quest.visible = true
	_quest_step.text = "ОБУЧЕНИЕ · ШАГ %d ИЗ %d" % [index + 1, total]
	_quest_text.text = str(cur.get("text", ""))
	_quest_hint.text = str(cur.get("hint", ""))
	var key := str(cur.get("key", ""))
	_quest_key.text = ("клавиша %s, потом ЛКМ" % key) if key != "" else ""


## Галочка и зелёная вспышка на закрытом шаге: маленькая награда за каждое
## сделанное дело, без неё цепочка ощущается как список дел.
func quest_done() -> void:
	if _quest == null:
		return
	_quest_tick.text = "✓"
	_quest_flash = 0.9


func quest_hide() -> void:
	if _quest:
		_quest.visible = false


func _build_toolbar(tool_names: Array, tool_keys: Array) -> void:
	var count := tool_names.size()
	var w := 89.0
	var gap := 5.0
	var total := count * w + (count - 1) * gap

	var bar := Control.new()
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -total * 0.5
	bar.offset_right = total * 0.5
	bar.offset_top = -96
	bar.offset_bottom = -28
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	_chrome.append(bar)

	for i in count:
		var slot := Panel.new()
		slot.position = Vector2(i * (w + gap), 0)
		slot.size = Vector2(w, 68)
		slot.add_theme_stylebox_override("panel", _slot_style(false))
		bar.add_child(slot)

		var key := _label(str(tool_keys[i]), 20, DIM, _font_bold)
		key.position = Vector2(10, 6)
		slot.add_child(key)

		var name_label := _label(str(tool_names[i]), 14, CREAM, _font)
		name_label.position = Vector2(10, 38)
		name_label.size = Vector2(w - 14, 20)
		name_label.clip_text = true
		slot.add_child(name_label)

		_slots.append({"panel": slot, "key": key, "name": name_label})


func _build_hints() -> void:
	var lines := [
		"WASD — идти, Shift — бегом, пробел — прыжок",
		"ЛКМ — работать инструментом, Tab — вид сверху",
		"G — чертёж печки, R — повернуть кирпич",
		"B — перевязка, H — половинка",
		"Z — заслонка, N — время суток",
		"P — погода, O — время года",
		"X на предмете — убрать, C — сбросить всё",
		"F5 / F9 — сохранить и загрузить постройку",
		"F3 — качество, F4 — обучение, F1 — этот список",
		"M — звук, F2 — полёт камеры",
	]
	var panel := Panel.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -394
	panel.offset_right = -28
	panel.offset_top = 24
	panel.offset_bottom = 24 + lines.size() * 24 + 24
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	_chrome.append(panel)

	for i in lines.size():
		var l := _label(lines[i], 15, DIM, _font)
		l.position = Vector2(16, 12 + i * 24)
		panel.add_child(l)
	_hint = _label("", 15, DIM, _font)
	panel.add_child(_hint)
	_hint.visible = false
	_hint.set_meta("panel", panel)


func _build_crosshair() -> void:
	var c := Control.new()
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.anchor_top = 0.5
	c.anchor_bottom = 0.5
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	_chrome.append(c)
	for r in [Vector2(-9, -1), Vector2(3, -1)]:
		var h := ColorRect.new()
		h.color = Color(1, 1, 1, 0.35)
		h.position = r
		h.size = Vector2(6, 2)
		c.add_child(h)
	for r2 in [Vector2(-1, -9), Vector2(-1, 3)]:
		var v := ColorRect.new()
		v.color = Color(1, 1, 1, 0.35)
		v.position = r2
		v.size = Vector2(2, 6)
		c.add_child(v)


func _build_toast() -> void:
	_toast = _label("", 19, CREAM, _font_bold)
	_toast.anchor_left = 0.0
	_toast.anchor_right = 1.0
	_toast.anchor_top = 1.0
	_toast.anchor_bottom = 1.0
	_toast.offset_top = -138
	_toast.offset_bottom = -110
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_child(_toast)


func _build_intro() -> void:
	_intro = Control.new()
	_intro.anchor_right = 1.0
	_intro.anchor_bottom = 1.0
	add_child(_intro)

	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.035, 0.03, 0.78)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	_intro.add_child(bg)

	var card := Panel.new()
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -330
	card.offset_right = 330
	card.offset_top = -180
	card.offset_bottom = 180
	card.add_theme_stylebox_override("panel", _panel_style())
	_intro.add_child(card)

	var t := _label("ПЕЧКА", 52, CREAM, _font_bold)
	t.position = Vector2(40, 34)
	card.add_child(t)

	# Первый экран обязан помещаться в голову с одного взгляда. Всё
	# остальное расскажет обучение по ходу дела, а полный список клавиш
	# висит справа и прячется на F1.
	var lines := [
		"В сарае холодно. Растопи печь и согрейся.",
		"Игра проведёт по шагам — просто делай, что написано слева.",
		"",
		"WASD — идти · мышь — смотреть · ЛКМ — работать",
		"F1 — все клавиши · F3 — качество картинки",
	]
	for i in lines.size():
		var l := _label(lines[i], 20, DIM, _font)
		l.position = Vector2(40, 124 + i * 32)
		l.size = Vector2(580, 26)
		card.add_child(l)

	var go := _label("Нажми любую кнопку", 22, HOT, _font_bold)
	go.position = Vector2(40, 300)
	card.add_child(go)


# ---------------------------------------------------------------- обновление

func set_tool(idx: int) -> void:
	for i in _slots.size():
		var active := i == idx
		var d := _slots[i]
		(d["panel"] as Panel).add_theme_stylebox_override("panel", _slot_style(active))
		(d["key"] as Label).add_theme_color_override("font_color", HOT if active else DIM)
		(d["name"] as Label).add_theme_color_override("font_color", CREAM if active else DIM)


func update_stats(temp: float, bricks: int, cemented: int, burning: int, rot: bool, bond: bool,
		plan_left := -1, plan_total := 0) -> void:
	_temp_label.text = "%d °C" % roundi(temp)
	var t: float = clampf(temp / TEMP_MAX, 0.0, 1.0)
	var c := _temp_grad.sample(t)
	_temp_fill.size.x = 270.0 * clampf((temp - 20.0) / (TEMP_MAX - 20.0), 0.0, 1.0)
	_temp_fill.color = c
	_temp_label.add_theme_color_override("font_color", c)
	var bond_text := "перевязка" if bond else "в стык"
	var rot_text := "поперёк" if rot else "вдоль"
	_stats.text = "кирпичей %d · на цементе %d · горит %d · %s · %s" % [bricks, cemented, burning, rot_text, bond_text]
	# когда чертёж включён, важнее всего — сколько кирпичей ещё не хватает
	if plan_left >= 0:
		_stats.text = "по чертежу сложено %d из %d · осталось %d" % [
			plan_total - plan_left, plan_total, plan_left]


## Строка про воздух: какая тяга, в каком положении заслонка и не завалило ли
## сарай дымом. Дым в сарае подсвечиваем — это уже беда, а не статистика.
func update_air(draught: float, damper: String, haze: float, dust: float,
		press: float = 0.0) -> void:
	var bar := "тяга %d%% · заслонка %s" % [roundi(draught * 100.0), damper]
	# давление главнее всего остального: если его проморгать, трубы не будет
	if press > 0.02:
		_air.text = "%s · ДАВЛЕНИЕ %d%%" % [bar, roundi(press * 100.0)]
		_air.add_theme_color_override("font_color",
			Color(1.0, 0.8, 0.3).lerp(Color(1.0, 0.18, 0.12), press))
		return
	if haze > 0.06:
		bar += " · ДЫМ В САРАЕ"
	# пыль опаснее дыма, поэтому её предупреждение и цвет главнее
	if dust > 0.1:
		bar += " · УГОЛЬНАЯ ПЫЛЬ %d%%" % roundi(dust * 100.0)
		_air.add_theme_color_override("font_color", Color(1.0, 0.72, 0.2).lerp(
			Color(1.0, 0.16, 0.1), clampf(dust, 0.0, 1.0)))
	elif haze > 0.06:
		_air.add_theme_color_override("font_color", Color(1.0, 0.45, 0.3).lerp(
			Color(1.0, 0.2, 0.15), clampf(haze, 0.0, 1.0)))
	else:
		_air.add_theme_color_override("font_color", DIM)
	_air.text = bar


func toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	_toast_time = 2.2


## Плашка достижения: выезжает сверху, висит и уходит.
## Погода, тепло в сарае и цель протопить его до жилого.
func update_room(room: float, outside: float, weather: String, goal: bool) -> void:
	_room.text = "в сарае %+d °C · на дворе %+d °C · %s" % [roundi(room), roundi(outside), weather]
	if goal:
		_room.add_theme_color_override("font_color", Color(0.55, 0.85, 0.5))
	elif room < 5.0:
		_room.add_theme_color_override("font_color", Color(0.55, 0.72, 1.0))
	else:
		_room.add_theme_color_override("font_color", DIM)


## Состояние трубы: сажа, угар и пожар в дымоходе.
func update_flue(soot: float, co: float, flue_fire: bool, retain: float) -> void:
	var parts := ["сажа %d%%" % roundi(soot * 100.0), "дымообороты %d%%" % roundi(retain * 100.0)]
	var color := DIM
	if co > 0.08:
		parts.append("УГАР %d%%" % roundi(co * 100.0))
		color = Color(0.85, 0.72, 0.35).lerp(Color(1.0, 0.25, 0.2), clampf(co, 0.0, 1.0))
	if flue_fire:
		parts.append("ТРУБА ГОРИТ")
		color = Color(1.0, 0.35, 0.15)
	elif soot > 0.7 and co <= 0.08:
		color = Color(0.9, 0.6, 0.3)
	_flue.text = " · ".join(parts)
	_flue.add_theme_color_override("font_color", color)


## Строка погоды: сезон, что на дворе, ветер по Бофорту и видимость.
func update_sky(w: PechWeather) -> void:
	if w == null:
		return
	var vis := w.visibility()
	var vtext := "%d км" % roundi(vis / 1000.0) if vis >= 950.0 else "%d м" % roundi(vis)
	_sky.text = "%s · %s · ветер %d б (%s) · видно %s" % [
		w.season_name(), w.phase_name(), roundi(w.beaufort), w.wind_name(), vtext]
	var c := DIM
	if w.beaufort >= 9.0:
		c = Color(1.0, 0.45, 0.3)
	elif w.beaufort >= 6.0:
		c = Color(0.9, 0.75, 0.4)
	elif vis < 300.0:
		c = Color(0.65, 0.75, 0.9)
	_sky.add_theme_color_override("font_color", c)


func update_fps(fps: float, pieces: int) -> void:
	_fps.text = "%d кадр/с · предметов %d" % [roundi(fps), pieces]


## Мороз и вода: по краям экрана нарастает иней, поверх — капли дождя.
func set_chill(chill: float, soaked: float) -> void:
	if _frost == null:
		return
	_frost.visible = chill > 0.04 or soaked > 0.15
	_frost.modulate = Color(0.82, 0.92, 1.0, clampf(chill * 0.75 + soaked * 0.2, 0.0, 0.85))


func _build_frost() -> void:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_CELLULAR
	fn.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	fn.frequency = 0.045
	fn.seed = 1204
	for y in n:
		for x in n:
			var u := (float(x) / float(n - 1) - 0.5) * 2.0
			var v := (float(y) / float(n - 1) - 0.5) * 2.0
			# иней садится с краёв, середину игрок продышал
			var edge := clampf((sqrt(u * u + v * v) - 0.45) / 0.75, 0.0, 1.0)
			var c := clampf(fn.get_noise_2d(float(x), float(y)) * 0.5 + 0.5, 0.0, 1.0)
			var a := pow(edge, 1.6) * pow(c, 2.2)
			img.set_pixel(x, y, Color(0.92, 0.97, 1.0, clampf(a, 0.0, 1.0)))

	_frost = TextureRect.new()
	_frost.texture = ImageTexture.create_from_image(img)
	_frost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frost.stretch_mode = TextureRect.STRETCH_SCALE
	_frost.anchor_right = 1.0
	_frost.anchor_bottom = 1.0
	_frost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frost.visible = false
	add_child(_frost)


## Пелена перед глазами от угарного газа.
func set_gas(x: float) -> void:
	if _gas == null:
		return
	_gas.visible = x > 0.02
	_gas.modulate.a = clampf(x, 0.0, 1.0) * 0.92


func _build_gas() -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.42, 1.0])
	g.colors = PackedColorArray([
		Color(0.35, 0.22, 0.12, 0.0), Color(0.35, 0.22, 0.12, 0.45), Color(0.22, 0.12, 0.06, 1.0),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256

	_gas = TextureRect.new()
	_gas.texture = gt
	_gas.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_gas.stretch_mode = TextureRect.STRETCH_SCALE
	_gas.anchor_right = 1.0
	_gas.anchor_bottom = 1.0
	_gas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gas.visible = false
	add_child(_gas)


## Убрать всю обвязку интерфейса: для красивых кадров нужен только мир.
func chrome(on: bool) -> void:
	_chrome_on = on
	for c in _chrome:
		c.visible = on


func hide_toast() -> void:
	_toast.modulate.a = 0.0
	_toast_time = 0.0


func achievement(title: String, subtitle: String) -> void:
	if _award == null:
		_award = Control.new()
		_award.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_award.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_award)

		var card := Panel.new()
		card.position = Vector2(-250, 0)
		card.size = Vector2(500, 118)
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.10, 0.075, 0.05, 0.94)
		s.border_color = Color(0.86, 0.66, 0.28)
		s.set_border_width_all(2)
		s.set_corner_radius_all(10)
		s.shadow_color = Color(0, 0, 0, 0.6)
		s.shadow_size = 14
		card.add_theme_stylebox_override("panel", s)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_award.add_child(card)

		var cap := _label("ДОСТИЖЕНИЕ ПОЛУЧЕНО", 14, Color(0.86, 0.66, 0.28), _font)
		cap.position = Vector2(24, 16)
		card.add_child(cap)

		_award_title = _label("", 30, CREAM, _font_bold)
		_award_title.position = Vector2(24, 38)
		card.add_child(_award_title)

		_award_sub = _label("", 16, DIM, _font)
		_award_sub.position = Vector2(24, 82)
		card.add_child(_award_sub)

	_award_title.text = title
	_award_sub.text = subtitle
	_award.visible = true
	_award.modulate.a = 0.0
	_award.position.y = -40
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_award, "modulate:a", 1.0, 0.35)
	tw.tween_property(_award, "position:y", 26.0, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_award_time = 11.0


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time < 0.6:
			_toast.modulate.a = _toast_time / 0.6
		if _toast_time <= 0.0:
			_toast.modulate.a = 0.0
	if _quest_flash > 0.0:
		_quest_flash = maxf(0.0, _quest_flash - delta)
		_quest.modulate = Color(1, 1, 1).lerp(Color(0.6, 1.0, 0.6), _quest_flash)
		if _quest_flash <= 0.0:
			_quest.modulate = Color(1, 1, 1)
			_quest_tick.text = ""
	if _award_time > 0.0:
		_award_time -= delta
		if _award_time < 1.2:
			_award.modulate.a = maxf(_award_time / 1.2, 0.0)
		if _award_time <= 0.0:
			_award.visible = false


func hide_achievement() -> void:
	_award_time = 0.0
	if _award:
		_award.visible = false


func intro_visible() -> bool:
	return _intro != null and _intro.visible


func hide_intro() -> void:
	if _intro:
		_intro.visible = false


func toggle_hints() -> void:
	var panel: Control = _hint.get_meta("panel")
	panel.visible = not panel.visible


# ---------------------------------------------------------------- стиль

func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.07, 0.06, 0.72)
	s.border_color = Color(0.45, 0.36, 0.26, 0.55)
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 8
	return s


func _slot_style(active: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.16, 0.11, 0.07, 0.88) if active else Color(0.07, 0.065, 0.06, 0.66)
	s.border_color = HOT if active else Color(0.4, 0.34, 0.26, 0.5)
	s.set_border_width_all(2 if active else 1)
	s.set_corner_radius_all(7)
	return s


func _panel(pos: Vector2, size: Vector2) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = size
	p.add_theme_stylebox_override("panel", _panel_style())
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _label(text: String, size: int, color: Color, font: Font) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
