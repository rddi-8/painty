package main

create_default_keybinds :: proc(bind_list: ^Action_Binds) {
    kb_map := &bind_list.key_binds
    mouse_map := &bind_list.mouse_binds
    pen_map := &bind_list.pen_binds

    add_keybind(kb_map,
        Input_Event_Key{
            ctx = .PAINTING,
            key = .ESCAPE,
        },
        Action_Simple{type = .QUIT})
    add_keybind(kb_map,
        Input_Event_Key{
            ctx = .PAINTING,
            key = .LALT,
            mod = {.LALT}
        },
        Action_Held{type = .EYE_DROPPER})
    
    add_keybind(kb_map,
        Input_Event_Key{
            ctx = .PAINTING,
            key = .H,
            use_repeat = true,
            ignore_mod = true,
        },
        Action_Simple{type = .FLIP_CANVAS})

    add_keybind(kb_map,
        Input_Event_Key{
            ctx = .PAINTING,
            key = .C,
            mod = {.LCTRL, .LSHIFT}
        },
        Action_Simple{type = .FLIP_CANVAS})

    add_keybind(kb_map,
        Input_Event_Key{
            ctx = .PAINTING,
            key = .T,
            use_repeat = true,
        },
        Action_Parameter{type = .ROTATE_CANVAS, value = 10})

    add_keybind(kb_map,
        Input_Event_Key{
            ctx = .PAINTING,
            key = .R,
            use_repeat = true,
        },
        Action_Parameter{type = .ROTATE_CANVAS, value = -10})

    add_keybind(kb_map,
        Input_Event_Key{
            ctx = .PAINTING,
            key = .E,
            use_repeat = true,
        },
        Action_Parameter{type = .ZOOM_CANVAS, value = 1.2})

    add_keybind(kb_map,
        Input_Event_Key{
            ctx = .PAINTING,
            key = .E,
            use_repeat = true,
            mod = {.LCTRL}
        },
        Action_Parameter{type = .ZOOM_CANVAS, value = 0.8})

    add_keybind(kb_map,
        Input_Event_Key{
            ctx = .PAINTING,
            key = ._1,
        },
        Action_Parameter{type = .SET_CANVAS_ZOOM, value = 0.5})

    add_keybind(kb_map,
        Input_Event_Key{
            ctx = .PAINTING,
            key = ._2,
        },
        Action_Parameter{type = .SET_CANVAS_ZOOM, value = 1})

    add_keybind(kb_map,
        Input_Event_Key{
            ctx = .PAINTING,
            key = ._3,
        },
        Action_Parameter{type = .SET_CANVAS_ZOOM, value = 2})

    add_keybind(mouse_map,
        Input_Event_Mouse{
            ctx = .PAINTING,
            button = .LEFT
        },
        Action_Canvas_Location{type = .BRUSH_TOUCH, location = {1, 8}})

    add_keybind(mouse_map,
        Input_Event_Mouse{
            ctx = .PAINTING,
            button = .LEFT,
            up = true
        },
        Action_Parameter{type = .SET_TOOL_OPACITY, value = 0.5})

    add_keybind(kb_map,
        Input_Event_Key{
            ctx = .PAINTING,
            key = .K,
        },
        Action_ToolToggle{tool_id = "huhuhu"})
}