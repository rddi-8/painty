package main

c_u8_f32 :: proc(color: [4]u8) -> [4]f32 {
    f_col: [4]f32
    f_col.r = f32(color.r) / 255.0
    f_col.g = f32(color.g) / 255.0
    f_col.b = f32(color.b) / 255.0
    f_col.a = f32(color.a) / 255.0
    return f_col
}

c_f32_u8 :: proc(color: [4]f32) -> [4]u8 {
    u_col: [4]u8
    u_col.r = u8(color.r * 255)
    u_col.g = u8(color.g * 255)
    u_col.b = u8(color.b * 255)
    u_col.a = u8(color.a * 255)
    return u_col
}

c_f16_u8 :: proc(color: [4]f16) -> [4]u8 {
    u_col: [4]u8
    u_col.r = u8(color.r * 255)
    u_col.g = u8(color.g * 255)
    u_col.b = u8(color.b * 255)
    u_col.a = u8(color.a * 255)
    return u_col
}