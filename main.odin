package main

import "core:math"
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

    particles := make(Rect_List, 20000, 20000)
    for &p in particles {
        p.pos = {rand.float32_range(0, 2000), rand.float32_range(0, 1000)}
        p.size = {rand.float32_range(1,32), rand.float32_range(1,32)}
        p.color = {rand.float32_range(0, 1),rand.float32_range(0, 1),rand.float32_range(0, 1), 0.2}
    }
    fmt.printfln("size of particles: %M (element: %M)", size_of(render.Rect_Instance)*len(particles), size_of(render.Rect_Instance))

    /// TESTY
    rr1 := [2]render.Rect_Instance{
        {pos = {20, 20}, size = {40,40}, color = {1,0,0,1}},
        {pos = {120, 20}, size = {40,40}, color = {0,1,0,1}},
    }
    rr2 := [2]render.Rect_Instance{
        {pos = {20, 120}, size = {40,40}, color = {1,0,0.5,1}},
        {pos = {120, 120}, size = {40,40}, color = {0,1,0.5,1}},
    }
    r_mov := [1]render.Rect_Instance{
        {pos = {100, 100}, size = {20, 20}, color = {0,0,1,1}}
    }

    vbuff := render.create_vbuffer(app.render_info.device, {.VERTEX}, 10000)
    vbuff2 := render.create_vbuffer(app.render_info.device, {.VERTEX}, 10000)
    
    tex_quad_idxbuff := render.create_vbuffer(app.render_info.device, {.INDEX}, 10000)
    
    blue_buffer, _ := render.vbuffer_reserve(vbuff, size_of(render.Rect_Instance) * len(r_mov))
    r_buff1, _ := render.vbuffer_reserve(vbuff, size_of(render.Rect_Instance) * len(rr1))
    r_buff2, _ := render.vbuffer_reserve(vbuff, size_of(render.Rect_Instance) * len(rr2))

    cp1 := [2]render.Copy_Description{
        {src = {ptr = raw_data(rr1[:]), size = size_of(render.Rect_Instance) * len(rr1)}, dst = r_buff1},
        {src = {ptr = raw_data(rr2[:]), size = size_of(render.Rect_Instance) * len(rr2)}, dst = r_buff2}
    }
    
    render.vbuffer_batch_copy(app.render_info, cp1[:])
    
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
        microui.button(mu, "BTN2")
        microui.button(mu, "BTN3")
        microui.end_window(mu)
        
        microui.end(mu)
        
        
        
        // for &b in r_mov {
            //     b.pos += {0.01, 0}
            // }
            
            // cp_r := [1]render.Copy_Description{
                //     {src = {ptr = raw_data(r_mov[:]), size = size_of(render.Rect_Instance) * len(r_mov)}, dst = blue_buffer}
                // }
                
                // render.vbuffer_batch_copy(app.render_info, cp_r[:])
                
        scene := render.Scene{}
        for &p in particles {
            // p.pos += {rand.float32_normal(0, 1), rand.float32_normal(0,1)}
            p.pos += {0, 0.01}
        }
        // time.sleep(1000000)
        render.vbuffer_reset(vbuff)
        render.vbuffer_reset(vbuff2)
        render.vbuffer_reset(tex_quad_idxbuff)
        
        
        // render.render_rects(app.render_info, particles[:], .CLEAR)
        // if (true) {
        //     render.present(app.render_info)
        //     fmt.print(fmt.tprintfln("MEM: %M", tracking_alloc.current_memory_allocated))
        //     free_all(context.temp_allocator)
        //     continue
        // }
        // render.render_rects(app.render_info, app.ui_context.rect_list[:], .DONT_CARE)
        // render.render_rects2(app.render_info, []render.Buffer_Portion{r_buff1, r_buff2, blue_buffer}, .LOAD)
        
        // text := ttf.CreateText(app.text_renderer.text_engine, app.text_renderer.font, "Hello World!", 0)
        // text_seq := ttf.GetGPUTextDrawData(text)
        
        // for t in app.ui_context.text_seq {
        //     render.render_text(app.render_info, t, vbuff, vbuff2, tex_quad_idxbuff)
        // }
        
        // render.render_text(app.render_info, text_seq, vbuff, vbuff2, tex_quad_idxbuff)
        
        render_ui(app.ui_context, app, vbuff, tex_quad_idxbuff)
        
        render.present(app.render_info)
        
        // ttf.DestroyText(text)
        clear(&app.ui_context.text_seq)

        fmt.print(fmt.tprintfln("MEM: %M", tracking_alloc.current_memory_allocated))
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