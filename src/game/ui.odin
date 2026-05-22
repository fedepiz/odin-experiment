package game

import "core:fmt"
import "core:hash"
import "core:mem"

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
Ui_Key :: u64

@(private = "file")
NumElements :: 1024

@(private = "file")
UI: struct {
	boxes:      [dynamic; NumElements]Ui_Box,
	active:     ^Ui_Box,
	drawables:  [dynamic; NumElements]Drawable,
	caches:     [2]map[Ui_Key]Ui_Cache,
	tick_num:   u64,
	global_sig: Ui_GlobalSignals,
	style_vars: [Ui_StyleVar]Ui_StyleVarData,
}

@(private = "file")
Ui_GlobalSignals :: struct {
	hovered_key: Ui_Key,
	clicked_key: Ui_Key,
	held_key:    Ui_Key,
}

Ui_StyleVar :: enum {
	UnitW,
	UnitH,
	WidgetBaseColor,
	WidgetHoverColor,
	WidgetHeldColor,
	WidgetTextColor,
	WidgetTextSize,
	WidgetBorderColor,
	WidgetBorderThickness,
	WidgetThinBorderThickness,
	WidgetBorderRadius,
	ToggleOnColor,
	ToggleHoverColor,
	PanelColor,
	PanelBorderColor,
	PanelBorderThickness,
	PanelBorderRadius,
	PanelBorderPad,
}

@(private = "file")
Ui_StyleVarType :: enum {
	Number,
	Color,
}

@(private = "file")
ui_style_var_type :: proc(var: Ui_StyleVar) -> Ui_StyleVarType {
	switch (var) {
	case .UnitW:
		return .Number
	case .UnitH:
		return .Number
	case .WidgetBaseColor:
		return .Color
	case .WidgetHeldColor:
		return .Color
	case .WidgetHoverColor:
		return .Color
	case .WidgetTextColor:
		return .Color
	case .WidgetTextSize:
		return .Number
	case .WidgetBorderColor:
		return .Color
	case .WidgetBorderThickness:
		return .Number
	case .WidgetThinBorderThickness:
		return .Number
	case .WidgetBorderRadius:
		return .Number
	case .ToggleOnColor:
		return .Color
	case .ToggleHoverColor:
		return .Color
	case .PanelColor:
		return .Color
	case .PanelBorderColor:
		return .Color
	case .PanelBorderThickness:
		return .Number
	case .PanelBorderRadius:
		return .Number
	case .PanelBorderPad:
		return .Number
	case:
		assert(false)
	}
	return {}
}

Ui_StyleVarData :: struct {
	num:   f32,
	color: Color,
}

@(private = "file")
Ui_Box :: struct {
	key:                  Ui_Key,
	logical_size:         [Axis]Logical_Size,
	bounds:               Rect,
	growth_axis:          [2]f32,
	center_axis:          [2]f32,
	background:           Asset_Id,
	background_intensity: f32,
	fill:                 Rect_Gradient,
	// Border
	stroke:               Rect_Gradient,
	thickness:            f32,
	radius:               f32,
	// Text
	text:                 string,
	font:                 Asset_Id,
	pixel_height:         f32,
	text_color:           Color,
	// Hierarchy
	parent:               ^Ui_Box,
	first_child:          ^Ui_Box,
	last_child:           ^Ui_Box,
	sibling:              ^Ui_Box,
}

@(private = "file")
Ui_Cache :: struct {
	key:    Ui_Key,
	bounds: Rect,
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

ui_init :: proc(alloc: mem.Allocator) {
	UI = {}
	// Acquire memory for caches
	UI.caches[0] = make(map[Ui_Key]Ui_Cache, NumElements, allocator = alloc)
	UI.caches[1] = make(map[Ui_Key]Ui_Cache, NumElements, allocator = alloc)
}

@(private = "file")
ui_get_old_cache :: proc() -> ^map[Ui_Key]Ui_Cache {
	return &UI.caches[UI.tick_num % len(UI.caches)]

}
@(private = "file")
ui_get_new_cache :: proc() -> ^map[Ui_Key]Ui_Cache {
	return &UI.caches[(UI.tick_num + 1) % len(UI.caches)]
}

ui_begin :: proc(input: Platform_Input) {
	old_cache := ui_get_old_cache()
	new_cache := ui_get_new_cache()
	UI.global_sig = {}

	hovered: Ui_Key

	for &ui_box in UI.boxes {
		if ui_box.key == 0 do continue
		cache: Ui_Cache
		// Is the pointer over this item?
		if rect_contains_point(ui_box.bounds, input.mouse_pos) {
			hovered = ui_box.key
		}
		// Populate the cache
		cache.key = ui_box.key
		cache.bounds = ui_box.bounds
		map_insert(new_cache, cache.key, cache)
	}
	// Get rid of the ui_box and old caches, we are done reading from there
	clear(&UI.boxes)
	clear(old_cache)

	UI.global_sig.hovered_key = hovered
	if input.mouse_clicked {
		UI.global_sig.clicked_key = hovered
	}
	if input.mouse_down {
		UI.global_sig.held_key = hovered
	}

	UI.active = nil
	UI.tick_num += 1
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
					computed_size += rect_size(child.bounds)[axis]
				}
			case .MaxOfChildren:
				v: f32 = 0
				for child := ui_box.first_child; child != nil; child = child.sibling {
					v = max(v, rect_size(child.bounds)[axis])
				}
				computed_size += v
			}
			switch (axis) {
			case .Horizontal:
				ui_box.bounds.w = computed_size
			case .Vertical:
				ui_box.bounds.h = computed_size
			}
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

		ui_box.bounds.x = cursor.x
		ui_box.bounds.y = cursor.y

		drawable := Drawable {
			space = .Ui,
			bounds = ui_box.bounds,
			color = ui_box.fill,
			sprite = ui_box.background,
			sprite_mapping = .Wrap,
			sprite_intensity = ui_box.background_intensity,
			stroke = ui_box.stroke,
			thickness = ui_box.thickness,
			radius = ui_box.radius,
			text = {
				content = ui_box.text,
				pixel_height = ui_box.pixel_height,
				color = ui_box.text_color,
				font = ui_box.font,
				pos = DrawTextPos.Center,
			},
		}

		append(&UI.drawables, drawable)


		for child := ui_box.first_child; child != nil; child = child.sibling {
			centering :=
				(rect_size(ui_box.bounds) - rect_size(child.bounds)) / 2 * ui_box.center_axis
			layout_rec(child, cursor + centering)
			cursor += rect_size(child.bounds) * ui_box.growth_axis
		}
	}
}

Ui_Signal :: struct {
	key:        Ui_Key,
	is_hovered: bool,
	is_clicked: bool,
	is_held:    bool,
}

ui_box_set_key :: proc(key: u64) -> Ui_Signal {
	signal: Ui_Signal
	if UI.active != nil {
		if UI.active.key != 0 {
			fmt.println("WARNING: Reassining key for active widget")
		}
		UI.active.key = key
		if key != 0 {
			signal.key = key
			signal.is_hovered = UI.global_sig.hovered_key == key
			signal.is_clicked = UI.global_sig.clicked_key == key
			signal.is_held = UI.global_sig.held_key == key
		}
	}
	return signal
}

ui_box_set_key_from_text :: proc(text: string) -> Ui_Signal {
	key := hash.murmur64a(transmute([]byte)text)
	return ui_box_set_key(key)
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

ui_box_set_border :: proc(color: Rect_Gradient, thickness: f32, radius: f32) {
	if UI.active != nil {
		UI.active.stroke = color
		UI.active.thickness = thickness
		UI.active.radius = radius
	}

}

ui_box_set_background :: proc(background: Asset_Id, intensity: f32) {
	if UI.active != nil {
		UI.active.background = background
		UI.active.background_intensity = intensity
	}
}

ui_box_set_text :: proc(text: string, color: Color, size: f32) {
	if UI.active != nil {
		UI.active.text = text
		UI.active.text_color = color
		UI.active.pixel_height = size
		UI.active.font = 0
	}
}

ui_box_set_layout :: proc(maj_axis: Axis) {
	if UI.active != nil {
		min_axis := axis_flip(maj_axis)
		UI.active.growth_axis[maj_axis] = 1
		UI.active.growth_axis[min_axis] = 0
		UI.active.logical_size[maj_axis].kind = Logical_Size_Kind.SumOfChildren
		UI.active.logical_size[min_axis].kind = Logical_Size_Kind.MaxOfChildren
		UI.active.center_axis[maj_axis] = 0
		UI.active.center_axis[min_axis] = 1
	}
}


ui_set_style_color :: proc(var: Ui_StyleVar, value: Color) {
	typ := ui_style_var_type(var)
	switch (typ) {
	case .Color:
		UI.style_vars[var].color = value
	case .Number:
		fallthrough
	case:
		fmt.printfln("Writing a color value to ui var %v, that has type %v\n", var, typ)
	}
}

ui_set_style_number :: proc(var: Ui_StyleVar, value: f32) {
	typ := ui_style_var_type(var)
	switch (typ) {
	case .Number:
		UI.style_vars[var].num = value
	case .Color:
		fallthrough
	case:
		fmt.printfln("Writing a number value to ui var %v, that has type %v\n", var, typ)
	}
}

ui_get_style_var :: proc(var: Ui_StyleVar) -> Ui_StyleVarData {
	return UI.style_vars[var]
}

@(private = "file")
ui_get_unit_size :: proc() -> [2]f32 {
	return {ui_get_style_var(Ui_StyleVar.UnitW).num, ui_get_style_var(Ui_StyleVar.UnitH).num}
}

@(private = "file")
ui_space_generic :: proc(x, y: f32) {
	size := ui_get_unit_size() / 2
	ui_box_begin()
	ui_box_pixel_size(size * {x, y})
	ui_box_end()
}

ui_vspace :: proc() {
	ui_space_generic(0, 1)
}

ui_hspace :: proc() {
	ui_space_generic(1, 0)
}

ui_heading :: proc(text: string, width: f32) {
	ui_box_begin()
	defer ui_box_end()

	unit_size := ui_get_unit_size()

	ui_box_set_text(text, BLACK, 32)
	ui_box_pixel_size(unit_size * {width, 2})
}

ui_toggle :: proc(text: string, status: bool) -> bool {
	status := status

	ui_box_begin()
	defer ui_box_end()

	ui_box_pixel_size(ui_get_unit_size())

	sig := ui_box_set_key_from_text(text)

	color: Rect_Gradient
	if status {
		color = ui_get_style_var(Ui_StyleVar.ToggleOnColor).color
	} else if sig.is_hovered {
		color = ui_get_style_var(Ui_StyleVar.ToggleHoverColor).color
	} else {
		color = {}
	}
	ui_box_set_fill(color)

	if sig.is_clicked {
		status = !status
	}

	{
		color := ui_get_style_var(.WidgetBorderColor).color
		thickenss := ui_get_style_var(.WidgetThinBorderThickness).num
		ui_box_set_border(color, thickenss, 0)
	}

	return status
}

ui_button :: proc(text: string, width: f32) -> bool {
	ui_box_begin()
	defer ui_box_end()

	unit_size := ui_get_unit_size()

	sig := ui_box_set_key_from_text(text)

	text_color := ui_get_style_var(.WidgetTextColor).color
	pixel_height := ui_get_style_var(.WidgetTextSize).num

	ui_box_set_text(text, text_color, pixel_height)

	color_var: Ui_StyleVar
	relief: f32 = 1.0
	if sig.is_held {
		color_var = Ui_StyleVar.WidgetHeldColor
		relief *= -1
	} else if sig.is_hovered {
		color_var = Ui_StyleVar.WidgetHoverColor
	} else {
		color_var = Ui_StyleVar.WidgetBaseColor
	}
	color := ui_get_style_var(color_var).color

	ui_box_pixel_size({width, 2} * unit_size)
	ui_box_set_fill(rect_gradient_shaded(color, relief))

	{
		color := ui_get_style_var(.WidgetBorderColor).color
		thickness := ui_get_style_var(.WidgetBorderThickness).num
		radius := ui_get_style_var(.WidgetBorderRadius).num
		ui_box_set_border(rect_gradient_shaded(color, relief), thickness, radius)
	}

	return sig.is_clicked
}

@(deferred_none = ui_box_end)
ui_panel :: proc(axis: Axis) {
	ui_box_begin()
	ui_box_set_layout(axis)

	{
		color := ui_get_style_var(Ui_StyleVar.PanelColor).color
		ui_box_set_fill(color)
	}

	{
		color := ui_get_style_var(.PanelBorderColor).color
		thickness := ui_get_style_var(.PanelBorderThickness).num
		radius := ui_get_style_var(.PanelBorderRadius).num
		ui_box_set_border(rect_gradient_shaded(color, 1), thickness, 0)
	}
}

@(deferred_none = ui_box_end)
ui_row :: proc() {
	ui_box_begin()
	ui_box_set_layout(Axis.Horizontal)

}

@(deferred_none = ui_box_end)
ui_col :: proc() {
	ui_box_begin()
	ui_box_set_layout(Axis.Vertical)
}

