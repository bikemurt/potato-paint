#pragma once

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

using namespace godot;

class PaintUtils : public RefCounted {
    GDCLASS(PaintUtils, RefCounted);

protected:
    static void _bind_methods();

private:

public:
	static void draw_brush_stamp(
		const Vector2& center,
		const Ref<Image>& image,
		int32_t size,
		const PackedFloat32Array& brush_mask,
		const Color& color,
		bool eraser,
		float pressure
	);
};