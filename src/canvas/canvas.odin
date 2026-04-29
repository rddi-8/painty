package canvas

import "core:container/queue"
import "core:math/linalg"
import "core:math"
import "core:fmt"
import "core:slice"
import "core:log"
import "core:mem"
import vmem "core:mem/virtual"
import "core:container/pool"

MAX_SIZE :: 32768
TILE_SIZE :: 8 * 32
BLOCK_SIZE :: 8
PIXEL_ALIGNMENT :: 64


Pixel :: [4]f16

Error :: enum byte {
    CANVAS_CREATE_ERROR,
    CANVAS_ALLOCATION_ERROR,
    TILE_ALLOCATION_ERROR,
    LAYER_ALLOCATION_ERROR,
}

Tile_Index :: int


Canvas :: struct {
    size_px: [2]int,
    tiles_rect: DataView(TileRect),
    tile_size: int,
    canvas_rect: RectI,
    allocator: mem.Allocator,
    meta_allocator: mem.Allocator,
    arena: vmem.Arena,
    layer_stack: [dynamic]Layer,
    composite_layer: Layer,
    tile_allocator: ^Tile_Allocator,
}




Tile :: struct {
    non_empty: bool,
    pixels: DataView(Pixel)
}

TileRect :: RectI

Layer :: struct {
    using canvas: ^Canvas,
    tiles: DataView(^Tile),
}

@require_results
make_canvas :: proc(size: [2]int) -> (canvas: ^Canvas, err: vmem.Allocator_Error) #optional_allocator_error {
    //init alloc
    block_size: uint = vmem.DEFAULT_ARENA_GROWING_MINIMUM_BLOCK_SIZE
    canvas = new(Canvas)
    arena_err := vmem.arena_init_growing(&canvas.arena, block_size)
    if arena_err != nil {
        log.errorf("Error allocating canvas vmem arena: %v", arena_err)
        canvas = nil
        err = arena_err
        return
    }
    canvas.allocator = vmem.arena_allocator(&canvas.arena)
    canvas.meta_allocator = context.allocator
    
    tile_size: int = TILE_SIZE
    canvas.tile_allocator = new(Tile_Allocator, allocator = canvas.meta_allocator)
    canvas.tile_allocator.tile_size = tile_size
    canvas.tile_allocator.backing_allocator = canvas.allocator

    canvas.size_px = size
    canvas.tile_size = tile_size
    canvas.canvas_rect = recti(to_vec2i(0), size)
    w, h: = find_tile_fit(tile_size, canvas.size_px.x), find_tile_fit(tile_size, canvas.size_px.y)
    tiles := make([dynamic]TileRect, w*h, allocator = canvas.meta_allocator)
    canvas.tiles_rect = {
        start_offset = 0,
        width = w,
        stride = w,
        num_rows = h,
        data = tiles[:],
    }

    tile_iterator := view_iter(&canvas.tiles_rect)
    for tile, coord in view_iterate_ptr(&tile_iterator) {
        tile_rect := RectI{pos_size = {pos = coord * tile_size, size = tile_size}}
        tile_rect = rect_intersect(tile_rect, canvas.canvas_rect)
        tile^ = tile_rect
    }

    canvas.composite_layer = create_layer(canvas) or_return
    fill_layer(canvas.composite_layer, {0.1, 0.2, 0.3, 1})
  
    return
}

create_layer :: proc(canvas: ^Canvas) -> (layer: Layer, err: vmem.Allocator_Error) #optional_allocator_error {
    layer.canvas = canvas
    tiles := make([dynamic]^Tile, canvas.tiles_rect.width * canvas.tiles_rect.num_rows, allocator = canvas.meta_allocator) or_return
    layer.tiles = {
        view = canvas.tiles_rect.view,
        data = tiles[:]
    }
    return layer, nil
}

fill_layer :: proc(layer: Layer, color: Pixel) {
    tile_count := view_size(layer.tiles.view)
    talloc_reserve(layer.tile_allocator, tile_count)
    for i in 0..<tile_count {
        tile := talloc_pop(layer.tile_allocator)
        tile.non_empty = true
        slice.fill(tile.pixels.data[:], color)
        layer.tiles.data[i] = tile
    }
}