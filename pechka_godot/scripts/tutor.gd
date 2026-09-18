class_name Tutor
extends Node

## Обучение. Печка — игра про настоящую печь, и без провожатого новичок
## видит двенадцать инструментов и не знает, за что взяться. Поэтому вместо
## стены текста — цепочка коротких шагов сбоку экрана: что сделать, какой
## клавишей и куда смотреть. Шаг закрывается сам, как только дело сделано,
## никаких «нажми ОК». Вся цепочка — про один понятный результат: в сарае
## тепло.
##
## Проверки нарочно мягкие: игрок может делать всё не по порядку, и тогда
## шаги просто засчитаются пачкой. Наказывать за самодеятельность нельзя,
## иначе обучение превращается в клетку.

signal step_done(index: int)
signal finished

const FIREBOX := Vector3(0, PechWorld.BASE_Y + 0.12, 0.0)
const STOVE := Vector3(0, PechWorld.BASE_Y + 0.5, 0.0)

var active := true
var step := 0

var _g: PechGame
var _steps: Array[Dictionary] = []
var _cd := 0.0
var _seen_hot := false


static func create(game: PechGame) -> Tutor:
	var t := Tutor.new()
	t.name = "Tutor"
	t._g = game
	t._build()
	return t


func _build() -> void:
	_steps = [
		{
			"text": "Подойди к печке",
			"hint": "WASD — шагать, мышь — смотреть по сторонам",
			"key": "",
			"at": STOVE,
			"ok": func() -> bool:
				return _g.player.global_position.distance_to(STOVE) < 2.4,
		},
		{
			"text": "Открой заслонку",
			"hint": "без тяги дым пойдёт в сарай, а не в трубу",
			"key": "Z",
			"at": STOVE,
			"ok": func() -> bool:
				return _g.damper == 2,
		},
		{
			"text": "Брось в топку сухой травы",
			"hint": "трава — растопка: берётся легче всего",
			"key": "8",
			"tool": PechGame.Tool.HAY,
			"at": FIREBOX,
			"ok": func() -> bool:
				return _in_box(Piece.Kind.HAY) >= 2,
		},
		{
			"text": "Чиркни спичкой по траве",
			"hint": "целься в топку и жми левую кнопку мыши",
			"key": "5",
			"tool": PechGame.Tool.MATCH,
			"at": FIREBOX,
			"ok": func() -> bool:
				return _g._n_burning > 0 or _g.stove_temp > 60.0,
		},
		{
			"text": "Подкинь щепок, потом дров",
			"hint": "трава сгорает мигом, жар дают щепки",
			"key": "9",
			"tool": PechGame.Tool.CHIP,
			"at": FIREBOX,
			"ok": func() -> bool:
				return _in_box(Piece.Kind.CHIP) >= 3 or _g.stove_temp > 260.0,
		},
		{
			"text": "Разгони печь до 300 °C",
			"hint": "держи заслонку открытой, подкидывай дров",
			"key": "7",
			"tool": PechGame.Tool.PROP,
			"at": FIREBOX,
			"ok": func() -> bool:
				return _g.stove_temp >= 300.0,
		},
		{
			"text": "Прогрей сарай до +20 °C",
			"hint": "кладка копит жар и отдаёт его сама",
			"key": "",
			"at": Vector3.ZERO,
			"ok": func() -> bool:
				return _g._warm_done,
		},
	]


func total() -> int:
	return _steps.size()


## Шаги проверяем не каждый кадр: условия медленные, а обход предметов
## стоит денег.
func update(delta: float) -> void:
	if not active or step >= _steps.size():
		return
	_cd -= delta
	if _cd > 0.0:
		return
	_cd = 0.25
	var cur: Dictionary = _steps[step]
	var ok: Callable = cur["ok"]
	if not ok.call():
		return
	step_done.emit(step)
	step += 1
	# если игрок обогнал обучение, засчитываем всё, что уже сделано
	while step < _steps.size() and (_steps[step]["ok"] as Callable).call():
		step_done.emit(step)
		step += 1
	if step >= _steps.size():
		finished.emit()


func current() -> Dictionary:
	if not active or step >= _steps.size():
		return {}
	return _steps[step]


## Сколько растопки нужного вида лежит в топке. Топка — это коробка над
## подом печи: всё, что игрок туда набросал, считается по-честному.
func _in_box(kind: int) -> int:
	var n := 0
	for p in _g._pieces:
		if p.kind != kind:
			continue
		var d := p.global_position - FIREBOX
		if absf(d.x) < 0.36 and absf(d.z) < 0.32 and d.y > -0.12 and d.y < 0.45:
			n += 1
	return n
