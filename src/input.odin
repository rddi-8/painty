package main

import sdl "vendor:sdl3"

InputContext :: enum {
    PAINTING
}

Pen_Button :: enum {
    TIP,
    BT_1,
    BT_2
}
Pen_Buttons :: bit_set[Pen_Button]

Mouse_Button :: enum {
    LEFT,
    RIGHT,
    MIDDLE,
    MBT_4,
    MBT_5,
}
Mouse_Buttons :: bit_set[Mouse_Button]

PointerInput :: struct {
    screen_position: Vec2,
    held_buttons: Mouse_Buttons,
    pressed_buttons: Mouse_Buttons,
    released_buttons: Mouse_Buttons,
}

Action_Simple_Enum :: enum {
    PRINT_ACTION,
    PICK_COLOR,
    FLIP_CANVAS,
    TOGGLE_OPACITY_PRESSURE,
    TOGGLE_SIZE_PRESSURE,
    DO_A_CARTWHEEL,
    QUIT,
}
Action_Simple :: struct {
    type: Action_Simple_Enum,
}

Action_Held_Enum :: enum {
    EYE_DROPPER,
    DRAG_BRUSH_SIZE,
    DRAG_BRUSH_OPACITY
}
Action_Held :: struct {
    type: Action_Held_Enum,
    up: bool,
}
Currently_Held_Actions :: bit_set[Action_Held_Enum] 

Action_Parameter_Enum :: enum {
    ROTATE_CANVAS,
    SET_TOOL_OPACITY
}
Action_Parameter :: struct {
    type: Action_Parameter_Enum,
    value: f32
}

Action_Color_Enum :: enum {
    SET_FG_COL,
    SET_BG_COL,
}

Action_Color :: struct {
    type: Action_Color_Enum,
    color: Color
}

Action_Canvas_Location_Enum :: enum {
    MOVE_TOOL,
    BRUSH_TOUCH,
    BRUSH_ALT
}

Action_Canvas_Location :: struct {
    type: Action_Canvas_Location_Enum,
    location: [2]f32
}

Action_ToolToggle :: struct {
    tool_id: string
}

Action_BoolToggle :: struct {
    value: ^bool
}

Action :: union {
    Action_Simple,
    Action_Parameter,
    Action_Canvas_Location,
    Action_Held,
    Action_ToolToggle,
    Action_BoolToggle
}

Modifier_Keys_Enum :: enum {
    CTRL,
    SHIFT,
    ALT,
}
Modifier_Keys :: bit_set[Modifier_Keys_Enum]

Input_Event_Key :: struct {
    key: sdl.Scancode,
    mod: sdl.Keymod,
    ignore_mod: bool,
    use_repeat: bool,
    ctx: InputContext
}

Input_Event_Mouse :: struct {
    button: Mouse_Button,
    up: bool,
    ctx: InputContext
}

Input_Event_Pen :: struct {
    button: Pen_Button,
    up: bool,
    ctx: InputContext
}

Bind_Key :: struct {
    key_event: Input_Event_Key,
    action: Action
}

Bind_Mouse :: struct {
    mouse_event: Input_Event_Mouse,
    action: Action
}

Bind_Pen :: struct {
    pen_event: Input_Event_Pen,
    action: Action
}

Action_Binds :: struct {
    key_binds: Key_Bind_Map,
    mouse_binds: Mouse_Bind_Map,
    pen_binds: Pen_Bind_Map
}

Key_Bind_Map :: distinct [len(sdl.Scancode)][dynamic]Bind_Key
Mouse_Bind_Map :: distinct [len(Mouse_Button)][dynamic]Bind_Mouse
Pen_Bind_Map :: distinct [len(Pen_Button)][dynamic]Bind_Pen

add_keybind_kb :: proc(kb_map: ^Key_Bind_Map, key_input: Input_Event_Key, action: Action) {
    append(&kb_map[key_input.key], Bind_Key{key_event = key_input, action = action})
}
add_keybind_mouse :: proc(kb_map: ^Mouse_Bind_Map, mouse_input: Input_Event_Mouse, action: Action) {
    append(&kb_map[mouse_input.button], Bind_Mouse{mouse_event = mouse_input, action = action})
}
add_keybind_pen :: proc(kb_map: ^Pen_Bind_Map, pen_input: Input_Event_Pen, action: Action) {
    append(&kb_map[pen_input.button], Bind_Pen{pen_event = pen_input, action = action})
}

add_keybind :: proc{
    add_keybind_kb,
    add_keybind_mouse,
    add_keybind_pen,
}