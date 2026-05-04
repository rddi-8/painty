package canvas

import "core:fmt"
import "../color"
import "core:prof/spall"

SPALLINF :: struct {
    spall_ctx: ^spall.Context,
    spall_buffer: ^spall.Buffer,
}

generate_round :: proc(buffer: []f32, size: int) -> DataView(f32) {
    view := DataView(f32){
        data = buffer,
        start_offset = 0,
        stride = size,
        width = size,
        num_rows = size,
    }
    assert(view_size(view) <= len(buffer), "Buffer for generating brush too small")
    iter := view_iter(&view)
    rad := size/2
    rad2 := size*size/4
    for row, y in view_iterate_rows(&iter) {
        for &p, x in row {
            if ((x-rad)*(x-rad) + (y-rad)*(y-rad) < rad2) {
                p = 1
            }
            else {
                p = 0
            }
        }
    }
    return view
}

brush_dab :: proc(brush: DataView(f32), brush_rect: RectI, col: [4]f32, opacity: f32, flow: f32, layer: Layer) {
    tile_iter := view_iter(&layer.canvas.tiles_rect)
    col32 := col
    col32.rgb = color.to_linear(col.rgb)
    // col32 *= flow
    for tile_rect, coord, idx in view_iterate(&tile_iter)
    {
        tiles := layer.tiles.data
        
        
        overlap := rect_intersect(tile_rect, brush_rect)
        if (!rect_is_empty(overlap)) {
            if (tiles[idx] == nil) {
                tiles[idx] = talloc_get(layer.tile_allocator)
            }
            tile_px := tiles[idx].pixels.data

            tb_overlap := view_overlap(tile_rect, brush_rect)
            bt_overlap := view_overlap(brush_rect, tile_rect)
            tb_data := DataView(Pixel){
                view = tb_overlap,
                data = tiles[idx].pixels.data
            }
            bt_data := DataView(f32){
                view = bt_overlap,
                data = brush.data
            }

            tb_iter := view_iter(&tb_data)
            bt_iter := view_iter(&bt_data)

            width := tb_data.width
            for t, b, row_n in view_iterate_rows_dual(&tb_iter, &bt_iter) {
                for i in 0..<width {
                    src := b[i]*col32*flow
                    dst := color.to_col32(t[i])

                    opacity := max(dst.a, opacity)
                    dst = src + dst*(1-src.a)
                    if dst.a > opacity {
                        dst.rgb = dst.rgb * (opacity / dst.a)
                        dst.a   = opacity
                    }

                    t[i] = color.to_color(dst)
                }
            }
            layer.canvas.tiles_changed.data[idx] = true
        }

    }
}

Brush_Dab_Data :: struct {
    pos: [2]int,
    col: [4]f32,
    opacity: f32,
    flow: f32,
}

brush_dab_multi :: proc(brush: DataView(f32), dabs: []Brush_Dab_Data, size: int, layer: Layer) {
    tile_iter := view_iter(&layer.canvas.tiles_rect)

    // col32 := col
    // col32.rgb = color.to_linear(col.rgb)
    // col32.a = col.a * opacity
    for tile_rect, coord, idx in view_iterate(&tile_iter)
    {
        tiles := layer.tiles.data
        
        for dab in dabs {
            brush_rect := RectI{
                pos_size = {
                    pos = dab.pos - Vec2i{size/2, size/2},
                    size = {size, size}
                }
            }
            col32: [4]f32
            col32.rgb = color.to_linear(dab.col.rgb)
            col32.a = dab.col.a * dab.opacity

            overlap := rect_intersect(tile_rect, brush_rect)
            if (!rect_is_empty(overlap)) {
                if (tiles[idx] == nil) {
                    tiles[idx] = talloc_get(layer.tile_allocator)
                }
                tile_px := tiles[idx].pixels.data
    
                tb_overlap := view_overlap(tile_rect, brush_rect)
                bt_overlap := view_overlap(brush_rect, tile_rect)
                tb_data := DataView(Pixel){
                    view = tb_overlap,
                    data = tiles[idx].pixels.data
                }
                bt_data := DataView(f32){
                    view = bt_overlap,
                    data = brush.data
                }
    
                tb_iter := view_iter(&tb_data)
                bt_iter := view_iter(&bt_data)
    
                width := tb_data.width
                for t, b, row_n in view_iterate_rows_dual(&tb_iter, &bt_iter) {
                    for i in 0..<width {
                        blend := b[i]*col32.a
                        dst := color.to_col32(t[i])
                        dst.a = dst.a*(1 - b[i]*col32.a) + b[i]*col32.a
                        dst.rgb = dst.rgb*(1 - blend) + col32.rgb*blend
                        t[i] = color.to_color(dst)
                    }
                }
                layer.canvas.tiles_changed.data[idx] = true
            }

        }
        

    }
}