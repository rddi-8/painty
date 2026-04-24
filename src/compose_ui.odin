package main

import "core:math"
import mu "microui"
import "render"
import "core:fmt"
import "color"
import "math2"

compose_color_picker :: proc(app: ^Application, is_open: ^bool) {
    NAME :: "Colooor"
    ctx := app.ui_context.mu_context
    mu.get_container(ctx, NAME).open = b32(is_open^)
    if mu.begin_window(ctx, NAME, {200, 100, 300, 300}) {
        defer mu.end_window(ctx)
        ctn := mu.get_current_container(ctx)
        
        mu.layout_row(ctx, {-1})
        mu.slider(ctx, &col_f, 0, 1)
        
        top_content_size := ctn.content_size

        @static test_mesh: render.UI_Mesh
        test_mesh = render.gen_circle(64, 16, map_wheel_col_hsl)
        picker_size := math.min(ctn.body.w, ctn.body.h - top_content_size.y)

        mu.draw_mesh(ctx, {ctn.body.x, ctn.body.y + top_content_size.y, picker_size, picker_size} , &test_mesh)
        
    }
    is_open^ = bool(mu.get_container(ctx, NAME).open)
}

compose_panel_test :: proc(app: ^Application) {
    NAME :: "Panel Test"
    ctx := app.ui_context.mu_context
    // mu.get_container(ctx, NAME).open = b32(is_open^)
    if mu.begin_window(ctx, NAME, {200, 100, 300, 300}) {
        defer mu.end_window(ctx)
        ctn := mu.get_current_container(ctx)

        mu.layout_row(ctx, {-1})
        mu.slider(ctx, &col_f, 0, 1)

        fg_color := color.to_col8(app.fg_color)
        preview_color: mu.Color
        preview_color.r = fg_color.r
        preview_color.g = fg_color.g
        preview_color.b = fg_color.b
        preview_color.a = fg_color.a
        picker_pos: [2]i32
        @static picker_pos_rel: [2]f32

        mu.layout_row(ctx, {-1}, -(ctx.style.size.y + ctx.style.spacing)*3)
        mu.begin_panel(ctx, "Some Panel", {.EXPANDED})
            id := mu.get_id(ctx, "Some Panel")

            @static test_mesh: render.UI_Mesh
            test_mesh = render.gen_circle(64, 16, map_wheel_col_hsl)
            panel := mu.get_current_container(ctx)
            size := math.min(panel.body.h, panel.body.w)
            panel.body.h = size
            panel.body.w = size

            mu.update_control(ctx, id, panel.body)

            if ctx.focus_id == id && ctx.mouse_down_bits == {.LEFT} {
                m_pos := ctx.mouse_pos - {panel.body.x, panel.body.y}
                norm_pos: [2]f32 = {f32(m_pos.x)/f32(size), f32(m_pos.y)/f32(size)}
                norm_pos = norm_pos*2 - 1
                norm_pos = math2.clamp_circle(norm_pos)
                picker_pos_rel = norm_pos
            }
            picker_pos.x = i32((picker_pos_rel.x+1)*0.5*f32(size))
            picker_pos.y = i32((picker_pos_rel.y+1)*0.5*f32(size))
            picked_color := map_wheel_col_hsl(picker_pos_rel)
            preview_color.r = u8(picked_color.r * 255)
            preview_color.g = u8(picked_color.g * 255)
            preview_color.b = u8(picked_color.b * 255)
            app.fg_color = picked_color
            picker_pos = [2]i32{panel.body.x, panel.body.y} + picker_pos
            picker_size: i32 = 12
            picker_rect: mu.Rect = mu.Rect{
                x = picker_pos.x - picker_size,
                y = picker_pos.y - picker_size,
                w = picker_size*2,
                h = picker_size*2}

            mu.draw_mesh(ctx, panel.body , &test_mesh)
            mu.draw_texture_rect(ctx, picker_rect,  {255,255,255,255}, app.ui_context.icons[.PICKER_RING])

        mu.end_panel(ctx)
        mu.layout_row(ctx, {100, 100, 100})
        mu.button(ctx, "BTN3")
        mu.button(ctx, "BTN4")
        mu.button(ctx, "BTN5")
        mu.button(ctx, "BTN6")
        r := mu.layout_next(ctx)
        mu.draw_rect(ctx, r, preview_color)
        
    }
    // is_open^ = bool(mu.get_container(ctx, NAME).open)
}

compose_main :: proc(app: ^Application) {
    NAME :: "Main Panel"
    ctx := app.ui_context.mu_context
    mu.get_container(ctx, NAME).rect = {0,0, i32(app.window_size.x), 40}
    mu.begin_window(ctx, NAME,{0,0, i32(app.window_size.x), 40}, {.NO_RESIZE, .NO_TITLE, .NO_CLOSE, .NO_SCROLL})
    defer mu.end_window(ctx)

    mu.layout_row(ctx, {100, 100, 100, 100})
    mu.button(ctx, "BTN1 xxxxxxxxxxxxxxxxx", .NONE, {.AUTO_SIZE})

    PANELS :: "PANELS"
    if .SUBMIT in mu.button(ctx, PANELS) {
        mu.open_popup(ctx, PANELS)
    }
    if mu.begin_popup(ctx, PANELS) {
        defer mu.end_popup(ctx)
        mu.checkbox(ctx, "Color Picker", &app.ui_state.color_picker_open)
    }

}