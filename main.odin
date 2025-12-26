package main

import "core:log"
import "base:runtime"
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

main_context: runtime.Context

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
    init_app(app, WINDOW_W, WINDOW_H)

    keybind_map := new(Key_Bind_Map)

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

    main_loop: for {
        ev: sdl.Event
        for sdl.PollEvent(&ev) {
            #partial switch ev.type {
                case .QUIT:
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
                    log.debug("Held Action:", a.type, "up:", a.up)
            }
        }

        clear(&actions)
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