extends Control

const MAX_UNDO := 20
const SAVE_PATH := "user://data.save"

@onready var layers: Control = %Layers
@onready var layer_buttons: HBoxContainer = %LayerButtons
@onready var toggle_layer_visibility: Button = %ToggleLayerVisibility
@onready var color_picker: ColorPicker = %ColorPicker
@onready var select_color: PanelContainer = %SelectColor
@onready var set_eraser_button: Button = %SetEraserButton
@onready var tool_box: HBoxContainer = %ToolBox
@onready var ui: Control = %UI
@onready var settings: VBoxContainer = %Settings
@onready var chosen_color_rect: ColorRect = %ChosenColorRect
@onready var hardness_h_slider: HSlider = %HardnessHSlider
@onready var spacing_h_slider: HSlider = %SpacingHSlider
@onready var size_h_slider: HSlider = %SizeHSlider
@onready var draw_region: Control = %DrawRegion
@onready var full_draw_region: Control = %FullDrawRegion
@onready var size_label: Label = %SizeLabel
@onready var top_left_corner: ColorRect = %TopLeftCorner
@onready var scroll_container: ScrollContainer = %ScrollContainer
@onready var file_scroll_container: ScrollContainer = %FileScrollContainer
@onready var load_file: PanelContainer = %LoadFile
@onready var load_v_box_container: VBoxContainer = %LoadVBoxContainer
@onready var file_name_line_edit: LineEdit = %FileNameLineEdit
@onready var last_saved_label: Label = %LastSavedLabel

var save_data := {
	&"file_count": 0,
	&"current_file": -1,
	&"files": {
		#0: {
			#&"layer_id": 0,
			#&"layer_order": [0,1],
			#&"layers": {
				#0: {
					## image path gen from keys. user://saves/save_0/layer_0.png
					#&"brush_size": 10,
					#&"brush_color_r": 1.0,
					#&"brush_color_g": 0.0,
					#&"brush_color_b": 0.0,
					#&"brush_color_a": 1.0,
					#&"brush_hardness": 0.5,
					#&"brush_spacing": 0.1,
				#},
			#}
		#}
	}
}

class ImageData:
	var layer_id := -1
	var image: Image
	var image_texture: ImageTexture
	var button: Button
	var texture_rect: TextureRect
	var brush_size := 10
	var brush_color := Color.BLACK
	var brush_hardness := 0.5
	var brush_spacing := 0.1

var image_map: Dictionary[int, ImageData] = {}

var eraser := false:
	get:
		return eraser
	set(value):
		set_cursor(value, Control.CURSOR_CROSS, Control.CURSOR_ARROW)
		eraser = value

var eye_dropper := false:
	get:
		return eye_dropper
	set(value):
		set_cursor(value, Control.CURSOR_CROSS, Control.CURSOR_POINTING_HAND)
		eye_dropper = value

var active_layer := 0:
	get:
		return active_layer
	set(value):
		active_layer = value
		if len(image_map) > 0:
			update_vis_button()
			update_chosen_color()
			update_hardness()
			update_spacing()
			update_size()
			rebuild_brush()

var brush_mask: PackedFloat32Array
var undo_stack: Array[Image] = []
var redo_stack: Array[Image] = []
var brush_pressure := 1.0
var drawing := false
var texture_dirty := false
var last_stamp_pos := Vector2(-100,-100)
var disabled := false
var drag_region_mouse_hover := false
var file_name := ""
var layer_count := 0
var last_saved_tween: Tween
var file_dialog := FileDialog.new()
var autosave := false
var autosave_timer := 10.0

func _ready() -> void:
	load_save_data()
	
	scroll_container.get_h_scroll_bar().custom_minimum_size.y = 20.0
	file_scroll_container.get_v_scroll_bar().custom_minimum_size.x = 20.0
	
	eye_dropper = false # this triggers default cursor ? weird
	
	tool_box.hide()
	settings.hide()
	select_color.hide()
	load_file.hide()
	full_draw_region.hide()
	top_left_corner.hide()
	last_saved_label.modulate.a = 0.0
	
	draw_region.gui_input.connect(gui_input)
	full_draw_region.gui_input.connect(gui_input)
	
	add_child(file_dialog)

	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = ["*.png ; PNG Images"]

	file_dialog.file_selected.connect(on_file_selected)
	
	if save_data.current_file == -1:
		new_save_file()
	else:
		load_save_file()

func _process(delta: float) -> void:
	if texture_dirty:
		var active_data := get_active_data()
		active_data.image_texture.update(active_data.image)
		texture_dirty = false
	
	if autosave and autosave_timer >= 5.0:
		save()
		autosave_timer = 0.0
		autosave = false
	
	# prevent it from creeping up infinitely?
	if autosave_timer <= 10.0:
		autosave_timer += delta

func get_file_name(_file_name: String, file_id: int) -> String:
	if _file_name == "": return "File %d" % [file_id]
	else: return _file_name

func new_save_file() -> void:
	reset_all_data()
	_on_new_layer_pressed()
	save_data.current_file = save_data.file_count
	save_data.file_count += 1

func reset_all_data() -> void:
	for c in layers.get_children(): c.free()
	for c in layer_buttons.get_children(): c.free()
	image_map.clear()
	eraser = false
	eye_dropper = false
	
	layer_count = 0
	active_layer = 0
	file_name = ""
	
	brush_mask.clear()
	undo_stack.clear()
	redo_stack.clear()
	brush_pressure = 1.0
	drawing = false
	texture_dirty = false
	last_stamp_pos = Vector2(-100,-100)
	disabled = false
	drag_region_mouse_hover = false

func delete_layer_folder(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null: return
	
	for _file_name in dir.get_files():
		var file_path := path.path_join(_file_name)
		DirAccess.remove_absolute(file_path)
	
	DirAccess.remove_absolute(path)

func save() -> void:
	var file_data := {
		&"layer_count": layer_count,
		&"layer_order": get_layer_order(),
		&"active_layer": active_layer,
		&"file_name": file_name,
		&"layers": {}
	}
	var dir := "user://saves/save_%d" % save_data.current_file
	DirAccess.make_dir_recursive_absolute(dir)
	
	for i in image_map:
		var data := image_map[i]
		var layer_data := {}
		layer_data.brush_size = data.brush_size
		layer_data.brush_color_r = data.brush_color.r
		layer_data.brush_color_g = data.brush_color.g
		layer_data.brush_color_b = data.brush_color.b
		layer_data.brush_color_a = data.brush_color.a
		layer_data.brush_hardness = data.brush_hardness
		layer_data.brush_spacing = data.brush_spacing
		file_data.layers[i] = layer_data
		
		# save the images
		data.image.save_png("user://saves/save_%d/layer_%d.png" % [save_data.current_file, i])
	
	save_data.files[save_data.current_file] = file_data
	
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_var(save_data)
	file.close()
	
	# clean up image save folders
	var dir2 := DirAccess.open("user://saves")
	if dir2:
		for folder_name in dir2.get_directories():
			var file_id := int(folder_name.replace("save_", ""))
			if file_id not in save_data.files:
				delete_layer_folder("user://saves/%s/" % folder_name)
	
	last_saved_label.modulate.a = 1.0
	var dt := Time.get_datetime_dict_from_system()

	var hour: int = dt.hour
	var ampm := "AM"
	if hour >= 12: ampm = "PM"
	hour = hour % 12
	if hour == 0: hour = 12
	last_saved_label.text = "Last saved %01d:%02d:%02d %s" % [hour, dt.minute, dt.second, ampm]
	
	if last_saved_tween: last_saved_tween.kill()
	last_saved_label.modulate.a = 1.0
	await get_tree().create_timer(2.0).timeout
	
	last_saved_tween = create_tween()
	last_saved_tween.tween_property(last_saved_label, "modulate:a", 0.0, 2.0)

func load_save_data() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		save_data = file.get_var()
		file.close()

func load_save_file() -> void:
	reset_all_data()
	var save_file_data: Dictionary = save_data.files[save_data.current_file]
	var layer_order: Array[int] = save_file_data.layer_order
	var active_layer_button: Button
	for i: int in layer_order:
		var layer: Dictionary = save_file_data.layers[layer_order[i]]
		var data := ImageData.new()
		
		data.brush_color = Color(layer.brush_color_r, layer.brush_color_g, layer.brush_color_b, layer.brush_color_a)
		data.brush_hardness = layer.brush_hardness
		data.brush_size = layer.brush_size
		data.brush_spacing = layer.brush_spacing
		
		data.image = Image.new()
		data.image.load("user://saves/save_%d/layer_%d.png" % [save_data.current_file, i])
		
		data.image_texture = ImageTexture.create_from_image(data.image)
		data.button = create_layer_button(i)
		data.texture_rect = create_layer_texture_rect(i, data.image.get_size(), data.image_texture)
		data.layer_id = i
		
		if i == save_file_data.active_layer: active_layer_button = data.button
		
		image_map[i] = data
	
	layer_count = save_file_data.layer_count
	file_name = save_file_data.file_name
	
	layer_button_pressed(active_layer_button)

func get_active_data() -> ImageData:
	return image_map[active_layer]

func create_layer() -> Button:
	var data := ImageData.new()
	
	var res := DisplayServer.window_get_size()
	data.image = Image.create(res.x, res.y, false, Image.FORMAT_RGBA8)
	data.image.fill(Color.TRANSPARENT)
	
	data.image_texture = ImageTexture.create_from_image(data.image)
	data.button = create_layer_button(layer_count)
	data.texture_rect = create_layer_texture_rect(layer_count, res, data.image_texture)
	data.layer_id = layer_count
	
	image_map[layer_count] = data
	
	layer_count += 1
	return data.button

func create_layer_button(layer_id: int) -> Button:
	var button := Button.new()
	button.text = "%d" % [layer_id + 1]
	button.set_meta(&"layer", layer_id)
	button.custom_minimum_size.x = 50
	button.pressed.connect(layer_button_pressed.bind(button))
	layer_buttons.add_child(button)
	return button

func create_layer_texture_rect(layer_id: int, res: Vector2, image_texture: ImageTexture) -> TextureRect:
	var layer := TextureRect.new()
	layer.set_meta(&"layer", layer_id)
	layer.position = Vector2.ZERO
	layer.size = res
	layer.texture = image_texture
	layers.add_child(layer)
	return layer

func clear_button_text() -> void:
	for b: Button in layer_buttons.get_children():
		b.text = str(b.get_meta(&"layer") + 1)

func layer_button_pressed(b: Button) -> void:
	clear_button_text()
	var layer: int = b.get_meta(&"layer")
	b.text = str(layer + 1) + "*"
	active_layer = layer

func gui_input(event: InputEvent) -> void:
	var texture_rect := get_active_data().texture_rect
	if not texture_rect.visible: return
	if select_color.visible: return
	if disabled: return
	if ui.visible and not drag_region_mouse_hover:
		drawing = false
		return
	
	var data := get_active_data()
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if event.pressed:
			var pos := screen_to_canvas(texture_rect)
			if eye_dropper:
				set_eye_dropper_color(pos)
				eye_dropper = false
			else:
				#draw_brush_stamp2(pos, data.image, data.brush_size, brush_mask,
				#	data.brush_color, eraser, brush_pressure)
				save_undo_state()
				PaintUtils.draw_brush_stamp(pos, data.image, data.brush_size, brush_mask,
					data.brush_color, eraser, brush_pressure)
				
				texture_dirty = true
				
				last_stamp_pos = pos
				drawing = true
				autosave = true
		else:
			drawing = false
	
	elif (event is InputEventScreenDrag or event is InputEventMouseMotion) and drawing:
		var pos := screen_to_canvas(texture_rect)
		
		if event is InputEventScreenDrag:
			brush_pressure = event.pressure
		
		draw_stroke(pos)
		autosave = true

func set_eye_dropper_color(pos: Vector2) -> void:
	var order := get_layer_order()
	var layer_0 := image_map[order[0]].image
	var dst := layer_0.get_pixelv(pos)
	for i in order:
		if i == 0: continue
		var src := image_map[order[i]].image.get_pixelv(pos)
		dst = dst.blend(src)
	
	set_color(dst)

func draw_stroke(to: Vector2) -> void:
	var data := get_active_data()
	var spacing := data.brush_size * data.brush_spacing
	var distance := last_stamp_pos.distance_to(to)
	
	if distance < spacing: return
	
	var direction := last_stamp_pos.direction_to(to)
	var steps := int(distance / spacing)
	for i in range(1, steps + 1):
		var pos := last_stamp_pos + direction * spacing * i
		#draw_brush_stamp2(pos, data.image, data.brush_size, brush_mask,
		#		data.brush_color, eraser, brush_pressure)
		PaintUtils.draw_brush_stamp(pos, data.image, data.brush_size, brush_mask,
				data.brush_color, eraser, brush_pressure)
	
	last_stamp_pos = to
	texture_dirty = true

# GD script method
func draw_brush_stamp2(center: Vector2, _image: Image, _size: int, _brush_mask: PackedFloat32Array,
	_color:  Color, _eraser: bool, _pressure: float) -> void:
	var start_x := int(center.x - _size * 0.5)
	var start_y := int(center.y - _size * 0.5)
	var width := _image.get_width()
	var height := _image.get_height()
	
	for y in _size:
		for x in _size:
			var strength := _brush_mask[y * _size + x]
			if strength <= 0.0: continue

			var px := start_x + x
			var py := start_y + y

			if px < 0 or py < 0: continue
			if px >= width or py >= height: continue

			if _eraser:
				var dst := _image.get_pixel(px, py)
				dst.a *= 1.0 - strength
				_image.set_pixel(px, py, dst)
			else:
				var dst := _image.get_pixel(px, py)
				var src := _color
				src.a *= strength * _pressure
				
				_image.set_pixel(px, py, dst.blend(src))

func screen_to_canvas(texture_rect: TextureRect) -> Vector2:
	var pos := texture_rect.get_local_mouse_position()
	var image := get_active_data().image
	return pos * Vector2(image.get_size()) / texture_rect.size

func save_undo_state() -> void:
	var data := get_active_data()
	undo_stack.push_back(data.image.duplicate())
	if undo_stack.size() > MAX_UNDO: undo_stack.pop_front()
	
	redo_stack.clear()

func undo() -> void:
	var data := get_active_data()
	if undo_stack.is_empty(): return
	redo_stack.push_back(data.image.duplicate())
	data.image = undo_stack.pop_back()
	data.image_texture.update(data.image)

func redo() -> void:
	var data := get_active_data()
	if redo_stack.is_empty(): return
	undo_stack.push_back(data.image.duplicate())
	data.image = redo_stack.pop_back()
	data.image_texture.update(data.image)

func rasterize_layers() -> Image:
	var _size := DisplayServer.window_get_size()
	
	var output := Image.create(
		_size.x,
		_size.y,
		false,
		Image.FORMAT_RGBA8
	)
	
	output.fill(Color.TRANSPARENT)
	
	var order := get_layer_order()
	for i in order:
		var layer_id := order[i]
		var data: ImageData = image_map[layer_id]

		if not data.texture_rect.visible:
			continue

		output.blend_rect(
			data.image,
			Rect2(Vector2.ZERO, _size),
			Vector2.ZERO
		)
	
	return output

func rebuild_brush() -> void:
	var data := get_active_data()

	var _size := data.brush_size
	var radius := _size * 0.5
	var radius2 := radius * radius
	var hard_radius := radius * data.brush_hardness
	var hard_radius2 := hard_radius * hard_radius

	brush_mask.resize(_size * _size)

	for y in _size:
		for x in _size:
			var dx := x + 0.5 - radius
			var dy := y + 0.5 - radius

			var dist2 := dx * dx + dy * dy
			var alpha := 0.0

			if dist2 <= radius2:
				if dist2 <= hard_radius2:
					alpha = 1.0
				else:
					var distance := sqrt(dist2)
					alpha = 1.0 - smoothstep(hard_radius, radius, distance)
			
			brush_mask[y * _size + x] = alpha

func set_color(color: Color) -> void:
	eraser = false
	eye_dropper = false
	get_active_data().brush_color = color
	update_chosen_color()
	rebuild_brush()

func set_cursor(condition: bool, cursor_1: CursorShape, cursor_2: CursorShape) -> void:
	var cursor := cursor_1
	if condition:
		cursor = cursor_2
	
	draw_region.mouse_default_cursor_shape = cursor
	full_draw_region.mouse_default_cursor_shape = cursor

func get_layer_order() -> Array[int]:
	var order: Array[int] = []
	for layer in layers.get_children():
		order.push_back(layer.get_meta(&"layer"))
	return order

func on_file_selected(path: String):
	var img := rasterize_layers()
	img.save_png(path)

func move_node(node: Node, inc: int) -> void:
	var current_index := node.get_index()
	var ok := inc > 0 or (inc < 0 and current_index > 0)
	if ok:
		node.get_parent().move_child(node, current_index + inc)





func update_vis_button() -> void:
	var texture_rect := get_active_data().texture_rect
	if texture_rect.visible:
		toggle_layer_visibility.text = "👁"
	else:
		toggle_layer_visibility.text = "⛔"

func update_chosen_color() -> void:
	chosen_color_rect.color = get_active_data().brush_color

func update_hardness() -> void:
	hardness_h_slider.value = get_active_data().brush_hardness

func update_spacing() -> void:
	spacing_h_slider.value = get_active_data().brush_spacing

func update_size() -> void:
	size_h_slider.value = get_active_data().brush_size





func _on_control_gui_input(event: InputEvent) -> void:
	if not ui.visible and event is InputEventScreenTouch or event is InputEventMouseButton:
		top_left_corner.hide()
		full_draw_region.hide()
		ui.show()
		if disabled:
			disabled = true
			await get_tree().create_timer(0.3).timeout
			disabled = false

func _on_new_layer_pressed() -> void:
	var b := create_layer()
	layer_button_pressed(b)

func _on_toggle_layer_visibility_pressed() -> void:
	var texture_rect := get_active_data().texture_rect
	texture_rect.visible = not texture_rect.visible
	update_vis_button()

func _on_set_color_button_pressed() -> void:
	select_color.visible = not select_color.visible
	color_picker.color = get_active_data().brush_color

func _on_color_picker_color_changed(color: Color) -> void:
	set_color(color)

func _on_color_close_button_pressed() -> void:
	select_color.hide()

func _on_fill_button_pressed() -> void:
	save_undo_state()
	var data := get_active_data()
	data.image.fill(data.brush_color)
	texture_dirty = true
	autosave = true

func _on_set_eraser_button_pressed() -> void:
	eraser = not eraser
	if eraser: set_eraser_button.text = "E*"
	else: set_eraser_button.text = "E"

func _on_fill_empty_button_pressed() -> void:
	save_undo_state()
	get_active_data().image.fill(Color.TRANSPARENT)
	texture_dirty = true
	autosave = true

func _on_tool_button_pressed() -> void:
	tool_box.visible = not tool_box.visible

func _on_hide_ui_button_pressed() -> void:
	top_left_corner.show()
	full_draw_region.show()
	ui.hide()

func _on_undo_button_pressed() -> void:
	undo()

func _on_redo_button_pressed() -> void:
	redo()

func _on_settings_button_pressed() -> void:
	settings.visible = not settings.visible

func _on_hardness_h_slider_drag_ended(value_changed: bool) -> void:
	if value_changed:
		get_active_data().brush_hardness = hardness_h_slider.value
		rebuild_brush()

func _on_spacing_h_slider_drag_ended(value_changed: bool) -> void:
	if value_changed:
		get_active_data().brush_spacing = spacing_h_slider.value
		rebuild_brush()

func _on_size_h_slider_drag_ended(value_changed: bool) -> void:
	if value_changed:
		get_active_data().brush_size = roundi(size_h_slider.value)
		rebuild_brush()

func _on_draw_region_mouse_entered() -> void:
	drag_region_mouse_hover = true

func _on_draw_region_mouse_exited() -> void:
	drag_region_mouse_hover = false

func _on_eye_dropper_button_pressed() -> void:
	eye_dropper = true

func _on_size_h_slider_value_changed(value: float) -> void:
	size_label.text = "%d" % roundi(value)

func _on_left_layer_pressed() -> void:
	var data := get_active_data()
	move_node(data.texture_rect, -1)
	move_node(data.button, -1)

func _on_right_layer_pressed() -> void:
	var data := get_active_data()
	move_node(data.texture_rect, +1)
	move_node(data.button, +1)

func _on_delete_layer_pressed() -> void:
	if len(image_map) > 1:
		var order := get_layer_order()
		var new_active_layer := order[1]
		for i in get_layer_order():
			if i == active_layer: break
			new_active_layer = i
		
		var data := get_active_data()
		data.texture_rect.queue_free()
		data.button.queue_free()
		image_map.erase(active_layer)
		
		layer_button_pressed(image_map[new_active_layer].button)

func _on_load_button_pressed() -> void:
	load_file.show()
	for c in load_v_box_container.get_children(): c.queue_free()
	
	file_name_line_edit.text = get_file_name(file_name, save_data.current_file)
	for save_file: int in save_data.files:
		var save_file_data: Dictionary = save_data.files[save_file]
		var button := Button.new()
		button.custom_minimum_size.x = 300
		button.text = get_file_name(save_file_data.file_name, save_file)
		button.pressed.connect(func() -> void:
			save_data.current_file = save_file
			load_save_file()
			load_file.hide()
			)
		load_v_box_container.add_child(button)

func _on_save_button_pressed() -> void:
	save()

func _on_load_file_close_button_pressed() -> void:
	load_file.hide()

func _on_delete_button_pressed() -> void:
	save_data.files.erase(save_data.current_file)
	new_save_file()
	load_file.hide()

func _on_file_name_line_edit_text_changed(new_text: String) -> void:
	file_name = new_text

func _on_new_file_button_pressed() -> void:
	new_save_file()
	load_file.hide()

func _on_export_button_pressed() -> void:
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.current_file = get_file_name(file_name, save_data.current_file)
	file_dialog.popup_centered_ratio()
