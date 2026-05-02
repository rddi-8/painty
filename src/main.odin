package main

import "core:thread"
import "core:time"
import "core:math/linalg"
import "core:slice"
import "core:os"
import "core:encoding/json"

import "core:math"
import "core:math/rand"
import "core:log"
import "base:runtime"
import "core:c"
import "vendor:sdl3/ttf"
import "core:mem"
import "core:fmt"
import sdl "vendor:sdl3"
import "core:prof/spall"
import "core:sync"

import mu "microui"
import "render"
import "color"
import "math2"
import "canvas"

DEBUG_PRINT :: false
spall_ctx: spall.Context
@(thread_local) spall_buffer: spall.Buffer

SPALLINF :: struct {
    spall_ctx: ^spall.Context,
    spall_buffer: ^spall.Buffer,
}
spall_inf: SPALLINF = {
    spall_ctx = &spall_ctx,
    spall_buffer = &spall_buffer,
}

WINDOW_W :: 1300
WINDOW_H :: 800

RES_FONT :: "fonts/DroidSans.ttf"
RES_ICON_ATLAS :: "fonts/icons.png"


Color :: [4]f32
Vec2 :: [2]f32

tracking_alloc: mem.Tracking_Allocator

Transform :: linalg.Matrix3x3f32

Text_Renderer :: struct {
    text_engine: ^ttf.TextEngine,
}

UI_Panel :: struct {
    open: bool,
    rect: mu.Rect,
}
UI_State :: struct {
    color_picker: UI_Panel,
    tool_options: UI_Panel,
    dev_panel: UI_Panel,
}
Application :: struct {
    window: ^sdl.Window,
    window_size: [2]int,
    mouse_pos: [2]int,
    ui_context: ^Ui_Context,
    render_info: ^render.Render_Info,
    text_renderer: ^Text_Renderer,
    ui_state: UI_State,
    fg_color: Color,
    current_canvas: ^canvas.Canvas
}

pen_mode: bool = false
pen_id: sdl.PenID

BRUSH_SIZE :: 16
g_tool_state: ToolState = {
    _size = 16,
    size = 16,
    flow = 1,
    opacity = 1,
    step = 0.05
}
f_pen_state: PenState
f_stroke: ^Stroke_Buffer
f_stroke_dist_accum: f32

sdl_cursor_crosshair: ^sdl.Cursor

pen_motion :[dynamic][2]f32
dabs_c: int

drag_tool: bool

mouse_just_pressed: bool
view: Canvas_View

font_cache: map[f32]^ttf.Font

main_context: runtime.Context

held: ^Held_Actions

timer: u64
last_frame: u64

user_scaling: f32 = 1.0

col_f: f32

map_wheel_col :: proc "contextless" (pos: [2]f32) -> [4]f32 {
    angle, l := math2.cart_to_polar(pos)
    lab_c: color.Lab
    lab_c.L = col_f
    lab_c.a = pos.x*0.3
    lab_c.b = pos.y*0.3

    col: [4]f32
    col.rgb = ([3]f32)(color.to_srgb(([3]f32)(color.oklab_to_linear_srgb(lab_c))))
    if (col.r < 0.0 || col.g < 0.0 || col.b < 0.0 || col.r >1 || col.g > 1 || col.b > 1){
        return {0.5,0.5,0.5, 1.0}
    }
    col.a = 1

    return col
}

// map_wheel_col_hsl :: proc "contextless" (pos: [2]f32) -> [4]f32 {
//     angle, l := math2.cart_to_polar(pos)
//     okhsl: color.HSL
//     okhsl.l = angle / (math.PI*2)
//     okhsl.h = l
//     okhsl.s = col_f


//     col: [4]f32
//     col.rgb = ([3]f32)(color.okhsl_to_srgb(okhsl))
//     if (col.r < 0.0 || col.g < 0.0 || col.b < 0.0 || col.r >1 || col.g > 1 || col.b > 1){
//         return {0.5,0.5,0.5, 1.0}
//     }
//     col.a = 1

//     return col
// }

map_wheel_col_hsl :: proc "contextless" (pos: [2]f32) -> [4]f32 {
    angle, l := math2.cart_to_polar(pos)
    okhsl: color.HSL
    okhsl.l = col_f
    okhsl.h = angle / (math.PI*2)
    okhsl.s = l*0.99


    col: [4]f32
    col.rgb = ([3]f32)(color.okhsl_to_srgb(okhsl))
    if (col.r < 0.0 || col.g < 0.0 || col.b < 0.0 || col.r >1 || col.g > 1 || col.b > 1){
        return {0.5,0.5,0.5, 1.0}
    }
    col.a = 1

    return col
}

get_frame_time :: proc() -> f32 {
    return f32(f64(last_frame)/1000000)
}

main :: proc() {
    // spall_ctx = spall.context_create("trace_test.spall")
	// defer spall.context_destroy(&spall_ctx)
	// buffer_backing := make([]u8, spall.BUFFER_DEFAULT_SIZE)
	// defer delete(buffer_backing)
	// spall_buffer = spall.buffer_create(buffer_backing, u32(sync.current_thread_id()))
	// defer spall.buffer_destroy(&spall_ctx, &spall_buffer)
    // context.user_ptr = &spall_inf


    mem.tracking_allocator_init(&tracking_alloc, context.allocator)
    defer mem.tracking_allocator_destroy(&tracking_alloc)
    context.allocator = mem.tracking_allocator(&tracking_alloc)

    context.logger = log.create_console_logger()
    // context.logger.lowest_level = .Warning

    sdl.SetLogPriorities(.VERBOSE)
    main_context =  context
    sdl.SetLogOutputFunction(proc "c" (userdata: rawptr, category: sdl.LogCategory, priority: sdl.LogPriority, message: cstring) {
        context = main_context
        if (priority == .ERROR) {
            panic("ooops")
        }
        log.debugf("SDL {} [{}]: {}", category, priority, message)
    }, nil)
    
    

    //TODO remove temp canvas stuff
    main_canvas := canvas.make_canvas({256*20, 256*20})
    
    start := time.now()
    // for t in main_canvas.composite_layer.tiles.data
    // {
    //     iter := canvas.view_iter(&t.pixels)
    //     for px, coord in canvas.view_iterate_ptr(&iter) {
    //         uv := canvas.to_vec2f(coord)/canvas.to_vec2f(main_canvas.tile_size)
    //         px^ = {f16(uv.x), f16(uv.y), 0.5, 1.0}
    //     }

    // }

    brush_px := make([]f32, 1024*1024)
    brush := canvas.generate_round(brush_px, g_tool_state.size)

    fillcol := make([dynamic]canvas.Pixel,main_canvas.tile_size*main_canvas.tile_size)
    w := main_canvas.tile_size
    s := main_canvas.tile_size
    for i in 0..<main_canvas.tile_size*main_canvas.tile_size {
        x := i % w
        y := i / w
        uv := canvas.to_vec2f({x, y})/canvas.to_vec2f(main_canvas.tile_size)
        fillcol[i] = {f16(uv.x), f16(uv.y), 0.5, 1.0}
    }

    f_stroke = sb_make(100)

    tile_iter := canvas.view_iter(&main_canvas.tiles_rect)

    brush_rect := canvas.recti({999, 777}, {g_tool_state.size, g_tool_state.size})

    // for tile_rect, coord, idx in canvas.view_iterate(&tile_iter)
    // {
    //     tiles := main_canvas.composite_layer.tiles.data
    //     tile_px := tiles[idx].pixels.data
    //     // iter := canvas.view_iter(&t.pixels)
    //     // for px, coord in canvas.view_iterate_ptr(&iter) {
    //     //     uv := canvas.to_vec2f(coord)/canvas.to_vec2f(main_canvas.tile_size)
    //     //     px^ = {f16(uv.x), f16(uv.y), 0.5, 1.0}
    //     // }
    //     // w := t.pixels.width
    //     // s := main_canvas.tile_size
    //     for pi in 0..<len(tile_px) {
    //         // coord := canvas.view_get_point(t.pixels.view, pi)
    //         // uv := canvas.to_vec2f(coord)/canvas.to_vec2f(main_canvas.tile_size)
    //         // t.pixels.data[pi] = {f16(uv.x), f16(uv.y), 0.5, 1.0}
    //         tile_px[pi] = fillcol[pi]
    //     }

    //     overlap := canvas.rect_intersect(tile_rect, brush_rect)

        
    //     if (!canvas.rect_is_empty(overlap)) {
    //         tb_overlap := canvas.view_overlap(tile_rect, brush_rect)
    //         bt_overlap := canvas.view_overlap(brush_rect, tile_rect)
    //         tb_data := canvas.DataView(canvas.Pixel){
    //             view = tb_overlap,
    //             data = tiles[idx].pixels.data
    //         }
    //         bt_data := canvas.DataView(canvas.Pixel){
    //             view = bt_overlap,
    //             data = brush.data
    //         }

    //         fmt.printfln("Tile idx: %v overlaps brush: tile(%v) overlap(%v)", idx, tile_rect.pos_size, overlap.pos_size)
    //         fmt.printfln("tb overlap: %v", tb_overlap)
    //         fmt.printfln("bt overlap: %v", bt_overlap)
    //         fmt.printfln("size: %v == %v", canvas.view_size(tb_overlap), canvas.view_size(bt_overlap))
    //         tb_iter := canvas.view_iter(&tb_data)
    //         bt_iter := canvas.view_iter(&bt_data)

    //         width := tb_data.width
    //         for t, b, row_n in canvas.view_iterate_rows_dual(&tb_iter, &bt_iter) {
    //             for i in 0..<width {
    //                 t[i].rgb = t[i].rgb*(1 - b[i].a) + b[i].rgb*b[i].a
    //             }
    //         }
        
    //     }


    // }
    end := time.now()
    fmt.printfln("fill time: %v", time.diff(start, end))
    

    
    //TODO remove
    test_mesh := render.gen_circle(8,3, map_wheel_col)
    
    app := new(Application)
    init_app(app, WINDOW_W, WINDOW_H, "Painty")

    sdl_cursor_crosshair = sdl.CreateSystemCursor(.CROSSHAIR)
    if (sdl_cursor_crosshair == nil) do fmt.printfln("CURSOR ERROR: %v", sdl.GetError())
    ok := sdl.SetCursor(sdl_cursor_crosshair); assert(ok)
    
    app.current_canvas = main_canvas
    tile_array, terr := render.create_tile_array(app.render_info, main_canvas.tile_size, len(main_canvas.composite_layer.tiles.data))

    //FIXME this is here for now
    view.scale = 1
    view.screen = {f32(app.window_size.x), f32(app.window_size.y)}
    view_fit(&view, {f32(main_canvas.size_px.x), f32(main_canvas.size_px.y)})

    //TODO remove tile thingy
    // tt, tte := render.create_tile_atlas(app.render_info, layer.tile_size, len(layer.tiles))

   

    // fmt.printfln("canvas tiles = %v, atlas_tiles = %v", len(layer.tiles), len(tt.tiles))

    
    
    action_binds := new(Action_Binds)
    create_default_keybinds(action_binds)
    add_keybind(&action_binds.key_binds, Input_Event_Key{ctx = .PAINTING, key = .C}, 
        Action_BoolToggle{ value = &app.ui_state.color_picker.open})
    

    current_context := InputContext.PAINTING

    actions: [dynamic]Action
    held_actions: Held_Actions
    just_pressed_actions: Held_Actions
    just_released_actions: Held_Actions
    held = &held_actions

 
    vbuff := render.create_vbuffer(app.render_info.device, {.VERTEX}, 30 * mem.Megabyte)
    
    idxbuff := render.create_vbuffer(app.render_info.device, {.INDEX}, 30 * mem.Megabyte)

    tilebuff := render.create_vbuffer(app.render_info.device, {.VERTEX}, 10 * mem.Megabyte)

    buncha_tiles: [dynamic]render.Vertex_Data_Tile
    arr_layer: u32 = 0
    composite_layer := main_canvas.composite_layer
    for tile in main_canvas.tiles_rect.data {
        ensure(int(arr_layer) < tile_array.array_size, "Messed up texture array size")
        pos: [2]f32 = canvas.to_vec2f(tile.pos)
        size: [2]f32 = canvas.to_vec2f(tile.size)
        q := render.make_quad_t(pos, pos + size, arr_layer)
        for v in q {
            append(&buncha_tiles, v)
        }
        // fmt.printfln("[%v]tile pos: %v", arr_layer, tile.pos)
        arr_layer += 1
    }
    for ttt in buncha_tiles {

        // fmt.println(ttt)
    }

    tilebffr, tlvberr := render.vbuffer_reserve(tilebuff, u32(len(buncha_tiles) * size_of(render.Vertex_Data_Tile)))
    if tlvberr != nil {
        log.error(tlvberr)
    }

    cpds := []render.Copy_Description{
        {
            src = {ptr = raw_data(buncha_tiles), size = u32(len(buncha_tiles) * size_of(render.Vertex_Data_Tile))},
            dst = tilebffr
        }
    }
    ttbuffer := sdl.CreateGPUTransferBuffer(app.render_info.device, {
        size = u32(main_canvas.tile_size * main_canvas.tile_size * size_of(canvas.Pixel)),
        usage = .UPLOAD,
    })
    render.vbuffer_batch_copy(app.render_info, cpds[:])

    { //populate texture
        arr_layer: u32 = 0
        cmd := sdl.AcquireGPUCommandBuffer(app.render_info.device)
        copy_pass := sdl.BeginGPUCopyPass(cmd)
        for tile in composite_layer.tiles.data {
            tile_size := main_canvas.tile_size
            //FIXME: don't allocate million cycled transfer buffers
            tb := sdl.MapGPUTransferBuffer(app.render_info.device, ttbuffer, true)
            mem.copy_non_overlapping(tb, raw_data(tile.pixels.data), tile_size * tile_size * size_of(canvas.Pixel))
            sdl.UnmapGPUTransferBuffer(app.render_info.device, ttbuffer)
            
            sdl.UploadToGPUTexture(copy_pass,
            {
                transfer_buffer = ttbuffer
            },
            {
                layer = arr_layer,
                d = 1,
                w = u32(tile_size),
                h = u32(tile_size),
                texture = tile_array.backing_texture
            }, false)
            arr_layer += 1
        }
        sdl.EndGPUCopyPass(copy_pass)
        ok := sdl.SubmitGPUCommandBuffer(cmd)
    }



    



    
    ww, wh :c.int
    sdl.GetWindowSize(app.window, &ww, &wh)
    render.create_render_target(app.render_info, u32(ww), u32(wh))

    // pen_motion := make([dynamic][2]f32)


    main_loop: for {
        last_frame = sdl.GetTicksNS() - timer
        // fmt.printfln("%.2f ms", f64(last_frame)/1000000)
        timer = sdl.GetTicksNS()
        
        //MARK: EVENTS
        keybind_map := action_binds.key_binds
        mouse_map := action_binds.mouse_binds
        pen_map := action_binds.pen_binds

        clear(&pen_motion)

        fff: canvas.RectF
        
        mouse_just_pressed = false
        clear(&actions)
        ev: sdl.Event
        for sdl.PollEvent(&ev) {
            #partial switch ev.type {
                case .WINDOW_DISPLAY_SCALE_CHANGED:
                    scale_ui(app)
                    scaling := sdl.GetWindowDisplayScale(app.window)
                    fmt.printfln("new display scaling = {}", scaling)
                case .WINDOW_RESIZED:
                    ww, wh :c.int
                    sdl.GetWindowSize(app.window, &ww, &wh)
                    render.create_render_target(app.render_info, u32(ww), u32(wh))
                    app.window_size = {int(ww), int(wh)}
                case .QUIT:
                    log.debug("SDL QUIT")
                    break main_loop
                case .KEY_DOWN: //MARK: key down
                    keymod := ev.key.mod
                    keymod = keymod - {.NUM, .CAPS, .MODE, .SCROLL}
                    if len(keybind_map[ev.key.scancode]) > 0 {
                        kb_loop: for kb in keybind_map[ev.key.scancode] {
                            if !kb.key_event.use_repeat && ev.key.repeat {
                                continue kb_loop
                            }
                            if kb.key_event.ctx != current_context {
                                continue kb_loop
                            }
                            if kb.key_event.ignore_mod || kb.key_event.mod == keymod {
                                append(&actions, kb.action)
                            }
                        }
                    }
                case .KEY_UP: //MARK: key up
                    if len(keybind_map[ev.key.scancode]) > 0 {
                        for kb in keybind_map[ev.key.scancode] {
                            if a, ok := kb.action.(Action_Held); ok {
                                a.up = true
                                append(&actions, a)
                            }
                        }
                    }
                case .MOUSE_MOTION: //MARK: mouse motion
                    mu.input_mouse_move(app.ui_context.mu_context, i32(ev.motion.x), i32(ev.motion.y))
                    if !pen_mode {
                        f_pen_state.screen_position = {ev.motion.x, ev.motion.y}
                        f_pen_state.timestamp = ev.pmotion.timestamp
                    }
                case .MOUSE_BUTTON_UP: //MARK: mb up
                    mu_mouse: mu.Mouse
                    switch ev.button.button {
                        case sdl.BUTTON_LEFT:
                            mu_mouse = mu.Mouse.LEFT
                        case sdl.BUTTON_RIGHT:
                            mu_mouse = mu.Mouse.RIGHT
                        case sdl.BUTTON_MIDDLE:
                            mu_mouse = mu.Mouse.MIDDLE
                    }
                    mu.input_mouse_up(app.ui_context.mu_context, i32(ev.motion.x), i32(ev.motion.y), mu_mouse)
                    
                    mbtn: Maybe(Mouse_Button) = nil
                    switch ev.button.button {
                        case sdl.BUTTON_LEFT:
                            mbtn = .LEFT
                        case sdl.BUTTON_RIGHT:
                            mbtn = .RIGHT
                        case sdl.BUTTON_MIDDLE:
                            mbtn = .MIDDLE
                        case sdl.BUTTON_X1:
                            mbtn = .MBT_4
                        case sdl.BUTTON_X2:
                            mbtn = .MBT_5
                    }

                    if mbtn != nil && len(mouse_map[mbtn.(Mouse_Button)]) > 0 {
                        for mb in mouse_map[mbtn.(Mouse_Button)] {
                            if mb.mouse_event.up == true {
                                append(&actions, mb.action)
                            }
                            if a, ok := mb.action.(Action_Held); ok {
                                a.up = true
                                append(&actions, a)
                            }
                        }
                    }

                case .MOUSE_BUTTON_DOWN: //MARK: mb down
                    mu_mouse: mu.Mouse
                    switch ev.button.button {
                        case sdl.BUTTON_LEFT:
                            mu_mouse = mu.Mouse.LEFT
                        case sdl.BUTTON_RIGHT:
                            mu_mouse = mu.Mouse.RIGHT
                        case sdl.BUTTON_MIDDLE:
                            mu_mouse = mu.Mouse.MIDDLE
                    }
                    mu.input_mouse_down(app.ui_context.mu_context, i32(ev.motion.x), i32(ev.motion.y), mu_mouse)
                    
                    mbtn: Maybe(Mouse_Button) = nil
                    mouse_just_pressed = true
                    switch ev.button.button {
                        case sdl.BUTTON_LEFT:
                            mbtn = .LEFT
                        case sdl.BUTTON_RIGHT:
                            mbtn = .RIGHT
                        case sdl.BUTTON_MIDDLE:
                            mbtn = .MIDDLE
                        case sdl.BUTTON_X1:
                            mbtn = .MBT_4
                        case sdl.BUTTON_X2:
                            mbtn = .MBT_5
                    }

                    if mbtn != nil && len(mouse_map[mbtn.(Mouse_Button)]) > 0 {
                        for mb in mouse_map[mbtn.(Mouse_Button)] {
                            if mb.mouse_event.up == false {
                                append(&actions, mb.action)
                            }
                        }
                    }
                //MARK: pen
                case .PEN_PROXIMITY_IN:
                    pen_mode = true
                    pen_id = ev.pproximity.which
                case .PEN_PROXIMITY_OUT:
                    pen_mode = false
                    
                case .PEN_AXIS:
                    if pen_mode && pen_id == ev.pmotion.which {
                        #partial switch ev.paxis.axis {
                            case .PRESSURE :
                                f_pen_state.pressure = ev.paxis.value
                        }
                    }
                case .PEN_MOTION:
                    if pen_mode && pen_id == ev.pmotion.which {
                        pen_pos: [2]f32 = {ev.pmotion.x, ev.motion.y}
                        f_pen_state.screen_position = {ev.pmotion.x, ev.pmotion.y}
                        f_pen_state.timestamp = ev.pmotion.timestamp
                    }
            }
        }

        
        just_pressed_actions = {}
        just_released_actions = {}

        //MARK: ACTIONS
        for action in actions {
            switch a in action {
                case Action_Simple:
                    log.debug("Action:", a.type)
                    #partial switch a.type {
                        case .QUIT:
                            break main_loop
                    }
                case Action_Parameter:
                    log.debug("Parameter Action:", a.type, "value:", a.value)
                    #partial switch a.type {
                        case .ROTATE_CANVAS:
                            mouse: [2]f32
                            m_state := sdl.GetMouseState(&mouse.x, &mouse.y)
                            view_set_pivot(&view, mouse)
                            view_rotate(&view, math.to_radians(a.value))
                        case .ZOOM_CANVAS:
                            mouse: [2]f32
                            m_state := sdl.GetMouseState(&mouse.x, &mouse.y)
                            view_set_pivot(&view, mouse)
                            view_scale(&view, a.value)
                        case .SET_CANVAS_ZOOM:
                            mouse: [2]f32
                            view.scale = a.value
                        case .TOOL_SIZE_SCALING:
                            g_tool_state._size = math.ceil(g_tool_state._size*a.value)
                            if g_tool_state._size <= 2.5 && a.value > 1 {
                                g_tool_state._size = 3
                            }
                            
                        case .TOOL_SIZE_FLAT:
                            g_tool_state._size += math.ceil(a.value)
                        case .TOOL_SIZE_SET:
                            g_tool_state._size = math.ceil(a.value)
                    }
                case Action_Canvas_Location:
                    log.debug("Canvas Location Action:", a.type, "loc:", a.location)
                case Action_ToolToggle:
                    log.debug("Toggle Tool Action:", "tool_id:", a.tool_id)
                case Action_Held:
                    if !a.up {
                        held_actions += {a.type}
                        just_pressed_actions += {a.type}
                    }
                    else {
                        held_actions -= {a.type}
                        just_released_actions -= {a.type}
                    }
                    log.debug("Held Action:", a.type, "up:", a.up)
                case Action_BoolToggle:
                    a.value^ = !a.value^
            }
        }

        view.screen = {f32(app.window_size.x), f32(app.window_size.y)}
        f_pen_state.canvas_position = view_to_canvas(&view, f_pen_state.screen_position)


        mousepos: [2]f32
        mstate := sdl.GetMouseState(&mousepos.x, &mousepos.y) 
        app.mouse_pos = canvas.to_vec2i(mousepos)

        if .PAN_CANVAS in held_actions {
            mousepos: [2]f32
            mrel := sdl.GetRelativeMouseState(&mousepos.x, &mousepos.y)
            if .LEFT in mrel {
                view_tr := view_transform(&view)
                rel_m: [3]f32
                rel_m.xy = 2*mousepos/canvas.to_vec2f(app.window_size)
                rel_m.y *= -1
                rel_m = linalg.inverse(view_tr) * rel_m
                view_translate(&view, -rel_m.xy)
            }
        }

        {
            muctx := app.ui_context.mu_context
            mu.begin(muctx)
            app.ui_context.mouse_captured = false 
            compose_main(app)
            compose_color_picker(app, &app.ui_state.color_picker)
            compose_dev_panel(app, &app.ui_state.dev_panel)
            compose_tool_settings(app, &app.ui_state.tool_options)


            mu.end(muctx)
        }

        

        if app.ui_context.mouse_captured {
            ok := sdl.SetCursor(sdl.GetDefaultCursor()); assert(ok)
            ok = sdl.ShowCursor(); assert(ok)
            if .PAINT in just_pressed_actions {
                just_pressed_actions -= {.PAINT}
                held_actions -= {.PAINT}
            }
        }
        else {
            if pen_mode {
                ok := sdl.HideCursor(); assert(ok)
            }
            ok := sdl.SetCursor(sdl_cursor_crosshair); assert(ok)
        }
        



        //MARK: update view
        

        stroke_point := Stroke_Point{
            canvas_pos = f_pen_state.canvas_position,
            color = app.fg_color,
            time = f_pen_state.timestamp,
        }
        if pen_mode && (g_tool_state.size_press) {
            stroke_point.size = int(f_pen_state.pressure * f32(g_tool_state.size))
        }
        else {
            stroke_point.size = g_tool_state.size
        }

        if pen_mode && (g_tool_state.opacity_press) {
            stroke_point.alpha = f_pen_state.pressure * g_tool_state.opacity
        }
        else {
            stroke_point.alpha = g_tool_state.opacity
        }

        if .PAINT in held_actions && .PAN_CANVAS not_in held_actions {
            sb_push(f_stroke, stroke_point)
        }
        else {
            sb_clear(f_stroke)
            f_stroke_dist_accum = 0
        }



        if .EYE_DROPPER in held_actions {
            mouse: [2]f32
            m_state := sdl.GetMouseState(&mouse.x, &mouse.y)
            mouse = view_to_canvas(&view, mouse)
            mousei := canvas.to_vec2i(mouse)

            tile_pos := canvas.match_tile_pos(main_canvas, mousei)
            tile_idx := canvas.view_get_index(composite_layer.tiles.view, tile_pos)
            tile := composite_layer.tiles.data[tile_idx]
            mousei.x = mousei.x %% tile.pixels.width
            mousei.y = mousei.y %% tile.pixels.width
            px_idx := canvas.view_get_index(tile.pixels.view, mousei)
            app.fg_color = color.to_col32(tile.pixels.data[px_idx])
        }

        {
            brush_apply :: proc(buffer: []f32, layer: canvas.Layer, sp: Stroke_Point) {
                @static size: int = 0
                @static brush: canvas.DataView(f32)
                if sp.size != size {
                    brush = canvas.generate_round(buffer, sp.size)
                    size = sp.size
                }
                brush_rect := canvas.RectI{
                    pos_size = {pos = canvas.to_vec2i(sp.canvas_pos) - sp.size/2, size = sp.size}
                }
                canvas.brush_dab(brush, brush_rect, sp.color, sp.alpha, layer)
            }
            if .PAINT in held_actions {
                current, err1 := sb_get(f_stroke, 0)
                last, err2 := sb_get(f_stroke, 1)
                if (f_stroke.length <= 1) {
                    brush_apply(brush_px, composite_layer, current)
                }
                else {
                    distance := linalg.distance(current.canvas_pos, last.canvas_pos)
                    size_min := min(current.size, last.size)
                    step := max(g_tool_state.step * f32(size_min), 1)
                    for d: f32 = max(step - f_stroke_dist_accum, 0); d < distance; d += step {

                        s_point := stroke_interpolate(last, current, d / distance) if distance > 0 else current

                        brush_apply(brush_px, composite_layer, s_point)
                        f_stroke_dist_accum = distance - d
                    }
                    f_stroke_dist_accum += distance
                }

                
            }
        }
        // view_fit(&view, {f32(main_canvas.size.x), f32(main_canvas.size.y)})

        { //update texture
            arr_layer: u32 = 0
            cmd := sdl.AcquireGPUCommandBuffer(app.render_info.device)
            copy_pass := sdl.BeginGPUCopyPass(cmd)
            tile_iter := canvas.view_iter(&main_canvas.tiles_changed)
            for changed, coord, idx in canvas.view_iterate(&tile_iter) {
                if changed {
                    // fmt.printfln("uppy %v", idx)
                    tile_size := main_canvas.tile_size
                    tile := main_canvas.composite_layer.tiles.data[idx]
                    //FIXME: don't allocate million cycled transfer buffers
                    tb := sdl.MapGPUTransferBuffer(app.render_info.device, ttbuffer, true)
                    mem.copy_non_overlapping(tb, raw_data(tile.pixels.data), tile_size * tile_size * size_of(canvas.Pixel))
                    sdl.UnmapGPUTransferBuffer(app.render_info.device, ttbuffer)
                    
                    sdl.UploadToGPUTexture(copy_pass,
                    {
                        transfer_buffer = ttbuffer
                    },
                    {
                        layer = u32(idx),
                        d = 1,
                        w = u32(tile_size),
                        h = u32(tile_size),
                        texture = tile_array.backing_texture
                    }, false)
                }
            }
            sdl.EndGPUCopyPass(copy_pass)
            ok := sdl.SubmitGPUCommandBuffer(cmd)
        }
        canvas.canvas_reset_tile_state(main_canvas) 
        
       


        

        render.vbuffer_reset(vbuff)
        render.vbuffer_reset(idxbuff)

        {
            uniform_data := render.VUB{
                camera = render.align_matrix3(view_transform(&view)),
                width = main_canvas.size_px.x,
                height = main_canvas.size_px.y,
                tile_size = main_canvas.tile_size,
            }
            render.render_canvas(app.render_info, tile_array.backing_texture, u32(len(buncha_tiles)), &tilebffr, uniform_data, .CLEAR)
            render_ui(app.ui_context, app, vbuff, idxbuff)
            render.present(app.render_info)
        }
        
        when DEBUG_PRINT do fmt.print(fmt.tprintfln("MEM: %M", tracking_alloc.current_memory_allocated))
        
        free_all(context.temp_allocator)

        evtm := sdl.WaitEventTimeout(nil, -1)
    }

   

    sdl.Quit()
    save_ui_state(app)
    
}

save_ui_state :: proc(app: ^Application) {
    log.info("Saving ui state")
    if json_data, json_err := json.marshal(app.ui_state, allocator = context.temp_allocator); json_err == nil {
        write_err := os.write_entire_file("ui_state.conf.json", json_data)
        if write_err != nil {
            log.errorf("Couldn't save ui state! Error: %v", write_err)
        }
    } else {
        log.errorf("Couldn't save ui state! Error: %v", json_err)
    }
}

load_ui_state :: proc(app: ^Application) {
    log.info("Loading ui state")
    if json_data, json_err := os.read_entire_file("ui_state.conf.json", context.temp_allocator); json_err == nil {
        loaded_state: UI_State

        if unmarshal_err := json.unmarshal(json_data, &loaded_state); unmarshal_err == nil {
            app.ui_state = loaded_state
            log.info("Loaded previous ui state from \"ui_state.conf.json\"")
        } else {
            log.errorf("Failed to load previous ui state. Error: %v", unmarshal_err)
        }
    } else {
        log.debug("Failed to read \"ui_state.conf.json\". Error: &v", json_err)
    }
}

init_app :: proc(application: ^Application, window_w, window_h: int, name: cstring) {
    
    if !sdl.Init({.VIDEO}) do print_sdl_err()
    if !ttf.Init() do print_sdl_err()

    displays: [^]sdl.DisplayID
    display_count: i32
    displays = sdl.GetDisplays(&display_count)
    window_bounds: sdl.Rect
    sdl.GetDisplayBounds(displays[0], &window_bounds)
    application.window = sdl.CreateWindow(name, c.int(window_w), c.int(window_h), {.RESIZABLE})
    if application.window == nil do print_sdl_err()

    application.window_size = {window_w, window_h}
    sdl.SetWindowPosition(application.window, window_bounds.x + 500, window_bounds.y + 500)

    application.render_info = new(render.Render_Info)
    render.init(application.window, application.render_info)

    application.text_renderer = new(Text_Renderer)
    application.text_renderer.text_engine = ttf.CreateGPUTextEngine(application.render_info.device)

    load_ui_state(application)
   
    application.ui_context = new(Ui_Context)
    ui_init(application.ui_context, application.render_info)
}

print_sdl_err :: proc() {
    fmt.printfln("SDL Error: {}", sdl.GetError())
}
