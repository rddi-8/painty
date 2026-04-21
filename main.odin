package main

import "core:log"
import "base:runtime"
import "core:c"
import "vendor:sdl3/ttf"
import "core:mem"
import "core:fmt"
import sdl "vendor:sdl3"

import "microui"
import "render"
import "colors"

WINDOW_W :: 800
WINDOW_H :: 400

Color :: [4]f32
Vec2 :: [2]f32

tracking_alloc: mem.Tracking_Allocator

Text_Renderer :: struct {
    text_engine: ^ttf.TextEngine,
    font: ^ttf.Font
}

Application :: struct {
    window: ^sdl.Window,
    ui_context: ^Ui_Context,
    render_info: ^render.Render_Info,
    text_renderer: ^Text_Renderer
}

main_context: runtime.Context

timer: u64

main :: proc() {
    mem.tracking_allocator_init(&tracking_alloc, context.allocator)
    defer mem.tracking_allocator_destroy(&tracking_alloc)
    context.allocator = mem.tracking_allocator(&tracking_alloc)

    context.logger = log.create_console_logger()
    // context.logger.lowest_level = .Warning

    sdl.SetLogPriorities(.VERBOSE)
    main_context =  context
    sdl.SetLogOutputFunction(proc "c" (userdata: rawptr, category: sdl.LogCategory, priority: sdl.LogPriority, message: cstring) {
        context = main_context
        if (priority == .ERROR) {
            panic("ooops")
        }
        log.debugf("SDL {} [{}]: {}", category, priority, message)
    }, nil)
    
    
    app := new(Application)
    init_app(app, WINDOW_W, WINDOW_H, "Painty")

    keybind_map := new(Key_Bind_Map)

    add_keybind(keybind_map,
        {
            ctx = .PAINTING,
            key = .ESCAPE,
        },
        Action_Simple{type = .QUIT})
    add_keybind(keybind_map,
        {
            ctx = .PAINTING,
            key = .LALT,
            mod = {.LALT}
        },
        Held_Action{type = .EYE_DROPPER})
    
    add_keybind(keybind_map,
        {
            ctx = .PAINTING,
            key = .H,
            use_repeat = true,
            ignore_mod = true,
        },
        Action_Simple{type = .FLIP_CANVAS})

    add_keybind(keybind_map,
        {
            ctx = .PAINTING,
            key = .C,
            mod = {.LCTRL, .LSHIFT}
        },
        Action_Simple{type = .FLIP_CANVAS})

    add_keybind(keybind_map,
        {
            ctx = .PAINTING,
            key = .R,
        },
        Parameter_Action{type = .ROTATE_CANVAS, value = 10})

    add_keybind(keybind_map,
        {
            ctx = .PAINTING,
            key = .R,
            mod = {.LCTRL}
        },
        Parameter_Action{type = .ROTATE_CANVAS, value = -10})
    

    current_context := InputContext.PAINTING

    actions: [dynamic]Action
    held_actions: Currently_Held_Actions

 
    vbuff := render.create_vbuffer(app.render_info.device, {.VERTEX}, 30 * mem.Megabyte)
    
    idxbuff := render.create_vbuffer(app.render_info.device, {.INDEX}, 10000)
      
    
    ww, wh :c.int
    sdl.GetWindowSize(app.window, &ww, &wh)
    render.create_render_target(app.render_info, u32(ww), u32(wh))

    main_loop: for {
        last_frame: u64 = sdl.GetTicksNS() - timer
        // fmt.printfln("%.2f ms", f64(last_frame)/1000000)
        timer = sdl.GetTicksNS()

        ev: sdl.Event
        for sdl.PollEvent(&ev) {
            #partial switch ev.type {
                case .WINDOW_RESIZED:
                    ww, wh :c.int
                    sdl.GetWindowSize(app.window, &ww, &wh)
                    render.create_render_target(app.render_info, u32(ww), u32(wh))
                case .QUIT:
                    log.debug("SDL QUIT")
                    break main_loop
                case .KEY_DOWN:
                    keymod := ev.key.mod
                    keymod = keymod - {.NUM, .CAPS, .MODE, .SCROLL}
                    if len(keybind_map[ev.key.scancode]) > 0 {
                        kb_loop: for kb in keybind_map[ev.key.scancode] {
                            if !kb.key_event.use_repeat && ev.key.repeat {
                                continue kb_loop
                            }
                            if kb.key_event.ctx != current_context {
                                continue kb_loop
                            }
                            if kb.key_event.ignore_mod || kb.key_event.mod == keymod {
                                append(&actions, kb.action)
                            }
                        }
                    }
                case .KEY_UP:
                    if len(keybind_map[ev.key.scancode]) > 0 {
                        for kb in keybind_map[ev.key.scancode] {
                            if a, ok := kb.action.(Held_Action); ok {
                                a.up = true
                                append(&actions, a)
                            }
                        }
                    }
                case .MOUSE_MOTION:
                    microui.input_mouse_move(app.ui_context.mu_context, i32(ev.motion.x), i32(ev.motion.y))
                case .MOUSE_BUTTON_UP:
                    mu_mouse: microui.Mouse
                    switch ev.button.button {
                        case sdl.BUTTON_LEFT:
                            mu_mouse = microui.Mouse.LEFT
                        case sdl.BUTTON_RIGHT:
                            mu_mouse = microui.Mouse.RIGHT
                        case sdl.BUTTON_MIDDLE:
                            mu_mouse = microui.Mouse.MIDDLE
                    }
                    microui.input_mouse_up(app.ui_context.mu_context, i32(ev.motion.x), i32(ev.motion.y), mu_mouse)
                case .MOUSE_BUTTON_DOWN:
                    mu_mouse: microui.Mouse
                    switch ev.button.button {
                        case sdl.BUTTON_LEFT:
                            mu_mouse = microui.Mouse.LEFT
                        case sdl.BUTTON_RIGHT:
                            mu_mouse = microui.Mouse.RIGHT
                        case sdl.BUTTON_MIDDLE:
                            mu_mouse = microui.Mouse.MIDDLE
                    }
                    microui.input_mouse_down(app.ui_context.mu_context, i32(ev.motion.x), i32(ev.motion.y), mu_mouse)

            }
        }

        for action in actions {
            switch a in action {
                case Action_Simple:
                    log.debug("Action:", a.type)
                    #partial switch a.type {
                        case .QUIT:
                            break main_loop
                    }
                case Parameter_Action:
                    log.debug("Parameter Action:", a.type, "value:", a.value)
                case ToolToggle_Action:
                    log.debug("Toggle Tool Action:", "tool_id:", a.tool_id)
                case Held_Action:
                    if !a.up {
                        held_actions += {a.type}
                    }
                    else {
                        held_actions -= {a.type}
                    }
                    log.debug("Held Action:", a.type, "up:", a.up)
            }
        }
        clear(&actions)

        
        
        mu := app.ui_context.mu_context
        microui.begin(mu)
        microui.begin_window(mu, "Hehhh", {10, 10, 200, 400})
        microui.button(mu, "BTN1")
        microui.button(mu, "BTN2")
        microui.button(mu, "BTN3")
        microui.end_window(mu)
        
        microui.begin_window(mu, "Hehhh2", {300, 10, 300, 300})
        microui.button(mu, "BTN1")
        microui.layout_row(mu, {-70, -1}, 300)
        microui.begin_panel(mu, "Panel", {.EXPANDED})
        microui.layout_row(mu, {-1}, 32)

        @static val: f32
        gradient: colors.Gradient
        gradient.points = {
            {color = {1, 0, 0, 1}, position = 0},
            {color = {0, 1, 0, 1}, position = 0.5},
            {color = {0, 0, 1, 1}, position = 1},
        }
        microui.slider_gradient(mu, &val, 0, 10, gradient)
        @static val2: f32
        gradient2: colors.Gradient
        pts: [10]colors.GradientPoint
        c1: colors.RGB = colors.RGB(colors.to_linear({0.9, 0.1, 0.05}))
        c2: colors.RGB = colors.RGB(colors.to_linear({0.0, 0.3, 0.8}))
        cc1 := colors.linear_srgb_to_oklab(c1)
        cc2 := colors.linear_srgb_to_oklab(c2)
        for i in 0..<len(pts) {
            d := f32(i)/f32(len(pts) - 1)
            pts[i].position = d
            col := colors.oklab_to_linear_srgb(
                {
                    cc1.L*(1-d) + cc2.L*d,
                    cc1.a*(1-d) + cc2.a*d,
                    cc1.b*(1-d) + cc2.b*d,
                }
            )
            csrgb := colors.to_srgb(([3]f32)(col))
            pts[i].color = {f16(csrgb.r), f16(csrgb.g), f16(csrgb.b), 1}
        }
        gradient2.points = pts[:]
        microui.slider_gradient(mu, &val2, 0, 10, gradient2)

        @static val3: f32
        gradient3: colors.Gradient
        pts3: [100]colors.GradientPoint
        c13: colors.RGB = colors.RGB(colors.to_linear({0.9, 0.1, 0.05}))
        c23: colors.RGB = colors.RGB(colors.to_linear({0.0, 0.3, 0.8}))
        cc13 := colors.linear_srgb_to_oklab(c13)
        cc23 := colors.linear_srgb_to_oklab(c23)
        for i in 0..<len(pts3) {
            d := f32(i)/f32(len(pts3) - 1)
            pts3[i].position = d
            col := colors.oklab_to_linear_srgb(
                {
                    cc13.L*(1-d) + cc23.L*d,
                    cc13.a*(1-d) + cc23.a*d,
                    cc13.b*(1-d) + cc23.b*d,
                }
            )
            csrgb := colors.to_srgb(([3]f32)(col))
            pts3[i].color = {f16(csrgb.r), f16(csrgb.g), f16(csrgb.b), 1}
        }
        gradient3.points = pts3[:]
        microui.slider_gradient(mu, &val3, 0, 10, gradient3)

        microui.layout_row(mu, {-1}, 200)
        s := "Hello there my guise. What a fine day we have today, it's time to paint\n"
        @static textbuf: [128]u8
        // for i in 0..<len(s) {
        //     if i < 128 {
        //         textbuf[i] = s[i]
        //     }
        // }
        @static len: int = len(textbuf)
        microui.textbox(mu, textbuf[:], &len)
        microui.text(mu, s)
        microui.layout_row(mu, {-1})
        microui.button(mu, "submit")
        microui.end_panel(mu)
        microui.end_window(mu)
        
        microui.end(mu)


        

        render.vbuffer_reset(vbuff)
        render.vbuffer_reset(idxbuff)
        
        
        
        render_ui(app.ui_context, app, vbuff, idxbuff)
        
        render.present(app.render_info)
        

        clear(&app.ui_context.text_seq)

        // fmt.print(fmt.tprintfln("MEM: %M", tracking_alloc.current_memory_allocated))
        free_all(context.temp_allocator)
    }

   

    sdl.Quit()
    
    
}

init_app :: proc(application: ^Application, window_w, window_h: int, name: cstring) {
    if !sdl.Init({.VIDEO}) do print_sdl_err()
    if !ttf.Init() do print_sdl_err()

    application.window = sdl.CreateWindow(name, c.int(window_w), c.int(window_h), {.RESIZABLE})
    if application.window == nil do print_sdl_err()

    application.render_info = new(render.Render_Info)
    render.init(application.window, application.render_info)

    application.text_renderer = new(Text_Renderer)
    application.text_renderer.text_engine = ttf.CreateGPUTextEngine(application.render_info.device)
    application.text_renderer.font = ttf.OpenFont("fonts/DroidSans.ttf", 16.0)
   
    application.ui_context = new(Ui_Context)
    ui_init(application.ui_context)
}

print_sdl_err :: proc() {
    fmt.printfln("SDL Error: {}", sdl.GetError())
}