package main

PenState :: struct {
    screen_position: Vec2,
    canvas_position: Vec2,
    timestamp: u64,
    pressure: f32,
    held_buttons: Pen_Buttons,
    pressed_buttons: Pen_Buttons,
    released_buttons: Pen_Buttons,
}

MouseState :: struct {
    screen_position: Vec2,
    canvas_position: Vec2,
    pressure: f32,
    held_buttons: Mouse_Buttons,
    pressed_buttons: Mouse_Buttons,
    released_buttons: Mouse_Buttons,
}

ToolState :: struct {
    color: Color,
    _size: f32,
    size: int,
    size_press: bool,
    step: f32,
    flow: f32,
    flow_press: bool,
    opacity: f32,
    opacity_press: bool,
}