package canvas

import "base:runtime"
import "core:math/rand"
import "base:intrinsics"
import "core:fmt"
import sdl "vendor:sdl3"
import mu "../microui"
import "core:math"
import "core:time"

// @(private="file")
// RectIv :: struct {
//     pos: [2]int,
//     size: [2]int,
// }
// @(private="file")
// RectIe :: struct {
//     x,y,w,h: int
// }
// RectI :: struct #raw_union {
//     using _e: RectIe,
//     using _v: RectIv,
// }

// @(private="file")
// RectFv :: struct {
//     pos: [2]f32,
//     size: [2]f32,
// }
// @(private="file")
// RectFe :: struct {
//     x,y,w,h: f32
// }
// RectF :: struct #raw_union {
//     using _e: RectFe,
//     using _v: RectFv,
// }

// @(private="file")
Rect_v :: struct($T: typeid) where intrinsics.type_is_numeric(T) {
    pos: [2]T,
    size: [2]T,
}
// @(private="file")
Rect_e :: struct($T: typeid) where intrinsics.type_is_numeric(T) {
    x,y,w,h: T
}
Rect :: struct($T: typeid) #raw_union where intrinsics.type_is_numeric(T) {
    using xywh: Rect_e(T),
    using pos_size: Rect_v(T),
}

RectF :: Rect(f32)
RectI :: Rect(int)

Vec2 :: [2]f32
Vec2i :: [2]int

Corner :: enum {
    TL,
    TR,
    BR,
    BL,
}

RectView :: struct {
    start_offset: int,
    width: int,
    stride: int,
    num_rows: int,
}

DataView :: struct($T: typeid) {
    using view: RectView,
    data: []T,
}

main :: proc() {

    test2()
    
}

test3 :: proc() {
    fmt.println("testing")
    canvas := make_canvas({600, 512})
    for tile, idx in canvas.tiles_rect.data {
        fmt.printfln("tile[%v] pos = %v, size = %v", idx, tile.pos, tile.size )
    }
}

test2 :: proc() {
    region: DataView(string)
    region.view = {
        width = 8,
        start_offset = 0,
        stride = 8,
        num_rows = 4,
    }

    h: RectF

    

    data: [dynamic]string
    for i in 0..<view_size(region.view) {
        pos := view_get_point(region.view, i)
        append(&data, fmt.tprint(pos))
    }
    region.data = data[:]

    clip_rect := view_overlap({xywh = {32,64,16,16}}, {xywh = {40, 50, 16, 16}})
    subregion := DataView(string){
        data = data[:],
        view = clip_rect,
    }

    fmt.println(clip_rect)

    iterator := View_Iter(string){view = &subregion, current_offset = subregion.start_offset}

    iterator2 := view_iter(&subregion)

    fmt.println("Iter 1")
    for elem, coord, idx in view_iterate(&iterator2) {
        fmt.printfln("elem: %v, c: %v, idx: %v", elem, coord, idx)
    }

    iterator3 := view_iter(&subregion)
    // fmt.println("Iter 2")
    // for row, row_n in view_iterate_rows(&iterator3) {
    //     for elem, x in row {
    //         fmt.printfln("elem: %v, c: %v", elem, Vec2i{x, row_n})
    //     }
    // }

    fmt.println(in_range(10, 11, 12))

}

test1 :: proc() {
    N :: 1000
    rects: [N]RectF
    for i in 0..<N {
        rects[i] = rectf(
            rand.float32_range(-100, 100),
            rand.float32_range(-100, 100),
            rand.float32_range(-100, 100),
            rand.float32_range(-100, 100))
    }

    start := time.tick_now()
    result: RectF
    for i in 0..<N {
        for j in 0..<N {
            sect := rect_intersect(rects[i], rects[j])
            result.x += sect.x
            result.y += sect.y
            result.w += sect.w
            result.h += sect.h
        }
    }
    end := time.tick_now()
    fmt.printfln("Result: %v", result.pos_size)
    fmt.printfln("Time taken: %v", time.tick_diff(start, end))
}

rectf_from_i :: #force_inline proc "contextless" (rect: RectI) -> RectF {
    return { pos_size = {pos = to_vec2f(rect.pos), size = to_vec2f(rect.size)}}
}
rectf_from_sdl :: #force_inline proc "contextless" (rect: sdl.Rect) -> RectF {
    return { pos_size = {pos = to_vec2f(rect.x, rect.y), size = to_vec2f(rect.w, rect.h)}}
}
rectf_from_sdlf :: #force_inline proc "contextless" (rect: sdl.FRect) -> RectF {
    return { pos_size = {pos = {rect.x, rect.y}, size = {rect.w, rect.h}}}
}
rectf_from_mu :: #force_inline proc "contextless" (rect: mu.Rect) -> RectF {
    return { pos_size = {pos = to_vec2f(rect.x, rect.y), size = to_vec2f(rect.w, rect.h)}}
}
rectf_from_ps :: #force_inline proc "contextless" (pos, size: [2]f32) -> RectF {
    return { pos_size = {pos = pos, size = size}}
}
rectf_from_e :: #force_inline proc "contextless" (x, y, w, h: f32) -> RectF {
    return { xywh = {x, y, w, h}}
}
rectf :: proc{
    rectf_from_i,
    rectf_from_sdl,
    rectf_from_sdlf,
    rectf_from_mu,
    rectf_from_ps,
    rectf_from_e,
}

recti_from_i :: #force_inline proc "contextless" (rect: RectF) -> RectI {
    return { pos_size = {pos = to_vec2i(rect.pos), size = to_vec2i(rect.size)}}
}
recti_from_sdl :: #force_inline proc "contextless" (rect: sdl.Rect) -> RectI {
    return { pos_size = {pos = to_vec2i(rect.x, rect.y), size = to_vec2i(rect.w, rect.h)}}
}
recti_from_sdlf :: #force_inline proc "contextless" (rect: sdl.FRect) -> RectI {
    return { pos_size = {pos = to_vec2i(rect.x, rect.y), size = to_vec2i(rect.w, rect.h)}}
}
recti_from_mu :: #force_inline proc "contextless" (rect: mu.Rect) -> RectI {
    return { pos_size = {pos = to_vec2i(rect.x, rect.y), size = to_vec2i(rect.w, rect.h)}}
}
recti_from_ps :: #force_inline proc "contextless" (pos, size: [2]int) -> RectI {
    return { pos_size = {pos = pos, size = size}}
}
recti_from_e :: #force_inline proc "contextless" (x, y, w, h: int) -> RectI {
    return { xywh = {x, y, w, h}}
}
recti :: proc{
    recti_from_i,
    recti_from_sdl,
    recti_from_sdlf,
    recti_from_mu,
    recti_from_ps,
    recti_from_e,
}

to_vec2f_1 :: #force_inline proc "contextless" (v: [2]int) -> [2]f32 {
    return {f32(v.x), f32(v.y)}
}
to_vec2f_2 :: #force_inline proc "contextless" (x,y: int) -> [2]f32 {
    return {f32(x), f32(y)}
}
to_vec2f_3 :: #force_inline proc "contextless" (x,y: i32) -> [2]f32 {
    return {f32(x), f32(y)}
}
to_vec2f :: proc {to_vec2f_1, to_vec2f_2, to_vec2f_3}

to_vec2i_1 :: #force_inline proc "contextless" (v: [2]f32) -> [2]int {
    return {int(v.x), int(v.y)}
}
to_vec2i_2 :: #force_inline proc "contextless" (x,y: f32) -> [2]int {
    return {int(x), int(y)}
}
to_vec2i_3 :: #force_inline proc "contextless" (x,y: i32) -> [2]int {
    return {int(x), int(y)}
}
to_vec2i :: proc {to_vec2i_1, to_vec2i_2, to_vec2i_3}

lerpi :: #force_inline proc "contextless" (a,b: int, t: f32) -> int {
    return a + int(f32(b - a)*t)
}
lerpi_u64 :: #force_inline proc "contextless" (a,b: u64, t: f32) -> u64 {
    return a + u64(f32(b - a)*t)
}

rect_intersect :: proc "contextless" (a,b: Rect($T)) -> Rect(T) {
    x1 := max(a.x, b.x)
    y1 := max(a.y, b.y)
    x2 := min(a.x + a.w, b.x + b.w)
    y2 := min(a.y + a.h, b.y + b.h)
    if x2 < x1 do x2 = x1
    if y2 < y1 do y2 = y1
    return {xywh = {x1, y1, x2 - x1, y2 - y1}}
}

rect_intersect_area :: proc "contextless" (a,b: Rect($T)) -> T {
    intersect_rect := rect_intersect(a, b)
    return intersect_rect.w * intersect_rect.h
}

rect_center :: proc "contextless" (size, center: [2]$T) -> Rect(T) {
    return {pos_size = {pos = center - size/2, size = size}}
}


in_range :: #force_inline proc "contextless" (value, low, high: $T) -> bool where intrinsics.type_is_numeric(T) {
    return value >= low && value <= high
}

in_range_open :: #force_inline proc "contextless" (value, low, high: $T) -> bool where intrinsics.type_is_numeric(T) {
    return value > low && value < high
}


rectf_has_point :: proc "contextless" (rect: RectF, point: [2]f32) -> bool {
    return in_range(point.x, rect.x, rect.x + rect.w) && in_range(point.y, rect.y, rect.y + rect.h)
}

recti_has_point :: proc "contextless" (rect: RectI, point: [2]int) -> bool {
    return in_range(point.x, rect.x, rect.x + rect.w) && in_range(point.y, rect.y, rect.y + rect.h)
}

rect_has_point :: proc {
    rectf_has_point,
    recti_has_point,
}

rect_is_empty :: proc "contextless" (rect: Rect($T)) -> bool {
    return rect.size.x == 0 || rect.size.y == 0
}

rect_points :: proc "contextless" (rect: Rect($T)) -> [Corner][2]T {
    return {
        .TL = rect.pos,
        .TR = {rect.pos.x + rect.w, rect.pos.y},
        .BR = rect.pos + rect.size,
        .BL = {rect.pos.x, rect.pos.y + rect.h}
    }
}

rect_grow :: proc "contextless" (rect: Rect($T), points: ..[2]T) -> Rect(T) {
    if len(points) == 0 do return rect

    min_x := rect.x
    min_y := rect.y
    max_x := rect.x + rect.w
    max_y := rect.y + rect.h
    
    for point in points {
        min_x = min(min_x, point.x)
        max_x = max(max_x, point.x)
        min_y = min(min_y, point.y)
        max_y = max(max_y, point.y)
    }
    
    return {xywh = {min_x, min_y, max_x - min_x, max_y - min_y}}
}

rect_grow_rect :: proc "contextless" (rect: Rect($T), other: Rect(T)) -> Rect(T) {
    return rect_grow(rect, other.x, other.y, (other.x + other.w), (other.y + other.h))
}

rect_grow_rects :: proc "contextless" (rect: Rect($T), others: ..Rect(T)) -> Rect(T) {
    if len(others) == 0 do return rect

    min_x := rect.x
    min_y := rect.y
    max_x := rect.x + rect.w
    max_y := rect.y + rect.h

    for rect in others {
        for point in rect_points(rect) {
            min_x = min(min_x, point.x)
            max_x = max(max_x, point.x)
            min_y = min(min_y, point.y)
            max_y = max(max_y, point.y)
        }
    }

    return {xywh = {min_x, min_y, max_x - min_x, max_y - min_y}}

}

rect_move :: proc "contextless" (rect: Rect($T), offset: [2]T) -> Rect(T) {
    return {pos_size = {pos = rect.pos + offset, size = rect.size}}
}



view_overlap :: proc "contextless" (area: RectI, inner: RectI) -> RectView {
    area := area
    inner := inner
    inner.pos -= area.pos
    area.pos = {0, 0}
    clipped := rect_intersect(area, inner)
    width := area.w
    return {
        start_offset = clipped.y * width + clipped.x,
        width = clipped.w,
        stride = width,
        num_rows = clipped.h
    }
}

tile_overlap :: proc "contextless" (tile_size: int, inner: RectI) -> RectView {
    return view_overlap({ xywh = {0, 0, tile_size, tile_size}}, inner)
}

rect_as_view :: proc "contextless" (rect: RectI, container_width: int = 0) -> RectView {
    if container_width == 0 {
        return {
            start_offset = 0,
            width = rect.w,
            stride = rect.w,
            num_rows = rect.h
        }
    }
    else {
        return {
            start_offset = rect.x + rect.y*container_width,
            width = rect.w,
            stride = container_width,
            num_rows = rect.h,
        }
    }
}


view_size :: proc "contextless" (view: RectView) -> int {
    return view.width * view.num_rows
}

view_tail :: proc "contextless" (view: RectView) -> int {
    return view.start_offset + view_size(view)
}

view_get_index :: proc "contextless" (view: RectView, point: Vec2i) -> int {
    return view.start_offset + (point.y * view.stride) + point.x
}

view_get_point :: proc "contextless" (view: RectView, index: int) -> Vec2i {
    local_index := index - view.start_offset
    return {local_index % view.stride, local_index / view.stride}
}

view_rebase :: proc "contextless" (view: RectView) -> RectView {
    return {
        start_offset = 0,
        width = view.width,
        stride = view.width,
        num_rows = view.num_rows
    }
}




View_Iter :: struct($T: typeid) {
    current_offset: int,
    xpos: int,
    row: int,
    view: ^DataView(T),
}

Row_Iter :: struct($T: typeid) {
    run: proc(row_iter: ^Row_Iter(T)) -> (val: []T, cond: bool)
}

view_iter :: proc(data_view: ^DataView($T)) -> View_Iter(T) {
    return {
        current_offset = data_view.start_offset,
        row = 0,
        xpos = 0,
        view = data_view,
    }
}

view_iterate_rows :: proc(iter: ^View_Iter($T)) -> (val: []T, n: int, cond: bool) {
    view := iter.view
    if (iter.row < view.num_rows) {
        row_start := view.start_offset + iter.row*view.stride
        val = view.data[row_start : row_start + view.width]
        n = iter.row
        cond = true
        iter.row += 1
        return
    }
    else {
        cond = false
        return
    }
}

view_iterate_rows_dual :: proc(iter1: ^View_Iter($T1), iter2: ^View_Iter($T2)) -> (val1: []T1, val2: []T2, n: int, cond: bool) {
    view1 := iter1.view
    view2 := iter2.view
    if (iter1.row < view1.num_rows) {
        row_start1 := view1.start_offset + iter1.row*view1.stride
        row_start2 := view2.start_offset + iter1.row*view2.stride
        val1 = view1.data[row_start1 : row_start1 + view1.width]
        val2 = view2.data[row_start2 : row_start2 + view2.width]
        n = iter1.row
        cond = true
        iter1.row += 1
        return
    }
    else {
        cond = false
        return
    }
}

view_iterate :: proc(iter: ^View_Iter($T)) -> (val: T, coord: Vec2i, offset: int, cond: bool) {
    data := iter.view.data
    view := iter.view.view
    if len(data) <= iter.current_offset || iter.row >= view.num_rows {
        offset = iter.current_offset
        cond = false
        return 
    }
    else {
        val = data[iter.current_offset]
        coord = view_get_point(view, iter.current_offset)
        offset = iter.current_offset
        cond = true
        iter.current_offset += 1
        iter.xpos += 1
        // fmt.println(iter.xpos)
        if (iter.xpos >= view.width) {
            iter.row += 1
            iter.current_offset += view.stride - iter.xpos
            iter.xpos = 0
        }
        return
    }
}

view_iterate_ptr :: proc(iter: ^View_Iter($T)) -> (val: ^T, coord: Vec2i, offset: int, cond: bool) {
    data := iter.view.data
    view := iter.view.view
    if len(data) <= iter.current_offset || iter.row >= view.num_rows {
        offset = iter.current_offset
        cond = false
        return 
    }
    else {
        val = &data[iter.current_offset]
        coord = view_get_point(view, iter.current_offset)
        offset = iter.current_offset
        cond = true
        iter.current_offset += 1
        iter.xpos += 1
        // fmt.println(iter.xpos)
        if (iter.xpos >= view.width) {
            iter.row += 1
            iter.current_offset += view.stride - iter.xpos
            iter.xpos = 0
        }
        return
    }
}



//find how many tiles needed to fit given width
find_tile_fit :: proc "contextless" (tilesize: int, width: int) -> int {
    return width / tilesize + (1 if width % tilesize != 0 else 0)
}

// tile_coords :: proc "contextless" (tile_index: int, width: int) -> [2]int {
//     return {
//         tile_index % width if width > 0 else 0,
//         tile_index / width if width > 0 else 0
//     }
// }

// tile_index_from_width :: #force_inline proc "contextless" (width: int, pos: [2]int) -> Tile_Index {
//     return pos.x %% width + pos.y * width
// }

// tile_index_from_canvas :: proc "contextless" (canvas: ^Canvas, pos: [2]int) -> Tile_Index {
//     return tile_index_from_width(canvas.tile_wh.x, pos)
// }



// tile_index :: proc{
//     tile_index_from_width,
//     tile_index_from_canvas,
// }

// match_tile_index :: proc "contextless" (canvas: ^Canvas, canvas_pos: [2]int) -> Tile_Index {
//     canvas_pos := [2]int{canvas_pos.x % canvas.size_px.x, canvas_pos.y % canvas.size_px.y}
//     tile_pos: [2]int = {canvas_pos.x / canvas.tile_size, canvas_pos.y / canvas.tile_size}
//     return tile_index(canvas, tile_pos)
// }

match_tile_pos :: proc "contextless" (canvas: ^Canvas, canvas_pos: [2]int) -> [2]int {
    canvas_pos := [2]int{canvas_pos.x % canvas.size_px.x, canvas_pos.y % canvas.size_px.y}
    return {canvas_pos.x / canvas.tile_size, canvas_pos.y / canvas.tile_size}
}

// match_tiles_rect :: proc "contextless" (canvas: ^Canvas, rect: RectI) -> RectI {
//     tl := match_tile_pos(canvas, rect.pos)
//     br := match_tile_pos(canvas, rect.pos + rect.size.x)
//     return { pos_size = {pos = tl, size = br - tl}}
// }