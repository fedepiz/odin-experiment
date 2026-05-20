package game

import "core:fmt"

Logical_Size_Kind :: enum {
	Pixels,
	SumOfChildren,
	MaxOfChildren,
}

Logical_Size :: struct {
	kind:  Logical_Size_Kind,
	value: f32,
}

Axis :: enum {
	Horizontal = 0,
	Vertical   = 1,
}

@(private = "file")
axis_flip :: proc(axis: Axis) -> Axis {
	out: Axis = ---
	switch (axis) {
	case .Horizontal:
		out = Axis.Vertical
	case .Vertical:
		out = Axis.Horizontal
	}
	return out
}

@(private = "file")
UI: struct {
	boxes:     [dynamic; 1024]Ui_Box,
	active:    ^Ui_Box,
	drawables: [dynamic; 1024]Drawable,
}

@(private = "file")
Ui_Box :: struct {
	key:           u64,
	logical_size:  [Axis]Logical_Size,
	computed_size: [2]f32,
	growth_axis:   [2]f32,
	fill:          Rect_Gradient,
	parent:        ^Ui_Box,
	first_child:   ^Ui_Box,
	last_child:    ^Ui_Box,
	sibling:       ^Ui_Box,
}

@(private = "file")
ui_box_add_child :: proc(parent: ^Ui_Box, child: ^Ui_Box) {
	if parent.last_child != nil {
		parent.last_child.sibling = child
	} else {
		parent.first_child = child
	}
	parent.last_child = child
	child.parent = parent
}

ui_box_begin :: proc() {
	append(&UI.boxes, Ui_Box{})
	new := &UI.boxes[len(UI.boxes) - 1]
	if UI.active != nil {
		ui_box_add_child(UI.active, new)
	}
	UI.active = new
}

ui_box_end :: proc() {
	UI.active = UI.active.parent
}

ui_begin :: proc() {
	clear(&UI.boxes)
	UI.active = nil
}

ui_end :: proc() -> []Drawable {
	if UI.active != nil {
		fmt.printfln("ERROR: ui_end detected unclosed ui_box")
	}
	clear(&UI.drawables)

	// Calculate sizes
	for axis in Axis {
		for i := len(UI.boxes); i > 0; i -= 1 {
			ui_box := &UI.boxes[i - 1]
			log_size := ui_box.logical_size[axis]
			computed_size: f32 = 0
			switch (log_size.kind) {
			case .Pixels:
				computed_size += log_size.value
			case .SumOfChildren:
				for child := ui_box.first_child; child != nil; child = child.sibling {
					computed_size += child.computed_size[axis]
				}
			case .MaxOfChildren:
				v: f32 = 0
				for child := ui_box.first_child; child != nil; child = child.sibling {
					v = max(v, child.computed_size[axis])
				}
				computed_size += v
			}
			ui_box.computed_size[axis] = computed_size
		}
	}

	// Layout
	for &ui_box in UI.boxes {
		// Not a root, skip
		if ui_box.parent != nil {
			continue
		}

		cursor: V2 = {0, 0}
		layout_rec(&ui_box, cursor)
	}

	return UI.drawables[:]

	// Layout recursive
	layout_rec :: proc(ui_box: ^Ui_Box, cursor: V2) {
		cursor := cursor
		bounds := Rect{cursor.x, cursor.y, ui_box.computed_size[0], ui_box.computed_size[1]}

		append(&UI.drawables, Drawable{bounds = bounds, color = ui_box.fill})

		for child := ui_box.first_child; child != nil; child = child.sibling {
			layout_rec(child, cursor)
			cursor += child.computed_size * ui_box.growth_axis
		}
	}
}

ui_box_pixel_size :: proc(size: V2) {
	if UI.active != nil {
		for axis in Axis {
			UI.active.logical_size[axis].kind = .Pixels
			UI.active.logical_size[axis].value = size[axis]
		}
	}

}

ui_box_set_fill :: proc(color: Rect_Gradient) {
	if UI.active != nil {
		UI.active.fill = color
	}
}

ui_box_set_layout :: proc(maj_axis: Axis) {
	if UI.active != nil {
		min_axis := axis_flip(maj_axis)
		UI.active.growth_axis[maj_axis] = 1
		UI.active.growth_axis[min_axis] = 0
		UI.active.logical_size[maj_axis].kind = Logical_Size_Kind.SumOfChildren
		UI.active.logical_size[min_axis].kind = Logical_Size_Kind.MaxOfChildren
	}
}

