package canvas

import "core:fmt"
import "../color"

generate_round :: proc(buffer: []Pixel, size: int) -> DataView(Pixel) {
    view := DataView(Pixel){
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
                p = {1,1,1,1}
            }
            else {
                p = {0,0,0,0}
            }
        }
    }
    return view
}


brush_dab :: proc(brush: DataView(Pixel), brush_rect: RectI, col: Pixel, layer: Layer) {
    tile_iter := view_iter(&layer.canvas.tiles_rect)

    col32 := color.to_col32(col)
    for tile_rect, coord, idx in view_iterate(&tile_iter)
    {
        tiles := layer.tiles.data
        tile_px := tiles[idx].pixels.data


        overlap := rect_intersect(tile_rect, brush_rect)
        if (!rect_is_empty(overlap)) {

            tb_overlap := view_overlap(tile_rect, brush_rect)
            bt_overlap := view_overlap(brush_rect, tile_rect)
            tb_data := DataView(Pixel){
                view = tb_overlap,
                data = tiles[idx].pixels.data
            }
            bt_data := DataView(Pixel){
                view = bt_overlap,
                data = brush.data
            }

            tb_iter := view_iter(&tb_data)
            bt_iter := view_iter(&bt_data)

            width := tb_data.width
            for t, b, row_n in view_iterate_rows_dual(&tb_iter, &bt_iter) {
                for i in 0..<width {
                    src := color.to_col32(b[i])
                    dst := color.to_col32(t[i])
                    dst.rgb = dst.rgb*(1 - src.a) + col32.rgb*src.a
                    t[i] = color.to_color(dst)
                    // t[i].rgb = t[i].rgb*(1 - b[i].a) + col.rgb*b[i].a
                }
            }
            layer.canvas.tiles_changed.data[idx] = true
        }

    }
}