package canvas

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

Canvas :: struct {
    size: [2]int,
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