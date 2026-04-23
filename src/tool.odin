package main

PenState :: struct {
    screen_position: Vec2,
    canvas_position: Vec2,
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
    size: f32,
    flow: f32,
    opacity: f32,
}