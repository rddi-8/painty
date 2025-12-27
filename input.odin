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

Simple_Action_Enum :: enum {
    PRINT_ACTION,
    PICK_COLOR,
    FLIP_CANVAS,
    TOGGLE_OPACITY_PRESSURE,
    TOGGLE_SIZE_PRESSURE,
    DO_A_CARTWHEEL,
    QUIT,
}
Action_Simple :: struct {
    type: Simple_Action_Enum,
}

Held_Action_Enum :: enum {
    EYE_DROPPER,
    DRAG_BRUSH_SIZE,
    DRAG_BRUSH_OPACITY
}
Held_Action :: struct {
    type: Held_Action_Enum,
    up: bool,
}
Currently_Held_Actions :: bit_set[Held_Action_Enum] 

Parameter_Action_Enum :: enum {
    ROTATE_CANVAS,
    SET_TOOL_OPACITY
}
Parameter_Action :: struct {
    type: Parameter_Action_Enum,
    value: f32
}

ToolToggle_Action :: struct {
    tool_id: int
}

Action :: union {
    Action_Simple,
    Parameter_Action,
    Held_Action,
    ToolToggle_Action
}

Modifier_Keys_Enum :: enum {
    CTRL,
    SHIFT,
    ALT,
}
Modifier_Keys :: bit_set[Modifier_Keys_Enum]

Key_Input_Event :: struct {
    key: sdl.Scancode,
    mod: sdl.Keymod,
    ignore_mod: bool,
    use_repeat: bool,
    ctx: InputContext
}

Key_Bind :: struct {
    key_event: Key_Input_Event,
    action: Action
}


Key_Bind_Map :: [len(sdl.Scancode)][dynamic]Key_Bind

add_keybind :: proc(kb_map: ^Key_Bind_Map, key_input: Key_Input_Event, action: Action) {
    append(&kb_map[key_input.key], Key_Bind{key_event = key_input, action = action})
}