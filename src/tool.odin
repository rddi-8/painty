package main

import "canvas"

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
    brush_type: Brush_Tip,
    brush_tip_options: Brush_Tip_Options,
    brush_mode: canvas.Brush_Mode,
    bound_layer: Layer_Kind,
    alt_brush: int,
    color: Color,
    _size: f32,
    size: int,
    size_press: bool,
    min_size: f32,
    step: f32,
    flow: f32,
    flow_press: bool,
    min_flow: f32,
    opacity: f32,
    opacity_press: bool,
    min_opacity: f32,
    multisample: bool,
    multisample_range: f32,
}

Brush_Round_Pixel_Opt :: struct {
    _: int
}
Brush_Round_Soft_Opt :: struct {
    feather: f32,
}
Brush_Round_Feather_Opt :: struct {
    feather_size: f32,
}
Brush_Round_Square_Opt :: struct {
    _: int
}

Brush_Tip_Options :: union {
    Brush_Round_Pixel_Opt,
    Brush_Round_Soft_Opt,
    Brush_Round_Feather_Opt,
    Brush_Round_Square_Opt,
}

Brush_Tip :: enum {
    UNDEFINED,
    ROUND_PIXEL,
    ROUND_SOFT,
    ROUND_FEATHER,
    SQUARE,
}

Brush_Tip_Names: [Brush_Tip]string = {
    Brush_Tip.UNDEFINED = "undefined",
    Brush_Tip.ROUND_PIXEL = "Round (Pixely)",
    Brush_Tip.ROUND_SOFT = "Round (Soft)",
    Brush_Tip.ROUND_FEATHER = "Round (Feather)",
    Brush_Tip.SQUARE = "Square",
}

Brush_Tip_Opt_Map: [Brush_Tip]Brush_Tip_Options = {
    Brush_Tip.UNDEFINED = nil,
    Brush_Tip.ROUND_PIXEL = Brush_Round_Pixel_Opt{},
    Brush_Tip.ROUND_SOFT = Brush_Round_Soft_Opt{},
    Brush_Tip.ROUND_FEATHER = Brush_Round_Feather_Opt{},
    Brush_Tip.SQUARE = Brush_Round_Square_Opt{},
}