package main

import "core:prof/spall"
import "vendor:sdl3/ttf"
import "core:math"
import mu "microui"
import "render"
import "core:fmt"
import "color"
import "math2"
import sdl "vendor:sdl3"
import "canvas"

get_font :: proc(size: f32) -> ^ttf.Font {
    font: ^ttf.Font
    if size in font_cache {
        font = font_cache[size]
        fmt.printfln("{} cached", size)
    }
    else {
        font = ttf.OpenFont(RES_FONT, size)
        fmt.printfln("{} not cached", size)
        font_cache[size] = font
    }
    return font
}

scale_ui :: proc(app: ^Application) {
    scaling := sdl.GetWindowDisplayScale(app.window)
    scaled_style := mu.scale_style(mu.default_style, scaling * user_scaling)
    app.ui_context.mu_context._style = scaled_style
    app.ui_context.mu_context.style = &app.ui_context.mu_context._style

    new_font_size := app.ui_context.mu_context.style.font_size
    app.ui_context.mu_context.style.font = mu.Font(get_font(new_font_size))
}


compose_dev_panel :: proc(app: ^Application, container_state: ^UI_Panel) {
    PANEL_NAME :: "Dev Info"
    ctx := app.ui_context.mu_context

    @static first_open: bool = true
    if first_open {
        mu.get_container(ctx, PANEL_NAME).rect = container_state.rect
        first_open = false
    }
    mu.get_container(ctx, PANEL_NAME).open = b32(container_state.open)
    defer container_state.open = bool(mu.get_container(ctx, PANEL_NAME).open)
    if mu.begin_window(ctx, PANEL_NAME, {0,0, 300, 200}) {
        defer mu.end_window(ctx)
        ctn := mu.get_current_container(ctx)
        container_state.rect = ctn.rect
        app.ui_context.mouse_captured |= point_is_inside(ctn, app.mouse_pos)
        
        mu.layout_row(ctx, {-1})
        mu.label(ctx, fmt.tprintf("frametime: %.2f ms", get_frame_time()))
        mu.label(ctx, fmt.tprintf("MEM: %M", tracking_alloc.current_memory_allocated))
        mu.label(ctx, fmt.tprintf("CANVAS: %M", app.current_canvas.arena.total_used))
        mu.label(ctx, fmt.tprintf("canvas_size: %d x %d", app.current_canvas.size_px.x, app.current_canvas.size_px.y))
        mu.label(ctx, fmt.tprintf("tile_size: %d x %d", app.current_canvas.tile_size, app.current_canvas.tile_size))
        mu.label(ctx, fmt.tprintf("zoom: %.2f%%", view.scale*100))
        mu.label(ctx, fmt.tprintf("pivot: (%.2f, %.2f)", view.pivot_offset.x, view.pivot_offset.y))
        mu.label(ctx, fmt.tprintf("move: (%.2f, %.2f)", view.translation.x, view.translation.y))
        mu.label(ctx, fmt.tprintf("pen: %v", pen_mode))
        mu.label(ctx, fmt.tprintf("dab time: %v", metrics.time_per_dab))
        mu.label(ctx, fmt.tprintf("brush: %v (%v dabs)", metrics.brush_render, metrics.dab_count))
        mu.label(ctx, fmt.tprintf("canvas: %v", metrics.canvas_compose_time))
        mouse: [2]f32
        m_state := sdl.GetMouseState(&mouse.x, &mouse.y)
        mouse = view_to_canvas(&view, mouse)
        mousei := canvas.to_vec2i(mouse)
        mu.label(ctx, fmt.tprintf("canvas pos: (%d, %d)", mousei.x, mousei.y))


    }

}

point_is_inside :: proc(ctn: ^mu.Container, pos: [2]int) -> bool {
    rect := canvas.recti(ctn.rect)
    return canvas.rect_has_point(rect, pos)
}

compose_color_picker :: proc(app: ^Application, container_state: ^UI_Panel) {
    PANEL_NAME :: "Color Picker"
    SUBPANEL_WHEEL :: "Color Picker Wheel"
    ctx := app.ui_context.mu_context

    @static first_open: bool = true
    if first_open {
        mu.get_container(ctx, PANEL_NAME).rect = container_state.rect
        first_open = false
    }
    mu.get_container(ctx, PANEL_NAME).open = b32(container_state.open)
    defer container_state.open = bool(mu.get_container(ctx, PANEL_NAME).open)
    if mu.begin_window(ctx, PANEL_NAME, {200, 100, 300, 300}, {.NO_SCROLL, .ALIGN_CENTER}) {
        defer mu.end_window(ctx)
        ctn := mu.get_current_container(ctx)
        container_state.rect = ctn.rect
        app.ui_context.mouse_captured |= point_is_inside(ctn, app.mouse_pos)
        
        mu.layout_row(ctx, {-1})

        @static picked_hsl: color.HSL
        current_hsl := picked_hsl
        // if (current_hsl.h == 0) {
        //     current_hsl = {0.5, 0, 0.5}
        // }
        // if (current_hsl.l == 1) {
        //     current_hsl = {current_hsl.h, 0, 0.5}
        // }
        col_la := current_hsl
        col_la.l = 0
        col_lb := current_hsl
        col_lb.l = 1
        grad_l := gradient_2color_hsl(col_la,col_lb)

        l_change := mu.slider_gradient(ctx, &picked_hsl.l, 0, 1, grad_l, 0.0025)
        if .CHANGE in l_change {
            col_f = picked_hsl.l
        }
        slider_id := mu.get_id(ctx, uintptr(&picked_hsl.l))
        @static mouse_in_slider_l: bool
        mouse_in_slider_l = ctx.focus_id == slider_id
  
        


        fg_color := color.to_col8(app.fg_color)

        preview_color: mu.Color
        preview_color.r = fg_color.r
        preview_color.g = fg_color.g
        preview_color.b = fg_color.b
        preview_color.a = fg_color.a
        picker_pos: [2]i32
        @static picker_pos_rel: [2]f32
        
        mu.layout_row(ctx, {-1}, -(ctx.style.size.y + ctx.style.padding + ctx.style.spacing)*4 - ctx.style.footer_height)
        mu.begin_panel(ctx, SUBPANEL_WHEEL, {.EXPANDED})
        id := mu.get_id(ctx, SUBPANEL_WHEEL)
        
        @static test_mesh: render.UI_Mesh
        {
            spall.SCOPED_EVENT(&spall_ctx, &spall_buffer, "gen circle")
            test_mesh = render.gen_circle(64, 16, map_wheel_col_hsl)
        }
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
        picked_color := app.fg_color
        
              
        if .EYE_DROPPER not_in held && (ctx.focus_id == id && ctx.mouse_down_bits == {.LEFT}) || .CHANGE in l_change {
            picked_hsl = map_wheel_col_hsl_tohsl(picker_pos_rel)
            picked_color = map_wheel_col_hsl(picker_pos_rel)
            preview_color.r = u8(picked_color.r * 255)
            preview_color.g = u8(picked_color.g * 255)
            preview_color.b = u8(picked_color.b * 255)
            app.fg_color = picked_color
            
        }
        else {
            fgc_ok := color.srgb_to_okhsl(app.fg_color.rgb)
            col_f = fgc_ok.l
            if fgc_ok.h == 0 || fgc_ok.l == 1 {
                fgc_ok.h = picked_hsl.h
                fgc_ok.s = picked_hsl.s
            }
            picked_hsl = fgc_ok
            if !mouse_in_slider_l {
                poss := math2.polar_to_cart(fgc_ok.h * math.PI * 2, fgc_ok.s)
                poss = math2.clamp_circle(poss)
                // poss = (poss+1)/2
                picker_pos_rel = poss
            }
        }
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
            mu.layout_row(ctx, {40, -1})
            @static slider_r, slider_g, slider_b: f32
            slider_r = app.fg_color.r
            slider_g = app.fg_color.g
            slider_b = app.fg_color.b
            mu.label(ctx, "C")
            r := mu.layout_next(ctx)
            mu.draw_rect(ctx, r, preview_color)
            mu.label(ctx, "R")
            fg_ra := col_replace(app.fg_color, 0, 0)
            fg_rb := col_replace(app.fg_color, 0, 1)
            grad_r := gradient_2color(fg_ra, fg_rb)
            if .CHANGE in mu.slider_gradient(ctx, &slider_r, 0, 1, grad_r) {
                app.fg_color.r = slider_r
            }
            mu.label(ctx, "G")
            fg_ga := col_replace(app.fg_color, 1, 0)
            fg_gb := col_replace(app.fg_color, 1, 1)
            grad_g := gradient_2color(fg_ga, fg_gb)
            if .CHANGE in mu.slider_gradient(ctx, &slider_g, 0, 1, grad_g) {
                app.fg_color.g = slider_g
            }
            mu.label(ctx, "B")
            fg_ba := col_replace(app.fg_color, 2, 0)
            fg_bb := col_replace(app.fg_color, 2, 1)
            grad_b := gradient_2color(fg_ba, fg_bb)
            if .CHANGE in mu.slider_gradient(ctx, &slider_b, 0, 1, grad_b) {
                app.fg_color.b = slider_b
            }
    }
    // is_open^ = bool(mu.get_container(ctx, NAME).open)
}

col_replace :: proc(color: [$N]$T, $CH: int, replace_by: T) -> [N]T where CH >= 0 && CH < N{
    col := color
    col[CH] = replace_by
    return col
}

gradient_2color :: proc(color_a, color_b: [4]f32) -> color.Gradient {
    SAMPLES :: 12
    grad: color.Gradient
    grad.points = make([]color.GradientPoint, SAMPLES, context.temp_allocator)
    color_a := color.to_color(color_a)
    color_b := color.to_color(color_b)
    for i in 0..<SAMPLES {
        grad.points[i].position = f32(i)/(SAMPLES - 1)
        grad.points[i].color = math.lerp(color_a, color_b, f16(i)/(SAMPLES - 1))
    }
    return grad
}

gradient_2color_hsl :: proc(color_a, color_b: color.HSL) -> color.Gradient {
    SAMPLES :: 12
    grad: color.Gradient
    grad.points = make([]color.GradientPoint, SAMPLES, context.temp_allocator)
    for i in 0..<SAMPLES {
        t := f32(i)/(SAMPLES - 1)
        grad.points[i].position = t
        hsl_lerp: color.HSL
        hsl_lerp.h = math.lerp(color_a.h, color_b.h, t)
        hsl_lerp.s = math.lerp(color_a.s, color_b.s, t)
        hsl_lerp.l = math.lerp(color_a.l, color_b.l, t)
        srgba: color.Color32
        srgba.rgb = cast([3]f32)color.okhsl_to_srgb(hsl_lerp)
        srgba.a = 1
        grad.points[i].color = color.to_color(srgba)
    }
    return grad
}

compose_tool_settings :: proc(app: ^Application, container_state: ^UI_Panel) {
    PANEL_NAME :: "Tool Options"
    ctx := app.ui_context.mu_context

    @static first_open: bool = true
    if first_open {
        mu.get_container(ctx, PANEL_NAME).rect = container_state.rect
        first_open = false
    }
    mu.get_container(ctx, PANEL_NAME).open = b32(container_state.open)
    defer container_state.open = bool(mu.get_container(ctx, PANEL_NAME).open)
    if mu.begin_window(ctx, PANEL_NAME, {200, 100, 300, 300}, {.NO_SCROLL}) {
        defer mu.end_window(ctx)
        ctn := mu.get_current_container(ctx)
        container_state.rect = ctn.rect
        app.ui_context.mouse_captured |= point_is_inside(ctn, app.mouse_pos)
        
        BW := ctn.body.w/6 - 6
        mu.layout_row(ctx, {BW, BW, BW, BW, BW, -1}, i32(54*ctx.style.scale))

        for i in 0..<12 {
            b_type: string
            switch app.tool_data.presets[i].brush_mode {
                case .NORMAL:
                    b_type = "B"
                case .ERASE:
                    b_type = "E"
            }
            mu.begin_panel(ctx, "p", {.NO_SCROLL, .AUTO_SIZE,.ALIGN_CENTER})
            mu.layout_row(ctx, {-1}, i32(32*ctx.style.scale))
            if app.alt_tool_state.active && app.alt_tool_state.original_tool.alt_brush == i {
                mu.button(ctx, fmt.tprintf(">%s%d<", b_type, i+1))
            }
            else if app.tool_data.current_preset == i {
                mu.button(ctx, fmt.tprintf("(%s%d)", b_type, i+1))
            }
            else {
                if .SUBMIT in mu.button(ctx, fmt.tprintf("%s%d", b_type, i+1)) {
                    app.tool_data.presets[app.tool_data.current_preset] = g_tool_state
                    g_tool_state = app.tool_data.presets[i]
                    app.tool_data.current_preset = i
                }
            }
            lbl_rect := mu.layout_next(ctx)
            lbl_rect.y -= i32(ctx.style.scale*10)
            mu.layout_set_next(ctx, lbl_rect, false)
            if app.tool_data.current_preset == i {
                mu.label(ctx, fmt.tprintf("%s", g_tool_state.bound_layer))
            } else {
                mu.label(ctx, fmt.tprintf("%s", app.tool_data.presets[i].bound_layer))
            }
            mu.end_panel(ctx)
        }
        
        mu.layout_row(ctx, {i32(100*ctx.style.scale), -1})
        mu.layout_begin_column(ctx)
        mu.label(ctx, "Brush Size")
        mu.checkbox(ctx, "Pressure",  &g_tool_state.size_press)
        mu.layout_end_column(ctx)
        mu.layout_begin_column(ctx)
            mu.layout_row(ctx, {-1})
            @static size_fine: f32
            size_fine = g_tool_state._size
            mu.slider(ctx, &g_tool_state._size, 1, 1000, 1)
            if g_tool_state._size > 60 do size_fine = 60
            if g_tool_state._size <= 60 do size_fine = g_tool_state._size
            mu.slider(ctx, &size_fine, 1, 60, 1)
            if size_fine < 60 do g_tool_state._size = size_fine
        mu.layout_end_column(ctx)
        g_tool_state.size = int(g_tool_state._size)
  
        if .ACTIVE in mu.header(ctx, "Options") {
            mu.layout_row(ctx, {i32(100*ctx.style.scale), -1})
            if .SUBMIT in mu.button(ctx, Brush_Tip_Names[g_tool_state.brush_type]) {
                mu.open_popup(ctx, "tool_popup_tip")
            }
            popupctn := mu.get_container(ctx, "tool_popup_tip")
            if mu.popup(ctx, "tool_popup_tip") {
                mu.layout_row(ctx, {i32(130*ctx.style.scale)})
                for brush_tip in Brush_Tip {
                    if .SUBMIT in mu.button(ctx, Brush_Tip_Names[brush_tip]) {
                        g_tool_state.brush_type = brush_tip
                        g_tool_state.brush_tip_options = Brush_Tip_Opt_Map[brush_tip]
                        popupctn.open = false
                    }
                }
            }
            mu.layout_begin_column(ctx)
            switch &opt in g_tool_state.brush_tip_options {
                case Brush_Round_Pixel_Opt:
                case Brush_Round_Soft_Opt:
                    mu.layout_row(ctx, {i32(100*ctx.style.scale), -1})
                    mu.label(ctx, "softness")
                    mu.slider(ctx, &opt.feather, 0.01, 1)
                case Brush_Round_Feather_Opt:
                    mu.layout_row(ctx, {i32(100*ctx.style.scale), -1})
                    mu.label(ctx, "feather(px)")
                    mu.slider(ctx, &opt.feather_size, 1, 200, 1)
                case Brush_Round_Square_Opt:
            }
            mu.layout_end_column(ctx)

            mu.layout_row(ctx, {i32(120*ctx.style.scale), i32(100*ctx.style.scale)})
            mu.label(ctx, "Mode")
            if .SUBMIT in mu.button(ctx, fmt.tprintf("%s", g_tool_state.brush_mode)) {
                mu.open_popup(ctx, "tool_popup_mode")
            }
            mode_popup_ctn := mu.get_container(ctx, "tool_popup_mode")
            if mu.popup(ctx, "tool_popup_mode") {
                mu.layout_row(ctx, {i32(130*ctx.style.scale)})
                for mode_opt in canvas.Brush_Mode {
                    if .SUBMIT in mu.button(ctx, fmt.tprintf("%s", mode_opt)) {
                        g_tool_state.brush_mode = mode_opt
                        mode_popup_ctn.open = false
                    }
                }
            }
            mu.label(ctx, "Alt Brush")
            target_brush := app.tool_data.presets[g_tool_state.alt_brush]
            if .SUBMIT in mu.button(ctx, fmt.tprintf(">> B%d" if target_brush.brush_mode == .NORMAL else ">> E%d", g_tool_state.alt_brush + 1)) {
                mu.open_popup(ctx, "tool_popup_alt_brush")
            }
            btoggle_popup_ctn := mu.get_container(ctx, "tool_popup_alt_brush")
            if mu.popup(ctx, "tool_popup_alt_brush") {
                mu.layout_row(ctx, {i32(130*ctx.style.scale)})
                for b_id in 0..<len(app.tool_data.presets) {
                    b_type: string
                    switch app.tool_data.presets[b_id].brush_mode {
                        case .NORMAL:
                            b_type = "B"
                        case .ERASE:
                            b_type = "E"
                    }
                    if .SUBMIT in mu.button(ctx, fmt.tprintf(">> %s%d", b_type, b_id + 1)) {
                        g_tool_state.alt_brush = b_id
                        btoggle_popup_ctn.open = false
                    }
                }
            }
            mu.label(ctx, "Bound Layer")
            if .SUBMIT in mu.button(ctx, fmt.tprintf("%s", g_tool_state.bound_layer)) {
                mu.open_popup(ctx, "tool_popup_bound_layer")
            }
            boundlayer_popup := mu.get_container(ctx, "tool_popup_bound_layer")
            if mu.popup(ctx, "tool_popup_bound_layer") {
                mu.layout_row(ctx, {i32(130*ctx.style.scale)})
                for layer_kind in Layer_Kind {
                    
                    if .SUBMIT in mu.button(ctx, fmt.tprintf("%s", layer_kind)) {
                        g_tool_state.bound_layer = layer_kind
                        boundlayer_popup.open = false
                    }
                }
            }
            mu.layout_row(ctx, {i32(100*ctx.style.scale), i32(24*ctx.style.scale), -1})
            mu.label(ctx, "Opacity")
            mu.checkbox(ctx, "  opacity",  &g_tool_state.opacity_press)
            mu.slider(ctx, &g_tool_state.opacity, 0, 1, 0.01)
            mu.label(ctx, "Flow")
            mu.checkbox(ctx, "  flow",  &g_tool_state.flow_press)
            mu.slider(ctx, &g_tool_state.flow, 0, 1, 0.01)
            mu.label(ctx, "Step Ratio")
            mu.layout_next(ctx)
            mu.slider(ctx, &g_tool_state.step, 0.01, 2, 0.01)
            mu.checkbox(ctx, "Multisample", &g_tool_state.multisample)
            mu.layout_next(ctx)
            mu.slider(ctx, &g_tool_state.multisample_range, 0.0, 100, 1)
            mu.layout_row(ctx, {ctn.body.w/3, ctn.body.w/3, -1})
            
        }


        ctn.rect.h = ctn.content_size.y + ctx.style.title_height + ctx.style.footer_height + ctx.style.padding + 1

    }
    // is_open^ = bool(mu.get_container(ctx, NAME).open)
}

compose_main :: proc(app: ^Application) {
    NAME :: "Main Panel"
    ctx := app.ui_context.mu_context
    mu.get_container(ctx, NAME).rect = {0,0, i32(app.window_size.x), 40}
    mu.begin_window(ctx, NAME,{0,0, i32(app.window_size.x), 40}, {.NO_RESIZE, .NO_TITLE, .NO_CLOSE, .NO_SCROLL})
    defer mu.end_window(ctx)
    ctn := mu.get_current_container(ctx)
    app.ui_context.mouse_captured |= point_is_inside(ctn, app.mouse_pos)

    mu.layout_row(ctx, {100, 100, 100, 100, 60, 300, 60, 60, 60, 100, 100, 200})

    if .SUBMIT in mu.button(ctx, "Q. Save") {
        save_img(app.current_canvas.composite_layer)
    }

    if .SUBMIT in mu.button(ctx, "New") {
        free_canvas(app)
        setup_canvas(app, CANVAS_SIZE)
    }

    PANELS :: "PANELS"
    if .SUBMIT in mu.button(ctx, PANELS) {
        mu.open_popup(ctx, PANELS)
    }
    if mu.begin_popup(ctx, PANELS) {
        defer mu.end_popup(ctx)
        mu.checkbox(ctx, "Color Picker", &app.ui_state.color_picker.open)
        mu.checkbox(ctx, "Devvy", &app.ui_state.dev_panel.open)
        mu.checkbox(ctx, "Brush", &app.ui_state.tool_options.open)
    }

    if .CHANGE in mu.slider(ctx, &user_scaling, 0.5, 2.0, 0.1) {
        scale_ui(app)
    }

    mu.label(ctx, "zoom:")
    if .CHANGE in mu.slider(ctx, &view.scale, 0.05, 6, 0.01) {
        canvas_center: [2]f32
        canvas_center.x = f32(app.window_size.x/2)
        canvas_center.y = f32(app.window_size.y/2)
        view_set_pivot(&view, canvas_center)
    }
    if .SUBMIT in mu.button(ctx, "0.5X") {
        view.scale = 0.5
    }
    if .SUBMIT in mu.button(ctx, "1X") {
        view.scale = 1.0
    }
    if .SUBMIT in mu.button(ctx, "2X") {
        view.scale = 2.0
    }

    if .SUBMIT in mu.button(ctx, "fit canvas") {
        view_fit(&view, canvas.to_vec2f(app.current_canvas.size_px))
    }

    mu.label(ctx, "pen sens:")
    mu.slider(ctx, &f_pen_sens, 0, 2)

    


}