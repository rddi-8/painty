package math2

import "core:math"

polar_to_cart :: proc "contextless" (angle, l: f32) -> [2]f32 {
    return { l * math.cos(angle), l * math.sin(angle)}
}

cart_to_polar :: proc "contextless" (pos: [2]f32) -> (angle,l: f32) {
    angle = math.atan2(pos.y, pos.x)
    l = math.sqrt(pos.x*pos.x + pos.y*pos.y)
    return
}