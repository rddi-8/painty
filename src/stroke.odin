package main

import "core:fmt"
import "core:math"
import "canvas"

Stroke_Point :: struct {
    canvas_pos: [2]f32,
    size: int,
    alpha: f32,
    time: u64,
    color: [4]f32,
}

Stroke_Buffer :: struct {
    capacity: int,
    length: int,
    head: int,
    buffer: #soa[]Stroke_Point
}

sb_make :: proc(capacity: int) -> ^Stroke_Buffer{
    sb := new(Stroke_Buffer)
    sb.buffer = make(#soa[]Stroke_Point, capacity)
    sb.capacity = capacity
    sb.length = 0
    sb.head = capacity - 1
    return sb
}

sb_get :: proc(sb: ^Stroke_Buffer, i: int = 0) ->  (res: Stroke_Point, ok: bool) #optional_ok {
    if sb.length <= i do return {}, false
    elem_index := (sb.head + i) %% sb.capacity
    return sb.buffer[elem_index], true
}

sb_push :: proc(sb: ^Stroke_Buffer, point: Stroke_Point) {
    elem_index := (sb.head - 1) %% sb.capacity
    sb.buffer[elem_index] = point
    sb.head = elem_index
    sb.length = min(sb.length + 1, sb.capacity)
}

sb_clear :: proc(sb: ^Stroke_Buffer) {
    sb.length = 0
    sb.head = sb.capacity - 1
}

stroke_interpolate :: proc(a, b: Stroke_Point, t: f32) -> Stroke_Point {
    return {
        canvas_pos = math.lerp(a.canvas_pos, b.canvas_pos, t),
        size = canvas.lerpi(a.size, b.size, t),
        color = math.lerp(a.color, b.color, t),
        alpha = math.lerp(a.alpha, b.alpha, t),
        time = canvas.lerpi_u64(a.time, b.time, t),
    }
}