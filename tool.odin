package main

Pen_Button :: enum {
    TIP,
    BT_1,
    BT_2
}

Pen_Buttons :: bit_set[Pen_Button]

PenState :: struct {
    screen_position: Vec2,
    canvas_position: Vec2,
    pressure: f32,
    held_buttons: Pen_Buttons,
    pressed_buttons: Pen_Buttons,
    released_buttons: Pen_Buttons,
}

ToolState :: struct {
    color: Color,
    size: f32,
    flow: f32,
    opacity: f32,
}