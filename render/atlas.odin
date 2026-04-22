package render

import sdl "vendor:sdl3"


Grid_Atlas :: struct {
    texture: ^sdl.GPUTexture,
    tex_w, tex_h: uint,
    count_w, count_h: uint,
    step_w, step_h: f32
}

Texture_Tile :: struct {
    texture: ^sdl.GPUTexture,
    rect: Rect
}

create_atlas :: proc(texture: ^sdl.GPUTexture, format: sdl.GPUTextureCreateInfo, count_w, count_h: uint) -> Grid_Atlas {
    w: f32 = f32(format.width)
    h: f32 = f32(format.height)
    return {
        texture = texture,
        count_w = count_w,
        count_h = count_h,
        step_w = 1/f32(count_w),
        step_h = 1/f32(count_h),
        tex_w = uint(format.width),
        tex_h = uint(format.height)
    }
}

fetch_tile :: proc(atlas: Grid_Atlas, x, y: uint) -> Texture_Tile {
    if (x < atlas.count_w && y < atlas.count_h) {
        return {
            texture = atlas.texture,
            rect = {pos = {f32(x)*atlas.step_w, f32(y)*atlas.step_h}, size = {atlas.step_w, atlas.step_h}}
        }
    }
    else {
        return {}
    }
}