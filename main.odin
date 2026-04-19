package main

import "core:time"
import "base:builtin"
import "core:math/rand"
import "core:os"
import "core:encoding/json"
import "core:log"
import "base:runtime"
import "core:c"
import "vendor:sdl3/ttf"
import "core:mem"
import "core:fmt"
import sdl "vendor:sdl3"
import "vendor:microui"

import "render"

WINDOW_W :: 800
WINDOW_H :: 400

Color :: [4]f32
Vec2 :: [2]f32

tracking_alloc: mem.Tracking_Allocator

Application :: struct {
    window: ^sdl.Window,
    ui_context: ^Ui_Context,
    render_info: ^render.Render_Info,
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

    particles := make(Rect_List, 200000, 200000)
    for &p in particles {
        p.pos = {rand.float32_range(0, 2000), rand.float32_range(0, 1000)}
        p.size = {rand.float32_range(1,32), rand.float32_range(1,32)}
        p.color = {rand.float32_range(0, 1),rand.float32_range(0, 1),rand.float32_range(0, 1), 0.2}
    }
    fmt.println(size_of(render.Rect_Instance)*len(particles))

    /// TESTY
    rr1 := [2]render.Rect_Instance{
        {pos = {20, 20}, size = {40,40}, color = {1,0,0,1}},
        {pos = {120, 20}, size = {40,40}, color = {0,1,0,1}},
    }
    rr2 := [2]render.Rect_Instance{
        {pos = {20, 120}, size = {40,40}, color = {1,0,0.5,1}},
        {pos = {120, 120}, size = {40,40}, color = {0,1,0.5,1}},
    }
    vbuff := render.create_vbuffer(app.render_info.device, {.VERTEX}, 10000)
    r_buff1, _ := render.vbuffer_reserve(vbuff, size_of(render.Rect_Instance) * len(rr1))
    r_buff2, _ := render.vbuffer_reserve(vbuff, size_of(render.Rect_Instance) * len(rr2))

    cp1 := [2]render.Copy_Description{
        {src = {ptr = raw_data(rr1[:]), size = size_of(render.Rect_Instance) * len(rr1)}, dst = r_buff1},
        {src = {ptr = raw_data(rr2[:]), size = size_of(render.Rect_Instance) * len(rr2)}, dst = r_buff2}
    }
    render.vbuffer_batch_copy(app.render_info, vbuff, cp1[:])

    
    main_loop: for {
        last_frame: u64 = sdl.GetTicksNS() - timer
        fmt.printfln("%.2f ms", f64(last_frame)/1000000)
        timer = sdl.GetTicksNS()

        ev: sdl.Event
        for sdl.PollEvent(&ev) {
            #partial switch ev.type {
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
        microui.button(mu, "BTN2")
        microui.button(mu, "BTN3")
        microui.end_window(mu)

        microui.end(mu)

        render_ui(app.ui_context)
        
        ww, wh :c.int
        sdl.GetWindowSize(app.window, &ww, &wh)
        render.create_render_target(app.render_info, u32(ww), u32(wh))

        scene := render.Scene{}
        for &p in particles {
            // p.pos += {rand.float32_normal(0, 1), rand.float32_normal(0,1)}
            p.pos += {0, 0.01}
        }
        // time.sleep(1000000)
        render.render_rects(app.render_info, particles[:], .CLEAR)
        render.render_rects(app.render_info, app.ui_context.rect_list[:], .DONT_CARE)
        render.render_rects2(app.render_info, []render.Buffer_Portion{r_buff1, r_buff2}, .LOAD)

        render.present(app.render_info)
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
   
    application.ui_context = new(Ui_Context)
    ui_init(application.ui_context)
}

print_sdl_err :: proc() {
    fmt.printfln("SDL Error: {}", sdl.GetError())
}