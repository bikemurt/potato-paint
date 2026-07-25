#include "paint_utils.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

using namespace godot;
void PaintUtils::_bind_methods() {
	ClassDB::bind_static_method(
		"PaintUtils",
		D_METHOD(
			"draw_brush_stamp",
			"center",
			"image",
			"size",
			"brush_mask",
			"color",
			"eraser",
			"pressure"
		),
		&PaintUtils::draw_brush_stamp
	);
}

void PaintUtils::draw_brush_stamp(
	const Vector2& center,
	const Ref<Image>& image,
	int32_t size,
	const PackedFloat32Array& brush_mask,
	const Color& color,
	bool eraser,
	float pressure
) {
	if (image.is_null()) {
		return;
	}

	pressure = Math::clamp(pressure, 0.0f, 1.0f);

	const int start_x = int(center.x - size * 0.5f);
	const int start_y = int(center.y - size * 0.5f);

	const int width = image->get_width();
	const int height = image->get_height();

	const float base_alpha = color.a * pressure;

	for (int y = 0; y < size; ++y) {
		const int row = y * size;

		for (int x = 0; x < size; ++x) {
			const float strength = brush_mask[row + x];

			if (strength <= 0.0f) continue;

			const int px = start_x + x;
			const int py = start_y + y;

			if (px < 0 || py < 0 || px >= width || py >= height) continue;

			Color dst = image->get_pixel(px, py);
			if (eraser) {
				dst.a *= (1.0f - strength);
				image->set_pixel(px, py, dst);
			}
			else {
				Color src = color;
				src.a = base_alpha * strength;
				image->set_pixel(px, py, dst.blend(src));
			}
		}
	}
}
