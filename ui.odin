package main

import "core:fmt"
import "vendor:microui"
import "vendor:sdl3/ttf"

ui_init :: proc(application: ^Application, font: ^ttf.Font) {
    application.mu_context = new(microui.Context)
    microui.init(application.mu_context)

    application.mu_context.text_height = mu_text_height
    application.mu_context.text_width = mu_text_width
    application.mu_context.style.font = cast(microui.Font)font
}

mu_text_height :: proc(font: microui.Font) -> i32 {
    ttf_font := cast(^ttf.Font)font
    return i32(ttf.GetFontSize(ttf_font))
}
mu_text_width :: proc(font: microui.Font, str: string) -> i32 {
    ttf_font := cast(^ttf.Font)font
    text := ttf.CreateText(nil, ttf_font, fmt.ctprint(str), 0)
    if (text == nil) do print_sdl_err()

    w: i32 = 12
    text_size := ttf.GetTextSize(text, &w, nil)
    ttf.DestroyText(text)
    return w
}