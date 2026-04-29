package canvas

import "core:container/queue"
import "core:mem"
import vmem "core:mem/virtual"

DEFAULT_RESERVE :: 4
Tile_Allocator :: struct {
	backing_allocator: mem.Allocator,
	tile_size: int,
    free_list: queue.Queue(^Tile),
}

talloc_reserve :: proc(talloc: ^Tile_Allocator, tile_count: int) -> mem.Allocator_Error {
	tile_size2: int = talloc.tile_size * talloc.tile_size
	tile_data_size: int = tile_size2 * size_of(Pixel)
	data := raw_data(mem.alloc_bytes_non_zeroed(tile_data_size * tile_count, PIXEL_ALIGNMENT, talloc.backing_allocator) or_return)
	pixel_ptr := cast([^]Pixel)data
	for i in 0..<tile_count {
		tile := new(Tile)
		tile.pixels = {
			start_offset = 0,
			stride = talloc.tile_size,
			width = talloc.tile_size,
			num_rows = talloc.tile_size,
			data = pixel_ptr[tile_size2 * i : tile_size2 * (i + 1)]
		}
		queue.push_back(&talloc.free_list, tile)
	}

	return nil
}

talloc_pop :: proc(talloc: ^Tile_Allocator) -> ^Tile {
	tile, ok := queue.pop_back_safe(&talloc.free_list)
	if ok {
		return tile
	}
	else {
		talloc_reserve(talloc, DEFAULT_RESERVE)
		return queue.pop_back(&talloc.free_list)
	}
}

talloc_return :: proc(talloc: ^Tile_Allocator, tile: ^Tile) {
	queue.push_back(&talloc.free_list, tile)
}