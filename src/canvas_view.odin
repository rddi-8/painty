package main

import "core:fmt"
import "core:math/linalg"
Canvas_View :: struct {
    translation: [2]f32,
    pivot_offset: [2]f32,
    angle: f32,
    scale: f32,
    screen: [2]f32,
    flip: bool,
}

matrix3_translate :: proc(x, y: f32) -> linalg.Matrix3f32 {
    m := linalg.MATRIX3F32_IDENTITY
    m[2][0] = x
    m[2][1] = y
    return m
}

view_transform :: proc(view: ^Canvas_View) -> Transform {
    screen_scale := linalg.matrix3_scale_f32({2/view.screen.x, -2/view.screen.y, 1})
    scale := linalg.matrix3_scale_f32({view.scale, view.scale, 1})
    rotation := linalg.Matrix3f32(linalg.matrix2_rotate_f32(view.angle))
    
    screen_offset := matrix3_translate(-view.screen.x/2, -view.screen.y/2)
    canvas_translate := matrix3_translate(view.translation.x, view.translation.y)
    pivot_offset := matrix3_translate(-view.pivot_offset.x, -view.pivot_offset.y)

    flip := linalg.matrix3_scale_f32({-1 if view.flip else 1, 1, 1})
    
    return  screen_scale * screen_offset * canvas_translate * flip * rotation * scale * pivot_offset
}

view_translate :: proc(view: ^Canvas_View, translate: [2]f32) {
    view.pivot_offset += translate
}

view_rotate :: proc(view: ^Canvas_View, angle: f32) {
    view.angle += angle
}

view_flip :: proc(view: ^Canvas_View) {
    view.flip = !view.flip
}

view_scale :: proc(view: ^Canvas_View, scale: f32) {
    view.scale *= scale
}

view_to_canvas :: proc(view: ^Canvas_View, screen_pos: [2]f32) -> [2]f32 {
    ndc: linalg.Vector3f32 = {2*screen_pos.x/view.screen.x - 1, -2*screen_pos.y/view.screen.y + 1, 1}
    canvas_pos := linalg.inverse(view_transform(view)) * ndc
    return canvas_pos.xy
}

view_from_canvas :: proc(view: ^Canvas_View, canvas_pos: [2]f32) -> [2]f32 {
    ndc := view_transform(view) * [3]f32{canvas_pos.x, canvas_pos.y, 1}
    return {view.screen.x * (ndc.x + 1)/2, view.screen.y * (ndc.y + 1)/2}
}

view_center :: proc(view: ^Canvas_View, canvas: [2]f32) {
    view.pivot_offset = canvas/2
    view.translation = view.screen/2
}

view_set_pivot :: proc(view: ^Canvas_View, screen_pos: [2]f32) {
    view.pivot_offset = view_to_canvas(view, screen_pos)
    view.translation = screen_pos
}

view_fit :: proc(view: ^Canvas_View, canvas: [2]f32) {
    c_aspect := canvas.x/canvas.y
    s_aspect := view.screen.x/view.screen.y
    if c_aspect < s_aspect {
        //fit width
        view.scale = view.screen.y/canvas.y
    }
    else {
        //fit height
        view.scale = view.screen.x/canvas.x
    }
    view_center(view, canvas)
}