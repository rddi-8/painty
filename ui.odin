package main

import "core:log"
import "core:fmt"
import mu "vendor:microui"
import "vendor:sdl3/ttf"
import "render"

Rect_List :: [dynamic]render.Rect_Instance

Ui_Context :: struct {
    mu_context: ^mu.Context,
    default_font: mu.Font,
    rect_list: Rect_List
}

ui_init :: proc(ui_ctx: ^Ui_Context) {
    ui_ctx.mu_context = new(mu.Context)
    mu.init(ui_ctx.mu_context)

    ui_font := ttf.OpenFont("fonts/DroidSans.ttf", 12)
    ui_ctx.default_font = cast(mu.Font)ui_font

    ui_ctx.mu_context.text_height = mu_text_height
    ui_ctx.mu_context.text_width = mu_text_width
    ui_ctx.mu_context.style.font = cast(mu.Font)ui_font

    list := make([dynamic]render.Rect_Instance)
    ui_ctx.rect_list = list


    for ins in ui_ctx.rect_list {
        fmt.println(ins)
    }

}

mu_text_height :: proc(font: mu.Font) -> i32 {
    ttf_font := cast(^ttf.Font)font
    return i32(ttf.GetFontSize(ttf_font))
}

mu_text_width :: proc(font: mu.Font, str: string) -> i32 {
    ttf_font := cast(^ttf.Font)font
    text := ttf.CreateText(nil, ttf_font, fmt.ctprint(str), 0)
    if (text == nil) do print_sdl_err()

    w: i32 = 12
    text_size := ttf.GetTextSize(text, &w, nil)
    ttf.DestroyText(text)
    return w
}

render_ui :: proc(ui_ctx: ^Ui_Context) {
    mu_ctx := ui_ctx.mu_context
    clear(&ui_ctx.rect_list)
    cmd_backing: ^mu.Command
    for cmd_variant in mu.next_command_iterator(mu_ctx, &cmd_backing) {
        #partial switch cmd in cmd_variant {
            case ^mu.Command_Rect:
                mu_draw_rect(cmd.rect, cmd.color, &ui_ctx.rect_list)
            case ^mu.Command_Text:
                mu_draw_text(cmd.str, cmd.pos, cmd.color, &ui_ctx.rect_list)
            case ^mu.Command_Icon:
                mu_draw_icon(cmd.id, cmd.rect, cmd.color, &ui_ctx.rect_list)
        }
    }
}

mu_draw_rect :: proc(rect: mu.Rect, color: mu.Color, rect_list: ^Rect_List) {
    rect_instance := render.Rect_Instance{
        pos = {f32(rect.x), f32(rect.y)},
        size = {f32(rect.w), f32(rect.h)},
        color = c_u8_f32({color.r, color.g, color.b, color.a})
    }
    append(rect_list, rect_instance)

}

mu_draw_text :: proc(text: string, pos: mu.Vec2, color: mu.Color, rect_list: ^Rect_List) {

}

mu_draw_icon :: proc(id: mu.Icon, rect: mu.Rect, color: mu.Color, rect_list: ^Rect_List) {

}