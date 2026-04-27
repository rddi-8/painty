package canvas

import "core:math/linalg"
import "core:math"
import "core:fmt"
import "core:slice"
import "core:log"
import "core:mem"
import vmem "core:mem/virtual"

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
Rect :: struct {
    pos: [2]int,
    size: [2]int,
}

Canvas :: struct {
    size: [2]int,
    tile_wh: [2]int,
    tile_size: int,
    allocator: mem.Allocator,
    arena: vmem.Arena,
    layer_stack: [dynamic]Layer
}

Tile :: struct {
    size: int,
    pos: [2]int,
    pixel_data: []Pixel,
}

Layer :: struct {
    size: [2]int,
    tile_size: int,
    full_data: []Pixel,
    tiles: []Tile,
}

@require_results
make_canvas :: proc(size: [2]int) -> (canvas: ^Canvas, err: vmem.Allocator_Error) #optional_allocator_error {
    block_size: uint = vmem.DEFAULT_ARENA_GROWING_MINIMUM_BLOCK_SIZE
    canvas = new(Canvas)
    canvas.size = size
    canvas.tile_size = TILE_SIZE
    canvas.tile_wh = {find_tile_fit(canvas.tile_size, canvas.size.x), find_tile_fit(canvas.tile_size, canvas.size.y)}
    arena_err := vmem.arena_init_growing(&canvas.arena, block_size)
    if arena_err != nil {
        log.errorf("Error allocating canvas vmem arena: %v", arena_err)
        canvas = nil
        err = arena_err
        return
    }
    canvas.allocator = vmem.arena_allocator(&canvas.arena)

    return
}

create_layer :: proc(canvas: ^Canvas) -> (layer: Layer, err: vmem.Allocator_Error) #optional_allocator_error {
    layer.size = canvas.size
    layer.tile_size = canvas.tile_size
    tile_size: int = canvas.tile_size
    tiles_w :int = canvas.size.x / tile_size + (1 if canvas.size.x % tile_size != 0 else 0)
    tiles_h :int = canvas.size.y / tile_size + (1 if canvas.size.y % tile_size != 0 else 0)
    fmt.printfln("tile_w: %v, tile_h: %v", tiles_w, tiles_h)
    tile_size_px := tile_size*tile_size
    layer_size_px := tiles_w*tiles_h*tile_size_px
    fmt.printfln("tile_size: %v, tiles_size: %v", tile_size, layer_size_px)
    data_ptr := raw_data(mem.alloc_bytes_non_zeroed(layer_size_px * size_of(Pixel), PIXEL_ALIGNMENT, canvas.allocator) or_return)
    // mem.set(data_ptr, 0, layer_size_px)
    pixel_ptr := cast([^]Pixel)data_ptr
    layer.full_data = pixel_ptr[:layer_size_px]
    layer.tiles = mem.make([]Tile, tiles_w * tiles_h, allocator = canvas.allocator) or_return
    
    for i in 0..<(tiles_w*tiles_h) {
        tile: Tile
        // tile.pixel_data = make([]Pixel, 100, allocator = canvas.allocator) or_return
        tile.pixel_data = pixel_ptr[i*tile_size_px:(i+1)*tile_size_px]
        tile.size = tile_size
        tile.pos = {
            (i % (tiles_w)) * tile_size if tiles_w > 0 else 0,
            (i / (tiles_w)) * tile_size if tiles_w > 0 else 0
        }
        layer.tiles[i] = tile
    }
    return layer, nil
}

fill_layer :: proc(layer: Layer, color: Pixel) {
    slice.fill(layer.full_data, color)
}

vec2f :: #force_inline proc "contextless" (v: [2]int) -> [2]f32 {
    return {f32(v.x), f32(v.y)}
}
vec2i :: #force_inline proc "contextless" (v: [2]f32) -> [2]int {
    return {int(v.x), int(v.y)}
}

find_tile_fit :: proc "contextless" (tilesize: int, width: int) -> int {
    return width / tilesize + (1 if width % tilesize != 0 else 0)
}

tile_coords :: proc "contextless" (tile_index: int, width: int) -> [2]int {
    return {
        tile_index % width if width > 0 else 0,
        tile_index / width if width > 0 else 0
    }
}

tile_index_from_width :: #force_inline proc "contextless" (width: int, pos: [2]int) -> Tile_Index {
    return pos.x %% width + pos.y * width
}

tile_index_from_canvas :: proc "contextless" (canvas: ^Canvas, pos: [2]int) -> Tile_Index {
    return tile_index_from_width(canvas.tile_wh.x, pos)
}



tile_index :: proc{
    tile_index_from_width,
    tile_index_from_canvas,
}

match_tile_index :: proc "contextless" (canvas: ^Canvas, canvas_pos: [2]int) -> Tile_Index {
    canvas_pos := [2]int{canvas_pos.x % canvas.size.x, canvas_pos.y % canvas.size.y}
    tile_pos: [2]int = {canvas_pos.x / canvas.tile_size, canvas_pos.y / canvas.tile_size}
    return tile_index(canvas, tile_pos)
}

match_tile_pos :: proc "contextless" (canvas: ^Canvas, canvas_pos: [2]int) -> [2]int {
    canvas_pos := [2]int{canvas_pos.x % canvas.size.x, canvas_pos.y % canvas.size.y}
    return {canvas_pos.x / canvas.tile_size, canvas_pos.y / canvas.tile_size}
}

match_tiles_rect :: proc "contextless" (canvas: ^Canvas, rect: Rect) -> Rect {
    tl := match_tile_pos(canvas, rect.pos)
    br := match_tile_pos(canvas, rect.pos + rect.size.x)
    return {pos = tl, size = br - tl}
}