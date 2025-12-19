package main

import "core:mem"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:c"
import sdl "vendor:sdl3"
import sdlt "vendor:sdl3/ttf"
import sdli "vendor:sdl3/image"
import "vendor:microui"


import "lcms"

gFramebuffer: ^int
SDL_Window: ^sdl.Window
SDL_Renderer: ^sdl.Renderer
SDL_Texture: ^sdl.Texture
gDone: int
WINDOW_WIDTH : c.int : 2200
WINDOW_HEIGHT : c.int : 1300
last_ticks: u64
brush_avg_sum: u64
avg_count: u64
avg_dab_time: f64

slider_red: microui.Real = 100
slider_green: microui.Real = 100
slider_blue: microui.Real = 100
slider_alpha: microui.Real = 100
slider_opacity: microui.Real = 1
pressure_opacity: microui.Real = 1

slider_size: microui.Real = 64
slider_size2: microui.Real = 64
BRUSH_W: i32 = 64
BRUSH_H: i32 = 64

ui_window_rect: sdl.Rect
redraw_brush: bool = false
update_rect: sdl.Rect
commit_stroke: bool = false

lastpos: [2]f32
mousepos: [2]f32
lastpress: f32
currpress: f32

update_window: struct {
    x,y,w,h: int
}

use_icc: bool = false
use_opacity: bool = false
flow_pressure: bool = false

save_img: bool = false

update :: proc() -> bool {
    event: sdl.Event
    if (sdl.PollEvent(&event)) {
        if (event.type == sdl.EventType.QUIT) {
            return false
        }
        if (event.type == sdl.EventType.KEY_UP && event.key.key == sdl.K_ESCAPE) {
            return false
        }
    }

    pix: ^rawptr
    pitch: int
    return true
}

print_err :: proc() {
    fmt.printfln("SDL Error: {}", sdl.GetError())
}

mu_context: ^microui.Context
ui_font: ^sdlt.Font

mu_text_height :: proc(font: microui.Font) -> i32 {
    return i32(sdlt.GetFontSize(ui_font))
}
mu_text_width :: proc(font: microui.Font, str: string) -> i32 {
    text := sdlt.CreateText(nil, ui_font, fmt.ctprint(str), 0)
    if (text == nil) do print_err()

    w: i32 = 12
    text_size := sdlt.GetTextSize(text, &w, nil)
    sdlt.DestroyText(text)
    return w
}
mu_draw_rect :: proc(rect: microui.Rect, color: microui.Color, surface: ^sdl.Surface) {
    sdl_rect: sdl.Rect
    sdl_rect.h = rect.h
    sdl_rect.w = rect.w
    sdl_rect.x = rect.x
    sdl_rect.y = rect.y
    sdl_color := sdl.MapRGBA(sdl.GetPixelFormatDetails(surface.format), nil, color.r, color.g, color.b, color.a)
    sdl.FillSurfaceRect(surface, &sdl_rect, sdl_color)
}
mu_draw_text :: proc(str: string, pos: microui.Vec2, color: microui.Color, surface: ^sdl.Surface)
{
    // sdl_color := sdl.MapRGBA(sdl.GetPixelFormatDetails(surface.format), nil, color.r, color.g, color.b, color.a)
    sdl_color: sdl.Color
    sdl_color.r = color.r
    sdl_color.g = color.g
    sdl_color.b = color.b
    sdl_color.a = color.a
    text := sdlt.RenderText_Solid(ui_font, fmt.ctprint(str), 0, sdl_color)
    sdl_rect: sdl.Rect = {x = pos.x, y = pos.y, w = text.w, h = text.h}
    sdl.BlitSurface(text, nil, surface, &sdl_rect)
    sdl.DestroySurface(text)
}
mu_clip :: proc(rect: microui.Rect, surface: ^sdl.Surface) {
    sdl_rect: sdl.Rect = { x = rect.x, y = rect.y, w = rect.w, h = rect.h}
    sdl.SetSurfaceClipRect(surface, &sdl_rect)
}

log_lcms_error :: proc(ctx: lcms.Context, error_code: lcms.ErrorCode, text: cstring) {
    fmt.printfln("LCMS ERROR: %s : %s", error_code, text)
}

map_xy :: proc(surface: ^sdl.Surface, x: int, y: int) -> int {
    return x + y * int(surface.w)
}

c_to_f :: proc(color: [4]u8) -> [4]f32 {
    f_col: [4]f32
    f_col.r = f32(color.r) / 255.0
    f_col.g = f32(color.g) / 255.0
    f_col.b = f32(color.b) / 255.0
    f_col.a = f32(color.a) / 255.0
    return f_col
}

f_to_c :: proc(color: [4]f32) -> [4]u8 {
    u_col: [4]u8
    u_col.r = u8(color.r * 255)
    u_col.g = u8(color.g * 255)
    u_col.b = u8(color.b * 255)
    u_col.a = u8(color.a * 255)
    return u_col
}


custom_blend :: proc(src: ^sdl.Surface, dest: ^sdl.Surface, x: int, y: int, pen_pressure: f32) #no_bounds_check #no_type_assert {
    src_cv := ([^][4]f16)(src.pixels)
    dst_cv := ([^][4]f16)(dest.pixels)

    // sdl.LockSurface(src)
    // sdl.LockSurface(dest)
    
    opacity: f16 = f16(clamp(pen_pressure*2 * slider_opacity, 0, 1))
    cxl,cxr,cyu,cyb: int // clipping vars
    cxl = max(0, -x)
    cyu = max(0, -y)
    cxr = min(int(src.w), int(dest.w) - x)
    cyb = min(int(src.h), int(dest.h) - y)

    // fmt.printfln("cxl: {}, cyu: {}, cxr: {}, cyb: {}", cxl, cyu, cxr, cyb)

    for ys in cyu..<cyb {
        for xs in cxl..<cxr {
            // if xs + x < 0 || ys + y < 0 do continue
            // if xs + x + 1 > int(dest.w) do continue
            // if ys + y + 1 > int(dest.h) do continue
            src_c := src_cv[map_xy(src, xs, ys)]
            dst_c := dst_cv[map_xy(dest, xs + x, ys + y)]
            // fin_c: [4]f16

            fin_c := src_c
            // ccc := src_c.r * (f16(xs) / f16(src.w))
            // fin_c.r = ccc
            // fin_c.g = ccc
            // fin_c.b = ccc



            // fin_c.rgb = (src_c.rgb * src_c.a)
            // fin_c.a = src_c.a + (dst_c.a * (1 - src_c.a))
            fin_c.a = math.max(f16(opacity)*src_c.a, dst_c.a)
            // fin_c.a = f16(slider_opacity)
            dst_cv[map_xy(dest, xs + x, ys + y)] = fin_c

        }
    }

    // sdl.UnlockSurface(src)
    // sdl.UnlockSurface(dest)
}


custom_blend_basic :: proc(src: ^sdl.Surface, dest: ^sdl.Surface, x: int, y: int) {
    src_cv := ([^][4]f16)(src.pixels)
    dst_cv := ([^][4]f16)(dest.pixels)

    sdl.LockSurface(src)
    sdl.LockSurface(dest)
    
    opacity: f16 = f16(clamp(slider_opacity*1.6, 0, 1))
    invpow: [3]f16 = {1/2.2, 1/2.2, 1/2.2}

    for ys in 0..<int(src.h) {
        for xs in 0..<int(src.w) {
            // if xs + x < 0 || ys + y < 0 do continue
            // if xs + x + 1 > int(dest.w) do continue
            // if ys + y + 1 > int(dest.h) do continue
            src_c := src_cv[map_xy(src, xs, ys)]
            dst_c := dst_cv[map_xy(dest, xs + x, ys + y)]
            fin_c: [4]f16


            // src_c.rgb *= src_c.a
            fin_c.rgb = src_c.rgb * src_c.a + dst_c.rgb * (1 - src_c.a)
            
            // fin_c.rgb = (src_c.rgb * src_c.a)
            fin_c.a = src_c.a + dst_c.a * (1 - src_c.a)
            

            // fin_c.a = 1
            // fin_c.a = math.max(opacity*src_c.a, dst_c.a)
            // fin_c.a = f16(slider_opacity)
            dst_cv[map_xy(dest, xs + x, ys + y)] = fin_c

        }
    }

    sdl.UnlockSurface(src)
    sdl.UnlockSurface(dest)
}

custom_blend_basic_premult :: proc(src: ^sdl.Surface, dest: ^sdl.Surface, x: int, y: int) {
    src_cv := ([^][4]f16)(src.pixels)
    dst_cv := ([^][4]f16)(dest.pixels)

    sdl.LockSurface(src)
    sdl.LockSurface(dest)
    
    opacity: f16 = f16(clamp(slider_opacity*1.6, 0, 1))
    invpow: [3]f16 = {2.2, 2.2, 2.2}

    for ys in 0..<int(src.h) {
        for xs in 0..<int(src.w) {
            // if xs + x < 0 || ys + y < 0 do continue
            // if xs + x + 1 > int(dest.w) do continue
            // if ys + y + 1 > int(dest.h) do continue
            src_c := src_cv[map_xy(src, xs, ys)]
            dst_c := dst_cv[map_xy(dest, xs + x, ys + y)]
            fin_c: [4]f16


            // src_c.rgb = src_c.rgb * (1/src_c.a)
            // fin_c.rgb = src_c.rgb * src_c.a
            
            // // fin_c.rgb = (src_c.rgb * src_c.a)
            // fin_c.a = src_c.a + dst_c.a * (1 - src_c.a)
            
            // src_c.rgb = linalg.pow(src_c.rgb, invpow)
            // fin_c.a = 1
            // fin_c.a = math.max(opacity*src_c.a, dst_c.a)
            // fin_c.a = f16(slider_opacity)
            dst_cv[map_xy(dest, xs + x, ys + y)] = src_c

        }
    }

    sdl.UnlockSurface(src)
    sdl.UnlockSurface(dest)
}

print_tex_prop :: proc(tex: ^sdl.Texture, name: string) {
    props := sdl.GetTextureProperties(tex)
    color_space := sdl.GetNumberProperty(props, sdl.PROP_TEXTURE_COLORSPACE_NUMBER, -88)
    access := sdl.GetNumberProperty(props, sdl.PROP_TEXTURE_ACCESS_NUMBER, -88)
    fmt.printfln("{} color_space: {}", name, sdl.Colorspace(color_space))
    fmt.printfln("{} access: {}", name, sdl.TextureAccess(access))
}

update_texture :: proc(source: ^sdl.Surface, tex: ^sdl.Texture, x,y,w,h: int) {
    if w == 0 || h == 0 do return
    tex_px: rawptr
    tex_pitch: i32
    rect: sdl.Rect = {i32(x),i32(y),i32(w),i32(h)}
    // fmt.println(rect)
    // print_tex_prop(tex, "copy source")
    if !sdl.LockTexture(tex, &rect , &tex_px, &tex_pitch) do print_err()
    // fmt.printfln("tex: pitch {}", tex_pitch)
    if !sdl.LockSurface(source) do print_err()
    // fmt.printfln("src: {} tex {}", source.pitch, tex_pitch)
    // assert(source.pitch == tex_pitch)

    for i in 0..<h {

        mem.copy_non_overlapping(rawptr(uintptr(tex_px) + uintptr(i)*uintptr(tex_pitch)), rawptr(uintptr(source.pixels) + uintptr(y*int(source.pitch) + x*8 + i*int(source.pitch))) , w*8)

    }
    sdl.UnlockTexture(tex)
    sdl.UnlockSurface(source)
}

main :: proc() {

    col_lane :: #simd [32]f16

    cols: col_lane = {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16}
    c1: col_lane = {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1}

    rrr := cols + c1
    fmt.println(rrr)

    lastpos.x = -100000
    fmt.println("hmmm")
    fmt.printfln("lcms_ver: ", lcms.GetEncodedCMMversion())
    lcms.SetLogErrorHandler(log_lcms_error)

    fmt.println("Loading srgb icm")
    // in_profile := lcms.OpenProfileFromFile("sRGB.icm", "r")
    in_profile := lcms.OpenProfileFromFile("sRGB.icm", "r")
    fmt.println("Loading dest icm")  

    out_profile := lcms.OpenProfileFromFile("profile.icm", "r")
    fmt.println("creating transform")
    h_transform := lcms.CreateTransform(
        in_profile,
        lcms.get_format_bgra8(),
        out_profile,
        lcms.get_format_bgra8(),
        .PERCEPTUAL,
        u32(lcms.dwFlags.COPY_ALPHA)
    )

    opacity_blend := sdl.ComposeCustomBlendMode(.SRC_ALPHA, .ONE_MINUS_SRC_ALPHA, .ADD, .SRC_ALPHA, .ZERO, .SUBTRACT)
    
    mu_context = new(microui.Context)
    microui.init(mu_context)
    mu_context.text_height = mu_text_height
    mu_context.text_width = mu_text_width
    
    if !sdl.Init({.VIDEO}) do fmt.printfln("Opps {}", sdl.GetError())

    update_rect = { x = 0, y = 0, w = 0, h = 0}
    
    if !sdlt.Init() do fmt.printfln("Opps {}", sdl.GetError())
    
    ui_font = sdlt.OpenFont("DroidSans.ttf", 12)
    if (ui_font == nil) do print_err()
    
    
    // window := sdl.CreateWindow("SDL Appy", WINDOW_WIDTH, WINDOW_HEIGHT, {.RESIZABLE})
    window: ^sdl.Window
    renderer: ^sdl.Renderer
    window = sdl.CreateWindow("Painty", WINDOW_WIDTH, WINDOW_HEIGHT, {})
    
    rend_prop := sdl.CreateProperties()
    sdl.SetNumberProperty(rend_prop, sdl.PROP_RENDERER_CREATE_OUTPUT_COLORSPACE_NUMBER, i64(sdl.Colorspace.SRGB_LINEAR))
    sdl.SetPointerProperty(rend_prop, sdl.PROP_RENDERER_CREATE_WINDOW_POINTER, window)
    renderer = sdl.CreateRendererWithProperties(rend_prop)
    
    surface := sdl.GetWindowSurface(window)

    tex_properties := sdl.CreateProperties()
    if tex_properties == 0 do print_err()
    if !sdl.SetNumberProperty(tex_properties, sdl.PROP_TEXTURE_CREATE_COLORSPACE_NUMBER, i64(sdl.Colorspace.SRGB_LINEAR)) do print_err()
    if !sdl.SetNumberProperty(tex_properties, sdl.PROP_TEXTURE_CREATE_ACCESS_NUMBER, i64(sdl.TextureAccess.STREAMING)) do print_err()
    if !sdl.SetNumberProperty(tex_properties, sdl.PROP_TEXTURE_CREATE_FORMAT_NUMBER, i64(sdl.PixelFormat.RGBA64_FLOAT)) do print_err()
    if !sdl.SetNumberProperty(tex_properties, sdl.PROP_TEXTURE_CREATE_WIDTH_NUMBER, i64(WINDOW_WIDTH)) do print_err()
    if !sdl.SetNumberProperty(tex_properties, sdl.PROP_TEXTURE_CREATE_HEIGHT_NUMBER, i64(WINDOW_HEIGHT)) do print_err()

    texs_properties := sdl.CreateProperties()
    if tex_properties == 0 do print_err()
    if !sdl.SetNumberProperty(texs_properties, sdl.PROP_TEXTURE_CREATE_COLORSPACE_NUMBER, i64(sdl.Colorspace.SRGB)) do print_err()
    if !sdl.SetNumberProperty(texs_properties, sdl.PROP_TEXTURE_CREATE_ACCESS_NUMBER, i64(sdl.TextureAccess.STREAMING)) do print_err()
    if !sdl.SetNumberProperty(texs_properties, sdl.PROP_TEXTURE_CREATE_FORMAT_NUMBER, i64(sdl.PixelFormat.XRGB8888)) do print_err()
    if !sdl.SetNumberProperty(texs_properties, sdl.PROP_TEXTURE_CREATE_WIDTH_NUMBER, i64(WINDOW_WIDTH)) do print_err()
    if !sdl.SetNumberProperty(texs_properties, sdl.PROP_TEXTURE_CREATE_HEIGHT_NUMBER, i64(WINDOW_HEIGHT)) do print_err()

    rendererr := sdl.GetRenderer(window)
    if rendererr == nil do print_err()
    canvas_tex := sdl.CreateTextureWithProperties(renderer, tex_properties)
    if canvas_tex == nil do print_err()
    stroke_tex := sdl.CreateTextureWithProperties(renderer, tex_properties)
    if stroke_tex == nil do print_err()
    surface_tex := sdl.CreateTextureWithProperties(renderer, texs_properties)
    if surface_tex == nil do print_err()

    print_tex_prop(canvas_tex, "canvas_tex")
    print_tex_prop(stroke_tex, "stroke_tex")
    print_tex_prop(surface_tex, "surface_tex")
    
    
    surface_cs := sdl.GetSurfaceColorspace(surface)
    fmt.printfln("c: {}", surface_cs)
    
    canvas_layer := sdl.CreateSurface(WINDOW_WIDTH, WINDOW_HEIGHT, .RGBA64_FLOAT )
    sdl.ClearSurface(canvas_layer, 0, 0, 0, 1)
    stroke_layer := sdl.CreateSurface(WINDOW_WIDTH, WINDOW_HEIGHT, .RGBA64_FLOAT )
    stroke_layer_premult := sdl.CreateSurface(WINDOW_WIDTH, WINDOW_HEIGHT, .RGBA64_FLOAT )
    fmt.printfln("canvas color: {}", sdl.GetSurfaceColorspace(canvas_layer))

    ui_layer := sdl.CreateSurface(WINDOW_WIDTH, WINDOW_HEIGHT, .RGBA32)
    ui_tex := sdl.CreateTextureFromSurface(renderer, ui_layer)  


    formatInfo := sdl.GetPixelFormatDetails(surface.format)
    fmt.printfln("pixel size: {} bytes {} bits", formatInfo.bytes_per_pixel, formatInfo.bits_per_pixel)
    red := sdl.MapRGB(formatInfo, nil, 210, 34, 12)
    canvas: [^]sdl.Uint32 = ([^]sdl.Uint32)(surface.pixels)


    brush := sdl.CreateSurface(BRUSH_W, BRUSH_H, .RGBA32)
    if (brush == nil) {
        print_err()
    }
    fmt.printfln("MUST_LOCK brush {}", sdl.MUSTLOCK(brush))
    fmt.printfln("MUST_LOCK window {}", sdl.MUSTLOCK(surface))
    

    // brushFmt := sdl.GetPixelFormatDetails(brush.format)
    // brushCol := sdl.MapRGBA(brushFmt, nil, 100, 100, 100, 100)
    // brushBg := sdl.MapRGBA(brushFmt, nil, 100, 100, 100, 0)

    // if(!sdl.LockSurface(brush)) do fmt.printfln("Error: {}", sdl.GetError())
    // brushCanvas: [^]sdl.Uint32 = ([^]sdl.Uint32)(brush.pixels)
    // for y in 0..<BRUSH_H {
    //     for x in 0..<BRUSH_W {
    //         if ( ((x - BRUSH_W/2)*(x - BRUSH_W/2) + (y - BRUSH_H/2)*(y - BRUSH_H/2)) <= (BRUSH_H/2)*(BRUSH_W/2)) {
    //             pixelOffset := brush.pitch / 4 * y + x
    //             brushCanvas[pixelOffset] = brushCol
    //         }
    //         else {
    //             pixelOffset := brush.pitch / 4 * y + x
    //             brushCanvas[pixelOffset] = brushBg
    //         }
    //     }
    // }
    // sdl.UnlockSurface(brush)

    quit: bool = false;

    draw_pixel :: proc(x: f32, y: f32, window: ^sdl.Window, color: sdl.Uint32) {
        cx: i32 = i32(x)
        cy: i32 = i32(y)
        surface := sdl.GetWindowSurface(window)
        canvas: [^]sdl.Uint32 = ([^]sdl.Uint32)(surface.pixels)
        if (cx >= 0 && cx < surface.w && cy >= 0 && cy < surface.h) {
            sdl.LockSurface(surface)
            canvas[cx + cy*surface.w] = color
            sdl.UnlockSurface(surface)
            sdl.UpdateWindowSurface(window)
        }
        else {
            fmt.println("Drawing outside canvas")
        }
    }

    redraw_brush = true

    main_loop: for {
        surface = sdl.GetWindowSurface(window)
        update_rect = { x = 0, y = 0, w = 0, h = 0}

        frame_time: u64 = sdl.GetTicksNS() - last_ticks
        last_ticks = sdl.GetTicksNS()
        event: sdl.Event


        if redraw_brush {
            // fmt.println("redraw brush")
            brushFmt := sdl.GetPixelFormatDetails(brush.format)
            brushCol: [4]f16 = {f16(slider_red / 255.0), f16(slider_green / 255.0), f16(slider_blue / 255.0), f16(slider_alpha / 255.0)}
            brushBg: [4]f16 = {f16(slider_red / 255.0), f16(slider_green / 255.0), f16(slider_blue / 255.0), 0}
            brushCol.r = math.pow(brushCol.r, 2.2)
            brushCol.g = math.pow(brushCol.g, 2.2)
            brushCol.b = math.pow(brushCol.b, 2.2)
            brushBg.r = math.pow(brushBg.r, 2.2)
            brushBg.g = math.pow(brushBg.g, 2.2)
            brushBg.b = math.pow(brushBg.b, 2.2)
            sdl.DestroySurface(brush)
            brush = sdl.CreateSurface(BRUSH_W, BRUSH_H, .RGBA64_FLOAT)
            sdl.ClearSurface(brush, 0, 0, 0, 0)
            
            brushCanvas: [^][4]f16 = ([^][4]f16)(brush.pixels)
            for y in 0..<BRUSH_H {
                for x in 0..<BRUSH_W {
                    if ( ((x - BRUSH_W/2)*(x - BRUSH_W/2) + (y - BRUSH_H/2)*(y - BRUSH_H/2)) <= (BRUSH_H/2)*(BRUSH_W/2)) {
                        brushCanvas[map_xy(brush, int(x), int(y))] = brushCol
                    }
                    else {
                        brushCanvas[map_xy(brush, int(x), int(y))] = brushBg
                    }
                }
            }

            redraw_brush = false;
        }


        destRect: sdl.Rect
        for sdl.PollEvent(&event) {
            #partial switch event.type {
                case .QUIT:
                    break main_loop
                case .KEY_DOWN:
                    if event.key.scancode == .ESCAPE do break main_loop
                    if event.key.scancode == .LALT {
                        r, g, b, a: u8
                        pick_col := sdl.ReadSurfacePixel(canvas_layer, i32(mousepos.x), i32(mousepos.y), &r, &g, &b, &a)
                        slider_red = f32(r)
                        slider_green = f32(g)
                        slider_blue = f32(b)
                        // slider_alpha = f32(a)
                        redraw_brush = true
                    }
                case .MOUSE_BUTTON_DOWN:
                    mu_mouse: microui.Mouse
                    mu_mouse = microui.Mouse.LEFT
                    microui.input_mouse_down(mu_context, i32(event.motion.x), i32(event.motion.y), mu_mouse)
                    r,g,b,a :sdl.Uint8

                    if event.button.button == 3 {
                        r, g, b, a: u8
                        pick_col := sdl.ReadSurfacePixel(canvas_layer, i32(event.motion.x), i32(event.motion.y), &r, &g, &b, &a)
                        slider_red = f32(r)
                        slider_green = f32(g)
                        slider_blue = f32(b)
                        // slider_alpha = f32(a)
                        redraw_brush = true
                    }
                case .MOUSE_BUTTON_UP:
                    mu_mouse: microui.Mouse
                    mu_mouse = microui.Mouse.LEFT
                    microui.input_mouse_up(mu_context, i32(event.motion.x), i32(event.motion.y), mu_mouse)

                    commit_stroke = true
                    lastpos.x = -100000
                    avg_count = 0
                case .MOUSE_MOTION:
                    microui.input_mouse_move(mu_context, i32(event.motion.x), i32(event.motion.y))
                    mousepos = {event.motion.x, event.motion.y}
            
                    if event.motion.state == {.LEFT} {
                        // fmt.printfln("draw px {} : {}", event.motion.x, event.motion.y)
                        // draw_pixel(event.motion.x, event.motion.y, window, red)
                        if (ui_window_rect.x < i32(event.motion.x) && i32(event.motion.x) < ui_window_rect.x + ui_window_rect.w &&
                            ui_window_rect.y < i32(event.motion.y) && i32(event.motion.y) < ui_window_rect.y + ui_window_rect.h) {

                        }
                        else
                        {
                            destRect.h = BRUSH_H
                            destRect.w = BRUSH_W
                            destRect.x = i32(event.motion.x) - BRUSH_W/2
                            destRect.y = i32(event.motion.y) - BRUSH_H/2
                            
                            // if flow_pressure do sdl.SetSurfaceAlphaMod(brush, u8(slider_opacity * 255))
                            
                            // sdl.SetSurfaceBlendMode(brush, opacity_blend)

                            // sdl.SetSurfaceBlendMode(canvas_layer, opacity_blend)

                            curpos: [2]f32 = {event.motion.x, event.motion.y}
                            delta := curpos - lastpos
                            dist: f32 = math.sqrt(delta.x*delta.x + delta.y*delta.y)
                            step: f32 = max(f32(BRUSH_H/64), 1)
                            dir := delta/dist

                            pressure: f32 = currpress
                            deltaPress := currpress - lastpress

                            sdl.LockSurface(brush)
                            sdl.LockSurface(stroke_layer)

                            if lastpos.x >= 0 {
                                for t: f32; t < dist; t = t + step {
                                    pos: [2]f32 = lastpos + dir * t
                                    last_dab_time := sdl.GetTicksNS()

                                    press_interp: f32 = lastpress + deltaPress * (t/dist)
                                    
                                    if use_opacity do custom_blend(brush, stroke_layer, int(pos.x) - int(BRUSH_W/2), int(pos.y) - int(BRUSH_H/2), press_interp)
                                    // else do custom_blend_basic(brush, stroke_layer, int(pos.x) - int(BRUSH_W/2), int(pos.y) - int(BRUSH_H/2))
                                    else do sdl.BlitSurface(brush, nil, stroke_layer, &destRect)
                                    ticks: u64 = sdl.GetTicksNS() - last_dab_time
                                    avg_count += 1
                                    if avg_count == 1 {brush_avg_sum = 0}
                                    brush_avg_sum += ticks
                                    avg_dab_time = f64(brush_avg_sum)/f64(avg_count)
                                } 
                            }
                            else {
                                last_dab_time := sdl.GetTicksNS()

                                if use_opacity do custom_blend(brush, stroke_layer, int(curpos.x) - int(BRUSH_W/2), int(curpos.y) - int(BRUSH_H/2), currpress)
                                // else do custom_blend_basic(brush, stroke_layer, int(curpos.x) - int(BRUSH_W/2), int(curpos.y) - int(BRUSH_H/2))
                                else do sdl.BlitSurface(brush, nil, stroke_layer, &destRect)

                                ticks: u64 = sdl.GetTicksNS() - last_dab_time
                                avg_count += 1
                                if avg_count == 1 {brush_avg_sum = 0}
                                brush_avg_sum += ticks
                                avg_dab_time = f64(brush_avg_sum)/f64(avg_count)
                            }

                            sdl.UnlockSurface(brush)
                            sdl.UnlockSurface(stroke_layer)

                            
                            lastpos = curpos
                            lastpress = currpress
                            update_rect = destRect

                            update_window.x = int(destRect.x)
                            update_window.y = int(destRect.y)
                            update_window.w = int(destRect.w)
                            update_window.h = int(destRect.h)

                        }
                    }
                    if event.motion.state == {.RIGHT} {
                        r, g, b, a: u8
                        pick_col := sdl.ReadSurfacePixel(canvas_layer, i32(event.motion.x), i32(event.motion.y), &r, &g, &b, &a)
                        slider_red = f32(r)
                        slider_green = f32(g)
                        slider_blue = f32(b)
                        // slider_alpha = f32(a)
                        redraw_brush = true
                    }
                case .PEN_AXIS:
                    if event.paxis.axis == .PRESSURE {
                        pressure_opacity = event.paxis.value
                        currpress = event.paxis.value
                    }
                case .PEN_UP:
                    commit_stroke = true
                    lastpos.x = -100000
                    avg_count = 0
            }

            
        }

        microui.begin(mu_context)

        microui.begin_window(mu_context, "Helloooo", {10, 10, 320, 530})

        res := microui.button(mu_context, "Button")
        res_toggle := microui.checkbox(mu_context, "use ICC", &use_icc)
        if (.SUBMIT in res) do save_img = true
        microui.label(mu_context, fmt.aprintf("time: %.2f ms", f32(frame_time)/1000000.0))
        microui.label(mu_context, fmt.aprintf("dab: %.2f µs", avg_dab_time/1000.0))
        microui.layout_row(mu_context, {300}, 26)
        n_rect := microui.layout_next(mu_context)
        microui.draw_rect(mu_context, n_rect, {u8(slider_red), u8(slider_green), u8(slider_blue), 255})
        res_r := microui.slider(mu_context, &slider_red, 0, 255)
        res_g := microui.slider(mu_context, &slider_green, 0, 255)
        res_b := microui.slider(mu_context, &slider_blue, 0, 255)
        microui.label(mu_context, "flow:")
        microui.checkbox(mu_context, "flow P", &flow_pressure)
        res_a := microui.slider(mu_context, &slider_alpha, 0, 255)
        microui.label(mu_context, "opacity:")
        microui.checkbox(mu_context, "opacity p", &use_opacity)
        res_o := microui.slider(mu_context, &slider_opacity, 0, 1)
        microui.label(mu_context, "size:")
        res_size := microui.slider(mu_context, &slider_size, 1, 400)
        if slider_size > 24 do slider_size2 = 24
        if slider_size <= 24 do slider_size2 = slider_size
        res_size2 := microui.slider(mu_context, &slider_size2, 1, 24)
        if slider_size2 < 24 do slider_size = slider_size2

        if (.CHANGE in res_size || .CHANGE in res_size2) {
            BRUSH_H = i32(slider_size)
            BRUSH_W = i32(slider_size)
            redraw_brush = true
        }

        if ((.CHANGE in res_r) || (.CHANGE in res_g) || (.CHANGE in res_b) || (.CHANGE in res_a)) {
            redraw_brush = true
        }

        ui_window := microui.get_current_container(mu_context)
        microui.end_window(mu_context)

        

        // microui.begin_window(mu_context, "Hmmm", {10, 10, 200, 400})
        // res1 := microui.button(mu_context, "Button 1")
        // if (.SUBMIT in res1) do fmt.println("button 1 pressy")
        // res2 := microui.button(mu_context, "Button 2")
        // if (.SUBMIT in res2) do fmt.println("button 2 pressy")
        // microui.end_window(mu_context)

        microui.end(mu_context)

        
        // if(!sdl.LockSurface(brush)) do fmt.printfln("Error: {}", sdl.GetError())
        

        sdl.ClearSurface(ui_layer, 0, 0, 0, 0)
        mu_command: ^microui.Command
        for microui.next_command(mu_context, &mu_command) {
            #partial switch cmd in mu_command.variant {
                case ^microui.Command_Rect:
                    mu_draw_rect(cmd.rect, cmd.color, ui_layer)
                case ^microui.Command_Text:
                    mu_draw_text(cmd.str, cmd.pos, cmd.color, ui_layer)
                    
            }
        }
        if true {
            // sdl.ClearSurface(surface, 0, 0, 0, 1)
            // sdl.BlitSurface(canvas_layer, nil, surface, nil)
        }
        else {
        //    sdl.BlitSurface(canvas_layer, &update_rect, surface, &update_rect)
        }
        ui_window_rect = { w = ui_window.rect.w, h = ui_window.rect.h, x = ui_window.rect.x, y = ui_window.rect.y}
        if (save_img) {
            sdli.SavePNG(canvas_layer, "img.png")
            sdli.SavePNG(surface, "img_bg.png")
            save_img = false
        }
        // sdl.BlitSurface(ui_layer, &ui_window_rect, surface, &ui_window_rect)

        if commit_stroke {
            
            // sdl.BlitSurface(stroke_layer, nil, canvas_layer, nil)
            custom_blend_basic(stroke_layer, canvas_layer, 0, 0)

            // custom_blend_basic(stroke_layer, canvas_layer, 0, 0)
            sdl.ClearSurface(stroke_layer, 0, 0, 0, 0)
            commit_stroke = false
        }
        
        
        canvas_tex_pixels: rawptr
        ctex_pitch: c.int
        // if !sdl.LockTexture(canvas_tex, nil, &canvas_tex_pixels, &ctex_pitch) do print_err()
        // pixls: [^][4]f16 = ([^][4]f16)(canvas_tex_pixels)
        // clor: [4]f16 = { 1, 1, 1, 1}
        // for i in 0..<100 {
        //     pixls[i] = clor
        // }
        // sdl.UnlockTexture(canvas_tex)
        
        sdl.RenderClear(renderer)
        // sdl.UpdateTexture(canvas_tex, nil, canvas_layer.pixels, canvas_layer.pitch)
        update_texture(canvas_layer, canvas_tex, update_window.x, update_window.y, update_window.w, update_window.h)
        sdl.RenderTexture(renderer, canvas_tex, nil, nil)
        // sdl.SetRenderDrawBlendMode(renderer, {.BLEND})
        // sdl.SetSurfaceColorspace(stroke_layer, .RGB_DEFAULT)
        custom_blend_basic_premult(stroke_layer, stroke_layer_premult, 0, 0)
        // sdl.UpdateTexture(stroke_tex, nil, stroke_layer_premult.pixels, stroke_layer_premult.pitch)
        // update_texture(stroke_layer_premult, stroke_tex, update_window.x, update_window.y, update_window.w, update_window.h)
        update_texture(stroke_layer_premult, stroke_tex, update_window.x, update_window.y, update_window.w, update_window.h)

        sdl.RenderTexture(renderer, stroke_tex, nil, nil)
        if use_icc {
            sdl.RenderClear(renderer)
            sdl.SetSurfaceColorspace(surface, .RGB_DEFAULT)
            sdl.ClearSurface(surface, 0, 0, 0, 1)
            sdl.BlitSurface(canvas_layer, nil, surface, nil)
            lcms.DoTransform(h_transform, surface.pixels, surface.pixels, u32(surface.h * surface.w))
            sdl.UpdateTexture(surface_tex, nil, surface.pixels, surface.pitch)
            sdl.RenderTexture(renderer, surface_tex, nil, nil)
        }
        sdl.UpdateTexture(ui_tex, nil, ui_layer.pixels, ui_layer.pitch)
        // update_texture(ui_layer, ui_tex)
        sdl.RenderTexture(renderer, ui_tex, nil, nil)
        
        
        sdl.RenderPresent(renderer)
        
        if use_icc {
            // surface_copy := sdl.DuplicateSurface(surface)
            // sdl.LockSurface(surface)
            lcms.DoTransform(h_transform, surface.pixels, surface.pixels, u32(surface.h * surface.w))
            // sdl.UnlockSurface(surface)
            // sdl.SetSurfaceColorspace(surface, .RGB_DEFAULT)
            // sdl.BlitSurface(surface_copy, nil, surface, nil)
            // sdl.DestroySurface(surface_copy)
        
        }

        sdl.UpdateWindowSurface(window)
    }
    
    sdl.DestroyWindow(window)
    sdl.Quit()
}