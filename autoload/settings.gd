extends Node
## 设置：亮度 / 音量 / 声呐配色。存 user://settings.cfg，Esc 面板里改。
## 三项都用"循环切换"，不搞滑条 —— 键鼠都能用，也不用做拖动交互。

const PATH := "user://settings.cfg"

## 越往后越亮；默认标准（索引 1）
const DARKS := [
	Color(0.008, 0.010, 0.018),
	Color(0.015, 0.017, 0.028),
	Color(0.032, 0.036, 0.052),
]
const DARK_NAMES := ["暗", "标准", "亮"]
const VOLS := [0.0, -6.0, -14.0]
const VOL_NAMES := ["100%", "50%", "25%"]
const PALETTE_NAMES := ["标准（青）", "高对比（白）"]

var dark_index := 1
var vol_index := 0
var palette := 0

func _ready() -> void:
	_load()
	_apply()

func dark_color() -> Color:
	return DARKS[clampi(dark_index, 0, DARKS.size() - 1)]

## 只改暗色层看不出区别（世界几乎是黑的），所以光圈亮度跟着一起变。
func light_mul() -> float:
	return [0.7, 1.0, 1.5][clampi(dark_index, 0, 2)]

func cycle_dark() -> void:
	dark_index = (dark_index + 1) % DARKS.size()
	_apply()
	_save()

func cycle_volume() -> void:
	vol_index = (vol_index + 1) % VOLS.size()
	_apply()
	_save()

func cycle_palette() -> void:
	palette = (palette + 1) % PALETTE_NAMES.size()
	_apply()
	_save()

func _apply() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, VOLS[vol_index])

func describe() -> String:
	return "亮度 %s    音量 %s    声呐配色 %s" % [
		DARK_NAMES[dark_index], VOL_NAMES[vol_index], PALETTE_NAMES[palette]
	]

func _save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"dark": dark_index, "vol": vol_index, "palette": palette}))

func _load() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if typeof(d) == TYPE_DICTIONARY:
		dark_index = clampi(int(d.get("dark", 1)), 0, DARKS.size() - 1)
		vol_index = clampi(int(d.get("vol", 0)), 0, VOLS.size() - 1)
		palette = clampi(int(d.get("palette", 0)), 0, PALETTE_NAMES.size() - 1)
