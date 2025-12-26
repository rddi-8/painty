package main

import "core:c"
import "vendor:sdl3/ttf"
import "core:mem"
import "core:fmt"
import sdl "vendor:sdl3"
import "vendor:microui"

WINDOW_W :: 800
WINDOW_H :: 400

Color :: [4]f32
Vec2 :: [2]f32

tracking_alloc: mem.Tracking_Allocator

Application :: struct {
    window: ^sdl.Window,
    mu_context: ^microui.Context,
    ui_font: ^ttf.Font
}


main :: proc() {
    mem.tracking_allocator_init(&tracking_alloc, context.allocator)
    defer mem.tracking_allocator_destroy(&tracking_alloc)
    context.allocator = mem.tracking_allocator(&tracking_alloc)
    
    
    app := new(Application)
    init_app(app, WINDOW_W, WINDOW_H)

    main_loop: for {
        ev: sdl.Event
        for sdl.PollEvent(&ev) {
            #partial switch ev.type {
                case .QUIT:
                    break main_loop
            }
        }
    }

    sdl.Quit()
    
    
}

init_app :: proc(application: ^Application, window_w, window_h: int) {
    if !sdl.Init({.VIDEO}) do print_sdl_err()
    if !ttf.Init() do print_sdl_err()

    application.window = sdl.CreateWindow("Painty", c.int(window_w), c.int(window_h), {.RESIZABLE})
    if application.window == nil do print_sdl_err()

    application.ui_font = ttf.OpenFont("fonts/DroidSans.ttf", 12)
    ui_init(application, application.ui_font)
}

print_sdl_err :: proc() {
    fmt.printfln("SDL Error: {}", sdl.GetError())
}