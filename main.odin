package main

import "core:fmt"
import "core:math"
import "core:c"
import sdl "vendor:sdl3"
import sdlt "vendor:sdl3/ttf"
import "vendor:microui"

import "lcms"

gFramebuffer: ^int
SDL_Window: ^sdl.Window
SDL_Renderer: ^sdl.Renderer
SDL_Texture: ^sdl.Texture
gDone: int
WINDOW_WIDTH : c.int : 1920 
WINDOW_HEIGHT : c.int : 1080
last_ticks: u64

slider_red: microui.Real = 100
slider_green: microui.Real = 100
slider_blue: microui.Real = 100
slider_alpha: microui.Real = 100

slider_size: microui.Real = 64
BRUSH_W: i32 = 64
BRUSH_H: i32 = 64

redraw_brush: bool = false

use_icc: bool = false

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

main :: proc() {
    fmt.println("hmmm")
    fmt.printfln("lcms_ver: ", lcms.GetEncodedCMMversion())
    lcms.SetLogErrorHandler(log_lcms_error)

    fmt.println("Loading srgb icm")
    // in_profile := lcms.OpenProfileFromFile("sRGB.icm", "r")
    in_profile := lcms.Create_sRGBProfile()
    fmt.println("Loading dest icm")  

    out_profile := lcms.OpenProfileFromFile("profile.icm", "r")
    fmt.println("creating transform")
    h_transform := lcms.CreateTransform(
        in_profile,
        lcms.get_format_rgba8(),
        out_profile,
        lcms.get_format_rgba8(),
        .PERCEPTUAL,
        u32(lcms.dwFlags.BLACKPOINTCOMPENSATION)
    )


    
    mu_context = new(microui.Context)
    microui.init(mu_context)
    mu_context.text_height = mu_text_height
    mu_context.text_width = mu_text_width

    if !sdl.Init({.VIDEO}) do fmt.printfln("Opps {}", sdl.GetError())

    if !sdlt.Init() do fmt.printfln("Opps {}", sdl.GetError())
    
    ui_font = sdlt.OpenFont("DroidSans.ttf", 12)
    if (ui_font == nil) do print_err()

    window := sdl.CreateWindow("SDL Appy", WINDOW_WIDTH, WINDOW_HEIGHT, {.RESIZABLE})
    surface := sdl.GetWindowSurface(window)

    surface_cs := sdl.GetSurfaceColorspace(surface)
    fmt.printfln("c: {}", surface_cs)

    canvas_layer := sdl.CreateSurface(WINDOW_WIDTH, WINDOW_HEIGHT, .RGBA32)
    sdl.SetSurfaceBlendMode(canvas_layer, {.BLEND})
    // sdl.ClearSurface(canvas_layer, 1, 1, 1, 1) 
    ui_layer := sdl.CreateSurface(WINDOW_WIDTH, WINDOW_HEIGHT, .RGBA32)   


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
    

    brushFmt := sdl.GetPixelFormatDetails(brush.format)
    brushCol := sdl.MapRGBA(brushFmt, nil, 100, 100, 100, 100)
    brushBg := sdl.MapRGBA(brushFmt, nil, 100, 100, 100, 0)

    // if(!sdl.LockSurface(brush)) do fmt.printfln("Error: {}", sdl.GetError())
    brushCanvas: [^]sdl.Uint32 = ([^]sdl.Uint32)(brush.pixels)
    for y in 0..<BRUSH_H {
        for x in 0..<BRUSH_W {
            if ( ((x - BRUSH_W/2)*(x - BRUSH_W/2) + (y - BRUSH_H/2)*(y - BRUSH_H/2)) <= (BRUSH_H/2)*(BRUSH_W/2)) {
                pixelOffset := brush.pitch / 4 * y + x
                brushCanvas[pixelOffset] = brushCol
            }
            else {
                pixelOffset := brush.pitch / 4 * y + x
                brushCanvas[pixelOffset] = brushBg
            }
        }
    }
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

    main_loop: for {
        surface = sdl.GetWindowSurface(window)
        frame_time: u64 = sdl.GetTicksNS() - last_ticks
        last_ticks = sdl.GetTicksNS()
        event: sdl.Event


        if redraw_brush {
            // fmt.println("redraw brush")
            brushFmt := sdl.GetPixelFormatDetails(brush.format)
            brushCol := sdl.MapRGBA(brushFmt, nil, u8(slider_red), u8(slider_green), u8(slider_blue), u8(slider_alpha))
            brushBg := sdl.MapRGBA(brushFmt, nil, u8(slider_red), u8(slider_green), u8(slider_blue), 0)
            sdl.DestroySurface(brush)
            brush = sdl.CreateSurface(BRUSH_W, BRUSH_H, .RGBA32)
            sdl.SetSurfaceBlendMode(brush, {.BLEND})
            if (brush == nil) {
                print_err()
            }
            brushCanvas: [^]sdl.Uint32 = ([^]sdl.Uint32)(brush.pixels)
            for y in 0..<BRUSH_H {
                for x in 0..<BRUSH_W {
                    if ( ((x - BRUSH_W/2)*(x - BRUSH_W/2) + (y - BRUSH_H/2)*(y - BRUSH_H/2)) <= (BRUSH_H/2)*(BRUSH_W/2)) {
                        pixelOffset := brush.pitch / 4 * y + x
                        brushCanvas[pixelOffset] = brushCol
                    }
                    else {
                        pixelOffset := brush.pitch / 4 * y + x
                        brushCanvas[pixelOffset] = brushBg
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
                case .MOUSE_BUTTON_DOWN:
                    mu_mouse: microui.Mouse
                    mu_mouse = microui.Mouse.LEFT
                    microui.input_mouse_down(mu_context, i32(event.motion.x), i32(event.motion.y), mu_mouse)
                    r,g,b,a :sdl.Uint8
                    fmt.printfln("------")
                    sdl.ReadSurfacePixel(surface, c.int(event.button.x), c.int(event.button.y), &r, &g, &b,&a)
                    fmt.printfln("surf -- r:{} g:{} b:{} a:{}", r,g,b,a)
                    sdl.ReadSurfacePixel(canvas_layer, c.int(event.button.x), c.int(event.button.y), &r, &g, &b,&a)
                    fmt.printfln("canv -- r:{} g:{} b:{} a:{}", r,g,b,a)
                    sdl.ReadSurfacePixel(brush, BRUSH_W / 2, BRUSH_H / 2, &r, &g, &b,&a)
                    fmt.printfln("brus -- r:{} g:{} b:{} a:{}", r,g,b,a)
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
                case .MOUSE_MOTION:
                    microui.input_mouse_move(mu_context, i32(event.motion.x), i32(event.motion.y))
                    if event.motion.state == {.LEFT} {
                        // fmt.printfln("draw px {} : {}", event.motion.x, event.motion.y)
                        // draw_pixel(event.motion.x, event.motion.y, window, red)
                        destRect.h = BRUSH_H
                        destRect.w = BRUSH_W
                        destRect.x = i32(event.motion.x) - BRUSH_W/2
                        destRect.y = i32(event.motion.y) - BRUSH_H/2
                        sdl.BlitSurface(brush, nil, canvas_layer, &destRect)
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
            }

            
        }

        microui.begin(mu_context)

        microui.begin_window(mu_context, "Helloooo", {10, 10, 320, 400})

        res := microui.button(mu_context, "Button")
        res_toggle := microui.checkbox(mu_context, "use ICC", &use_icc)
        if (.SUBMIT in res) do fmt.println("button L pressy")
        microui.label(mu_context, fmt.aprintf("time: %.2f ms", f32(frame_time)/1000000.0))
        microui.layout_row(mu_context, {300}, 0)
        n_rect := microui.layout_next(mu_context)
        microui.draw_rect(mu_context, n_rect, {u8(slider_red), u8(slider_green), u8(slider_blue), 255})
        res_r := microui.slider(mu_context, &slider_red, 0, 255)
        res_g := microui.slider(mu_context, &slider_green, 0, 255)
        res_b := microui.slider(mu_context, &slider_blue, 0, 255)
        res_a := microui.slider(mu_context, &slider_alpha, 0, 255)
        microui.label(mu_context, "size:")
        res_size := microui.slider(mu_context, &slider_size, 1, 1000)

        if (.CHANGE in res_size) {
            BRUSH_H = i32(slider_size)
            BRUSH_W = i32(slider_size)
            redraw_brush = true
        }

        if ((.CHANGE in res_r) || (.CHANGE in res_g) || (.CHANGE in res_b) || (.CHANGE in res_a)) {
            redraw_brush = true
        }

        ui_window := microui.get_current_container(mu_context)
        microui.label(mu_context, fmt.aprintf("{}, {}", ui_window.rect.w, ui_window.rect.h))
        microui.end_window(mu_context)

        // microui.begin_window(mu_context, "Hmmm", {10, 10, 200, 400})
        // res1 := microui.button(mu_context, "Button 1")
        // if (.SUBMIT in res1) do fmt.println("button 1 pressy")
        // res2 := microui.button(mu_context, "Button 2")
        // if (.SUBMIT in res2) do fmt.println("button 2 pressy")
        // microui.end_window(mu_context)

        microui.end(mu_context)

        
        // if(!sdl.LockSurface(brush)) do fmt.printfln("Error: {}", sdl.GetError())
        

        // sdl.ClearSurface(ui_layer, 0, 0, 0, 0)
        mu_command: ^microui.Command
        for microui.next_command(mu_context, &mu_command) {
            #partial switch cmd in mu_command.variant {
                case ^microui.Command_Rect:
                    mu_draw_rect(cmd.rect, cmd.color, ui_layer)
                case ^microui.Command_Text:
                    mu_draw_text(cmd.str, cmd.pos, cmd.color, ui_layer)
                    
            }
        }

        // sdl.ClearSurface(surface, 0, 0, 0, 1)
        sdl.BlitSurface (canvas_layer, nil, surface, nil)
        ui_window_rect: sdl.Rect = { w = ui_window.rect.w, h = ui_window.rect.h, x = ui_window.rect.x, y = ui_window.rect.y}
        sdl.BlitSurface(ui_layer, &ui_window_rect, surface, &ui_window_rect)
        // sdl.BlitSurface(ui_layer, nil, surface, nil)

        if use_icc {

            surface_copy := sdl.DuplicateSurface(surface)
            // sdl.LockSurface(surface)
            lcms.DoTransform(h_transform, surface.pixels, surface_copy.pixels, u32(surface.h * surface.w))
            // sdl.UnlockSurface(surface)
            sdl.BlitSurface(surface_copy, nil, surface, nil)
            sdl.DestroySurface(surface_copy)
        }

        sdl.UpdateWindowSurface(window)
    }

    sdl.DestroyWindow(window)
    sdl.Quit()
}