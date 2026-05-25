package main

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

import "csv"
import "util"
import image "vendor:stb/image"


Sprite_Atlas_Region :: struct {
	name: string,
	x:    int,
	y:    int,
	w:    int,
	h:    int,
}

Sprite_Atlas :: struct {
	image_path: string,
	regions:    []Sprite_Atlas_Region,
}

sprite_atlas_create :: proc(inpath: string, outpath: string) {
	scratch := util.with_scratch(nil)

	Sprite :: struct {
		name:  string,
		bytes: [^]byte,
		size:  [2]i32,
	}

	sprites := make([dynamic]Sprite, 0, 64, scratch.arena)
	defer for sprite in sprites {
		if sprite.bytes != nil {
			image.image_free(sprite.bytes)
		}
	}

	files, err := os.read_directory_by_path(inpath, 0, scratch.arena)
	if err != nil {
		fmt.printfln("ERROR: Failed to read sprite directory %q", inpath)
		return
	}

	for file in files {
		if file.type == .Directory || !strings.has_suffix(file.name, ".png") {
			continue
		}

		sprite: Sprite
		channels: i32
		cpath := strings.clone_to_cstring(file.fullpath, scratch.arena)
		sprite.bytes = image.load(cpath, &sprite.size.x, &sprite.size.y, &channels, 4)
		if sprite.bytes == nil {
			fmt.printfln("ERROR: Failed to load sprite %q", file.fullpath)
			return
		}

		sprite.name = os.stem(file.name)
		append(&sprites, sprite)
	}

	if len(sprites) == 0 {
		fmt.printfln("ERROR: No sprite images found in %q", inpath)
		return
	}

	{
		sort_proc := proc(sprite: Sprite) -> i32 {
			return -sprite.size.y
		}
		slice.sort_by_key(sprites[:], sort_proc)
	}

	regions := make([dynamic]Sprite_Atlas_Region, 0, len(sprites), scratch.arena)

	padding :: 8
	max_width :: 2048

	x := padding
	y := padding
	shelf_height := 0
	atlas_width := padding

	for sprite in sprites {
		sprite_w := int(sprite.size.x)
		sprite_h := int(sprite.size.y)

		if x + sprite_w + padding > max_width && shelf_height > 0 {
			x = padding
			y += shelf_height + padding
			shelf_height = 0
		}

		region := Sprite_Atlas_Region {
			name = sprite.name,
			x    = x,
			y    = y,
			w    = sprite_w,
			h    = sprite_h,
		}
		append(&regions, region)

		x += sprite_w + padding
		shelf_height = max(shelf_height, sprite_h)
		atlas_width = max(atlas_width, region.x + region.w + padding)
	}

	atlas_height := y + shelf_height + padding
	atlas_pixels := make([]byte, atlas_width * atlas_height * 4, allocator = scratch.arena)

	for sprite, idx in sprites {
		region := regions[idx]
		sprite_w := int(sprite.size.x)
		sprite_h := int(sprite.size.y)

		for row := 0; row < sprite_h; row += 1 {
			src_offset := row * sprite_w * 4
			dst_offset := ((region.y + row) * atlas_width + region.x) * 4

			src_row := sprite.bytes[src_offset:src_offset + sprite_w * 4]
			dst_row := atlas_pixels[dst_offset:dst_offset + sprite_w * 4]
			copy(dst_row, src_row)
		}
	}

	csv_path := strings.join({outpath, ".csv"}, "", scratch.arena)
	{
		sb := strings.builder_make(scratch.arena)
		strings.write_string(&sb, outpath)
		strings.write_string(&sb, ".png")

		for region in regions {
			strings.write_string(&sb, "\n")
			strings.write_string(&sb, region.name)
			strings.write_string(&sb, ",")
			strings.write_int(&sb, region.x)
			strings.write_string(&sb, ",")
			strings.write_int(&sb, region.y)
			strings.write_string(&sb, ",")
			strings.write_int(&sb, region.w)
			strings.write_string(&sb, ",")
			strings.write_int(&sb, region.h)
		}

		csv_contents := strings.to_string(sb)
		if err := os.write_entire_file(csv_path, csv_contents); err != nil {
			fmt.printfln("ERROR: Failed to write atlas csv %q", csv_path)
			return
		}
	}

	image_path := strings.join({outpath, ".png"}, "", scratch.arena)
	coutpath := strings.clone_to_cstring(image_path, scratch.arena)
	if image.write_png(
		   coutpath,
		   i32(atlas_width),
		   i32(atlas_height),
		   4,
		   raw_data(atlas_pixels),
		   i32(atlas_width * 4),
	   ) ==
	   0 {
		fmt.printfln("ERROR: Failed to write atlas image %q", outpath)
		return
	}

	fmt.printfln("Wrote sprite atlas %q and %q", outpath, csv_path)
}

sprite_atlas_load :: proc(csv_path: string) -> (atlas: Sprite_Atlas, ok: bool) {
	scratch := util.with_scratch(nil)

	source, err := os.read_entire_file(csv_path, scratch.arena)
	if err != nil {
		fmt.printfln("ERROR: Failed to read sprite atlas csv %q", csv_path)
		return {}, false
	}

	table, csv_errors := csv.parse(scratch.arena, string(source))
	if len(csv_errors) > 0 {
		for csv_err in csv_errors {
			fmt.printfln("ERROR: Sprite atlas csv parse error: %s", csv_err)
		}
		return {}, false
	}

	if len(table) == 0 || len(table[0]) == 0 {
		fmt.printfln("ERROR: Sprite atlas csv %q is empty", csv_path)
		return {}, false
	}

	atlas.image_path = strings.clone(table[0][0].text, context.allocator)
	regions := make([dynamic]Sprite_Atlas_Region, 0, max(0, len(table) - 1), context.allocator)

	for row_idx in 1 ..< len(table) {
		row := table[row_idx]
		if len(row) == 0 {
			continue
		}
		if len(row) != 5 {
			fmt.printfln("ERROR: Sprite atlas csv row %d should have 5 columns", row_idx + 1)
			return {}, false
		}

		reader := csv.read_row(row)
		region := Sprite_Atlas_Region {
			name = strings.clone(csv.read_text(&reader), context.allocator),
			x    = int(csv.read_num(&reader)),
			y    = int(csv.read_num(&reader)),
			w    = int(csv.read_num(&reader)),
			h    = int(csv.read_num(&reader)),
		}
		append(&regions, region)
	}

	atlas.regions = regions[:]
	return atlas, true
}

