package csv
import "../util"
import "core:mem"
import "core:strconv"

Cell :: struct {
	text:   string,
	number: f32,
}

Row :: []Cell

Table :: []Row

clone_string :: proc(alloc: mem.Allocator, s: string) -> string {
	if len(s) == 0 {
		return ""
	}

	bytes := make([]byte, len(s), allocator = alloc)
	copy(bytes, s)
	return string(bytes)
}

parse :: proc(alloc: mem.Allocator, source: string) -> (Table, []string) {
	table := make_dynamic_array([dynamic]Row, alloc)
	errors := make_dynamic_array([dynamic]string, alloc)

	if len(source) == 0 {
		return table[:], errors[:]
	}

	row := make_dynamic_array([dynamic]Cell, alloc)
	i := 0

	for {
		text := ""

		if i < len(source) && source[i] == '"' {
			scratch := util.with_scratch({alloc})
			field := make_dynamic_array([dynamic]byte, scratch.arena)
			i += 1
			closed := false

			for i < len(source) {
				if source[i] == '"' {
					if i + 1 < len(source) && source[i + 1] == '"' {
						append(&field, byte('"'))
						i += 2
						continue
					}

					closed = true
					i += 1
					break
				}

				append(&field, source[i])
				i += 1
			}

			if !closed {
				append(&errors, "unterminated quoted field")
			} else if i < len(source) &&
			   source[i] != ',' &&
			   source[i] != '\n' &&
			   source[i] != '\r' {
				append(&errors, "unexpected characters after closing quote")
				for i < len(source) && source[i] != ',' && source[i] != '\n' && source[i] != '\r' {
					append(&field, source[i])
					i += 1
				}
			}

			text = clone_string(alloc, string(field[:]))
		} else {
			start := i
			saw_quote := false

			for i < len(source) && source[i] != ',' && source[i] != '\n' && source[i] != '\r' {
				if source[i] == '"' {
					saw_quote = true
				}
				i += 1
			}

			if saw_quote {
				append(&errors, "unexpected quote in unquoted field")
			}

			text = clone_string(alloc, source[start:i])
		}


		number, ok := strconv.parse_f32(text)
		if !ok {
			number = 0
		}

		append(&row, Cell{text = text, number = number})

		if i >= len(source) {
			append(&table, row[:])
			break
		}

		if source[i] == ',' {
			i += 1
			continue
		}

		append(&table, row[:])
		row = make_dynamic_array([dynamic]Cell, alloc)

		if source[i] == '\r' {
			i += 1
			if i < len(source) && source[i] == '\n' {
				i += 1
			}
		} else {
			i += 1
		}

		if i >= len(source) {
			break
		}
	}

	return table[:], errors[:]
}

Row_Reader :: struct {
	row:      Row,
	cell_idx: int,
}

read_row :: proc(row: Row) -> Row_Reader {
	return {row = row, cell_idx = 0}
}

read_cell :: proc(row: ^Row_Reader) -> Cell {
	cell: Cell
	if row.cell_idx < len(row.row) {
		row.cell_idx += 1
		cell = row.row[row.cell_idx - 1]
	}
	return cell
}

read_num :: proc(row: ^Row_Reader) -> f32 {
	return read_cell(row).number
}

read_text :: proc(row: ^Row_Reader) -> string {
	return read_cell(row).text
}

