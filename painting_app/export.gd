extends Control

var file_dialog := FileDialog.new()

func _ready():
	add_child(file_dialog)

	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = ["*.png ; PNG Images"]

	file_dialog.file_selected.connect(_on_file_selected)

func open_export_dialog():
	file_dialog.popup_centered_ratio()

func _on_file_selected(path: String):
	print("Selected:", path)
