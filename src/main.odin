package main

import "vendor:sdl3/image"
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

CANVAS_SIZE :: [2]int{256*15, 256*15}

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

Tool_Data :: struct {
    presets: [12]ToolState,
    current_preset: int,
}
Application :: struct {
    window: ^sdl.Window,
    window_size: [2]int,
    window_position: [2]c.int,
    mouse_pos: [2]int,
    ui_context: ^Ui_Context,
    render_info: ^render.Render_Info,
    text_renderer: ^Text_Renderer,
    ui_state: UI_State,
    fg_color: Color,
    tool_data: Tool_Data,
    alt_tool_state: Alt_Tool_Toggle,
    paint_layers: [Layer_Kind]^canvas.Layer,
    current_canvas: ^canvas.Canvas,
    canvas_render_tex: render.Tile_Array,
    canvas_gpu_tiles: [dynamic]render.Vertex_Data_Tile,
    tile_render_vb: ^render.Virtual_Buffer,
    canvas_vbuffer: render.Buffer_Portion,
}

Layer_Kind :: enum {
    BACKGROUND,
    UNDERPAINT,
    SKETCH,
    PAINT,
    LINE,
    OVERLAY
}

brush_preview_texture: ^sdl.GPUTexture

Metrics :: struct {
    brush_this_frame: bool,
    brush_render: time.Duration,
    canvas_compose_time: time.Duration,
    time_per_dab: time.Duration,
    dab_count: int,
    brush_data_rate: u64
}
metrics: Metrics

pen_mode: bool = false
pen_id: sdl.PenID

Alt_Tool_Toggle :: struct {
    active: bool,
    alt_tool: ToolState,
    original_tool: ToolState,
}

g_tool_state: ToolState = {
    _size = 16,
    size = 16,
    flow = 1,
    opacity = 1,
    step = 0.05
}
g_last_tool: ToolState
f_pen_state: PenState
f_stroke: ^Stroke_Buffer
f_stroke_dist_accum: f32
f_pen_sens: f32



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

map_wheel_col_hsl_tohsl :: proc "contextless" (pos: [2]f32) -> color.HSL {
    angle, l := math2.cart_to_polar(pos)
    okhsl: color.HSL
    okhsl.l = col_f
    okhsl.h = angle / (math.PI*2)
    okhsl.s = l*0.99


    return okhsl
}

get_frame_time :: proc() -> f32 {
    return f32(f64(last_frame)/1000000)
}

free_canvas :: proc(app: ^Application) {
    canvas.canvas_destroy(app.current_canvas)
    sdl.ReleaseGPUTexture(app.render_info.device, app.canvas_render_tex.backing_texture)
    //TODO: mamange gpu buffers better
    // render.vbuffer_reset(app.tile_render_vb)
    clear(&app.canvas_gpu_tiles)
}

restack_layers :: proc(app: ^Application, current_layer: Layer_Kind) {
    the_canvas := app.current_canvas
    brush_lr := the_canvas.brush_layer
    clear(&the_canvas.layer_stack)

    for layer, kind in app.paint_layers {
        append(&the_canvas.layer_stack, layer)
        layer.blend_mode = .NORMAL
        if kind == current_layer {
            append(&the_canvas.layer_stack, brush_lr)
            the_canvas.current_target_layer = layer
        }
    }
}



setup_canvas :: proc(app: ^Application, size: [2]int) {
    main_canvas := canvas.make_canvas(size)
    bg_layer := canvas.create_layer(main_canvas)
    canvas.fill_layer(bg_layer, color.to_linear_rgba16({0.8, 0.8, 0.8, 1}))
    // for t in bg_layer.tiles.data
    // {
    //     iter := canvas.view_iter(&t.pixels)
    //     for px, coord in canvas.view_iterate_ptr(&iter) {
    //         uv := canvas.to_vec2f(coord)/canvas.to_vec2f(main_canvas.tile_size)
    //         px^ = {f16(uv.x), f16(uv.y), 0.5, 1.0}
    //     }

    // }
    append(&main_canvas.layer_stack, bg_layer)
    paint_layer := canvas.create_layer(main_canvas)
    append(&main_canvas.layer_stack, paint_layer)
    brush_layer := canvas.create_layer(main_canvas)
    append(&main_canvas.layer_stack, brush_layer)
    main_canvas.current_target_layer = paint_layer
    main_canvas.brush_layer = brush_layer
    canvas.mark_changed(main_canvas)

    app.current_canvas = main_canvas

    app.paint_layers = {
        Layer_Kind.BACKGROUND = bg_layer,
        Layer_Kind.UNDERPAINT = canvas.create_layer(main_canvas),
        Layer_Kind.SKETCH = canvas.create_layer(main_canvas),
        Layer_Kind.PAINT = paint_layer,
        Layer_Kind.LINE = canvas.create_layer(main_canvas),
        Layer_Kind.OVERLAY = canvas.create_layer(main_canvas),
    }
    restack_layers(app, g_tool_state.bound_layer)
    
    view.scale = 1
    view.screen = {f32(app.window_size.x), f32(app.window_size.y)}
    view_fit(&view, {f32(main_canvas.size_px.x), f32(main_canvas.size_px.y)})

    tile_array, terr := render.create_tile_array(app.render_info, app.current_canvas.tile_size, len(app.current_canvas.composite_layer.tiles.data))
    if (!terr) do log.error("Error creating canvas render texture")
    app.canvas_render_tex = tile_array

    
    clear(&app.canvas_gpu_tiles)
    arr_layer: u32 = 0
    composite_layer := main_canvas.composite_layer
    for tile in app.current_canvas.tiles_rect.data {
        ensure(int(arr_layer) < tile_array.array_size, "Messed up texture array size")
        pos: [2]f32 = canvas.to_vec2f(tile.pos)
        size: [2]f32 = canvas.to_vec2f(tile.size)
        q := render.make_quad_t(pos, pos + size, arr_layer)
        for v in q {
            append(&app.canvas_gpu_tiles, v)
        }
        // fmt.printfln("[%v]tile pos: %v", arr_layer, tile.pos)
        arr_layer += 1
    }
    
    tile_vbuffer := app.tile_render_vb

    tile_buffer, tberr := render.vbuffer_reserve(tile_vbuffer, u32(len(app.canvas_gpu_tiles) * size_of(render.Vertex_Data_Tile)))
    if tberr != nil {
        log.error(tberr)
    }

    cpds := []render.Copy_Description{
        {
            src = {ptr = raw_data(app.canvas_gpu_tiles), size = u32(len(app.canvas_gpu_tiles) * size_of(render.Vertex_Data_Tile))},
            dst = tile_buffer
        }
    }

    render.vbuffer_batch_copy(app.render_info, cpds[:])

    app.canvas_vbuffer = tile_buffer
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
    brush := canvas.generate_round_pixel(brush_px, f32(g_tool_state.size))



    f_stroke = sb_make(100)

    // tile_iter := canvas.view_iter(&app.ca main_canvas.tiles_rect)

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
    


    //FIXME this is here for now
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
    
    brush_preview_quad := render.make_quad_t({0,0}, {1,1}, 0)
    brush_preview_vbuff, bp_err := render.vbuffer_reserve(tilebuff, len(brush_preview_quad)*size_of(render.Vertex_Data_Tile))
    if bp_err != nil do print_sdl_err()
    brush_preview_texture = render.create_brush_texture(app.render_info, 1024, 1024)

    app.tile_render_vb = tilebuff
    setup_canvas(app, CANVAS_SIZE)


    tile_tr_buff := sdl.CreateGPUTransferBuffer(app.render_info.device, {
        size = u32(app.current_canvas.tile_size * app.current_canvas.tile_size * size_of(canvas.Pixel)),
        usage = .UPLOAD,
    })
    brush_tr_buff := sdl.CreateGPUTransferBuffer(app.render_info.device, {
        size = u32(1024 * 1024 * size_of(f32)),
        usage = .UPLOAD,
    })
    // render.vbuffer_batch_copy(app.render_info, cpds[:])



    
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

        // fff: canvas.RectF
        
        
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
                        case .FLIP_CANVAS:
                            mouse: [2]f32
                            m_state := sdl.GetMouseState(&mouse.x, &mouse.y)
                            view_set_pivot(&view, mouse)
                            view_flip(&view)
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
                        just_released_actions += {a.type}
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

        // Needs to be called only once per frame
        mouseposrel: [2]f32
        mrel := sdl.GetRelativeMouseState(&mouseposrel.x, &mouseposrel.y)

        if .PAN_CANVAS in held_actions {
            if .LEFT in mrel {
                view_tr := view_transform(&view)
                rel_m: [3]f32
                rel_m.xy = 2*mouseposrel/canvas.to_vec2f(app.window_size)
                rel_m.y *= -1
                rel_m = linalg.inverse(view_tr) * rel_m
                view_translate(&view, -rel_m.xy)
            }
        }

        if .TOGGLE_ALT_BRUSH in just_pressed_actions {
            app.alt_tool_state.active = true
            alt_tool := app.tool_data.presets[g_tool_state.alt_brush]
            app.alt_tool_state.alt_tool = alt_tool
            app.alt_tool_state.original_tool = g_tool_state
            g_tool_state = alt_tool
        }
        if .TOGGLE_ALT_BRUSH in just_released_actions {
            app.alt_tool_state.active = false
            g_tool_state = app.alt_tool_state.original_tool
        }


        if .EYE_DROPPER in held_actions {
            mouse: [2]f32
            m_state := sdl.GetMouseState(&mouse.x, &mouse.y)
            mouse = view_to_canvas(&view, mouse)
            mousei := canvas.to_vec2i(mouse)

            tile_pos := canvas.match_tile_pos(app.current_canvas, mousei)
            tile_idx := canvas.view_get_index(app.current_canvas.composite_layer.tiles.view, tile_pos)
            tile := app.current_canvas.composite_layer.tiles.data[tile_idx]
            mousei.x = mousei.x %% tile.pixels.width
            mousei.y = mousei.y %% tile.pixels.width
            px_idx := canvas.view_get_index(tile.pixels.view, mousei)
            app.fg_color = color.to_col32(tile.pixels.data[px_idx])
            app.fg_color.rgb = color.to_srgb(app.fg_color.rgb)
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
            else {
                ok := sdl.ShowCursor(); assert(ok)
            }
            ok := sdl.SetCursor(sdl_cursor_crosshair); assert(ok)
        }
        



        //MARK: update view
        
        adjusted_pressure := math.clamp(f_pen_state.pressure * (1 + f_pen_sens), 0.0, 1.0)
        
        
        stroke_point := Stroke_Point{
            canvas_pos = f_pen_state.canvas_position,
            color = app.fg_color,
            time = f_pen_state.timestamp,
        }
        if pen_mode && (g_tool_state.size_press) {
            stroke_point.size = adjusted_pressure * f32(g_tool_state.size)
        }
        else {
            stroke_point.size = f32(g_tool_state.size)
        }

        if pen_mode && (g_tool_state.opacity_press) {
            stroke_point.opacity = adjusted_pressure * g_tool_state.opacity
        }
        else {
            stroke_point.opacity = g_tool_state.opacity
        }

        if pen_mode && (g_tool_state.flow_press) {
            stroke_point.flow = adjusted_pressure * g_tool_state.flow
        }
        else {
            stroke_point.flow = g_tool_state.flow
        }

        if .PAINT in held_actions && .PAN_CANVAS not_in held_actions {
            sb_push(f_stroke, stroke_point)
        }
        else {
            sb_clear(f_stroke)
            f_stroke_dist_accum = 0
        }

        if g_tool_state != g_last_tool {
            if !app.alt_tool_state.active {
                restack_layers(app, g_tool_state.bound_layer)
            }
        }

        
        main_canvas := app.current_canvas
        composite_layer := main_canvas.composite_layer
        {
            brush_apply :: proc(buffer: []f32, layer: canvas.Layer, sp: Stroke_Point) {
                @static prev_size: f32 = 0
                @static brush: canvas.DataView(f32)
                @static prev_options: Brush_Tip_Options
                if sp.size != prev_size || (sp.size > 1 && int(sp.size) != int(prev_size)) || g_tool_state.brush_tip_options != prev_options {
                    switch opt in g_tool_state.brush_tip_options {
                        case Brush_Round_Pixel_Opt:
                            brush = canvas.generate_round_pixel(buffer, sp.size)
                        case Brush_Round_Soft_Opt:
                            brush = canvas.generate_round_feathered(buffer, sp.size, opt.feather, false)
                        case Brush_Round_Feather_Opt:
                            brush = canvas.generate_round_feathered(buffer, sp.size, opt.feather_size, true)
                        case Brush_Round_Square_Opt:
                            brush = canvas.generate_square(buffer, sp.size)
                    }
                    prev_size = sp.size
                    prev_options = g_tool_state.brush_tip_options
                }
                brush_rect := canvas.RectI{
                    pos_size = {pos = canvas.to_vec2i(sp.canvas_pos) - brush.width/2, size = brush.width}
                }
                if g_tool_state.multisample && sp.size < g_tool_state.multisample_range { // multi-sample
                    dx := sp.canvas_pos.x - math.floor(sp.canvas_pos.x)
                    dy := sp.canvas_pos.y - math.floor(sp.canvas_pos.y)
                    px_area := canvas.RectF{xywh = {dx, dy, 1, 1}}
                    samples: [4]canvas.RectF
                    samples[0] = canvas.RectF{xywh = {0, 0, 1, 1}}
                    samples[1] = canvas.RectF{xywh = {1, 0, 1, 1}}
                    samples[2] = canvas.RectF{xywh = {0, 1, 1, 1}}
                    samples[3] = canvas.RectF{xywh = {1, 1, 1, 1}}
                    for smpl in samples {
                        coverage := canvas.rect_intersect_area(px_area, smpl)
                        brush_rect := canvas.RectI{
                            pos_size = {pos = canvas.to_vec2i({math.floor(sp.canvas_pos.x), math.floor(sp.canvas_pos.y)}) - {1,1} + canvas.to_vec2i(smpl.pos) - brush.width/2, size = brush.width}
                        }
                        canvas.brush_dab(brush, brush_rect, sp.color, sp.opacity, sp.flow*coverage, layer, g_tool_state.brush_mode)
                    }
                }
                else {
                    canvas.brush_dab(brush, brush_rect, sp.color, sp.opacity, sp.flow, layer, g_tool_state.brush_mode)
                }
            }
            metrics.brush_this_frame = false
            if .PAINT in held_actions {
                timer_dab_s := time.now()
                dab_count: int = 0
                layer := main_canvas.brush_layer^
                if layer.canvas == main_canvas {
                    current, err1 := sb_get(f_stroke, 0)
                    last, err2 := sb_get(f_stroke, 1)
                    if (f_stroke.length <= 1) {
                        brush_apply(brush_px, layer, current)
                        dab_count += 1
                    }
                    else {
                        distance := linalg.distance(current.canvas_pos, last.canvas_pos)
                        size_min := min(current.size, last.size)
                        step := max(g_tool_state.step * f32(size_min), 0.5 if g_tool_state.multisample && size_min < 2 else 1)
                        brush_dabs := make([dynamic]canvas.Brush_Dab_Data, context.temp_allocator)
                        for d: f32 = max(step - f_stroke_dist_accum, 0); d < distance; d += step {
    
                            s_point := stroke_interpolate(last, current, d / distance) if distance > 0 else current
    
                            brush_apply(brush_px, layer, s_point)
                            dab_count += 1
                            // append(&brush_dabs, canvas.Brush_Dab_Data{
                            //     col = s_point.color,
                            //     opacity = s_point.alpha,
                            //     pos = canvas.to_vec2i(s_point.canvas_pos)
                            // })
                            f_stroke_dist_accum = distance - d
                        }
                        // canvas.brush_dab_multi(brush, brush_dabs[:], size_min, layer)
                        f_stroke_dist_accum += distance
                    }
                }
                timer_dab_e := time.now()
                metrics.dab_count = dab_count
                if (dab_count > 0) {
                    metrics.brush_this_frame = true
                    metrics.brush_render = time.diff(timer_dab_s, timer_dab_e)
                    metrics.time_per_dab = time.diff(timer_dab_s, timer_dab_e)/cast(time.Duration)dab_count
                }
            }
        }

        if .PAINT in just_released_actions {
            canvas.layer_blend(main_canvas.brush_layer, main_canvas.current_target_layer, g_tool_state.brush_mode)
            canvas.clear_layer(main_canvas.brush_layer)
            // fmt.println("Brushstroke commit")
        }
        main_canvas.brush_layer.blend_mode = g_tool_state.brush_mode
        main_canvas.current_target_layer.blend_mode = g_tool_state.brush_mode
        timer_compose_s := time.now()
        canvas.canvas_compose(main_canvas)
        timer_compose_e := time.now()
        if metrics.brush_this_frame {
            metrics.canvas_compose_time = time.diff(timer_compose_s, timer_compose_e)
        }
        // view_fit(&view, {f32(main_canvas.size.x), f32(main_canvas.size.y)})

        { //update texture
            canvas_texture := app.canvas_render_tex.backing_texture
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
                    tb := sdl.MapGPUTransferBuffer(app.render_info.device, tile_tr_buff, true)
                    mem.copy_non_overlapping(tb, raw_data(tile.pixels.data), tile_size * tile_size * size_of(canvas.Pixel))
                    sdl.UnmapGPUTransferBuffer(app.render_info.device, tile_tr_buff)
                    
                    sdl.UploadToGPUTexture(copy_pass,
                    {
                        transfer_buffer = tile_tr_buff
                    },
                    {
                        layer = u32(idx),
                        d = 1,
                        w = u32(tile_size),
                        h = u32(tile_size),
                        texture = canvas_texture
                    }, false)
                }
            }
            sdl.EndGPUCopyPass(copy_pass)
            ok := sdl.SubmitGPUCommandBuffer(cmd)
        }


        if g_tool_state != g_last_tool { // update brush texture
            upload_size := g_tool_state._size
            switch opt in g_tool_state.brush_tip_options {
                case Brush_Round_Pixel_Opt:
                    brush = canvas.generate_round_pixel(brush.data, upload_size)
                case Brush_Round_Soft_Opt:
                    brush = canvas.generate_round_feathered(brush.data, upload_size, opt.feather, false)
                case Brush_Round_Feather_Opt:
                    brush = canvas.generate_round_feathered(brush.data, upload_size, opt.feather_size, true)
                case Brush_Round_Square_Opt:
                    brush = canvas.generate_square(brush.data, upload_size)
            }

            
            cmd := sdl.AcquireGPUCommandBuffer(app.render_info.device)
            copy_pass := sdl.BeginGPUCopyPass(cmd)
            tb := sdl.MapGPUTransferBuffer(app.render_info.device, brush_tr_buff, true)
            b_iter := canvas.view_iter(&brush)
            dest_ptr := cast(^f32)(tb)
            // silly pointer memy, hopefully it doesn't break
            for row, y in canvas.view_iterate_rows(&b_iter) {
                row_ptr := mem.ptr_offset(dest_ptr, y*(brush.width+4))          
                mem.copy_non_overlapping(row_ptr, raw_data(row), brush.width*size_of(f32))
                row_end := mem.ptr_offset(row_ptr, brush.width)
                mem.zero(row_end, 4*size_of(f32))
            }
            block_end := mem.ptr_offset(dest_ptr, brush.width*(brush.width+4))
            mem.zero(block_end, 4*(brush.width+4)*size_of(f32))
            
            sdl.UnmapGPUTransferBuffer(app.render_info.device, brush_tr_buff)
            sdl.UploadToGPUTexture(copy_pass,
            {
                transfer_buffer = brush_tr_buff,
                pixels_per_row = u32(brush.width+4),
            },
            {
                layer = 0,
                d = 1,
                x = 4,
                y = 4,
                w = u32(brush.width+4),
                h = u32(brush.width+4),
                texture = brush_preview_texture
            }, false)

            sdl.EndGPUCopyPass(copy_pass)
            ok := sdl.SubmitGPUCommandBuffer(cmd)
        }

        { // place brush preview
            brush_preview_quad = render.make_quad_t(f_pen_state.canvas_position - g_tool_state._size/2 - {4,4}, f_pen_state.canvas_position + g_tool_state._size/2 + {4,4}, 0)
            for &v in brush_preview_quad {
                v.uv = v.uv*(f32(brush.width + 8)/1024)
            }
            
            cpds := []render.Copy_Description{
                {
                    src = {ptr = raw_data(brush_preview_quad[:]), size = 6 * size_of(render.Vertex_Data_Tile)},
                    dst = brush_preview_vbuff
                }
            }

            render.vbuffer_batch_copy(app.render_info, cpds[:])
        }

        g_last_tool = g_tool_state
        canvas.canvas_reset_tile_state(main_canvas) 
        
       


        

        render.vbuffer_reset(vbuff)
        render.vbuffer_reset(idxbuff)

        {
            canvas_texture := app.canvas_render_tex.backing_texture
            uniform_data := render.VUB{
                camera = render.align_matrix3(view_transform(&view)),
                width = main_canvas.size_px.x,
                height = main_canvas.size_px.y,
                tile_size = main_canvas.tile_size,
                brush_pixel_scale = view.scale,
                uv_max = {(f32(brush.width + 8)/1024), (f32(brush.width + 8)/1024)}
            }
            render.render_canvas(app.render_info, canvas_texture, brush_preview_texture, u32(len(app.canvas_gpu_tiles)), &app.canvas_vbuffer, &brush_preview_vbuff, uniform_data, .CLEAR)
            render_ui(app.ui_context, app, vbuff, idxbuff)
            render.present(app.render_info)
        }
        
        when DEBUG_PRINT do fmt.print(fmt.tprintfln("MEM: %M", tracking_alloc.current_memory_allocated))
        
        free_all(context.temp_allocator)

        evtm := sdl.WaitEventTimeout(nil, -1)
    }

   

    save_ui_state(app)
    save_tool_data(app)
    sdl.Quit()
    
}

Saved_Tool_Data :: struct {
    tool_data: Tool_Data,
    global_pen_sens: f32,
}

save_tool_data :: proc(app: ^Application) {
    log.info("Saving tool data")
    app.tool_data.presets[app.tool_data.current_preset] = g_tool_state
    save_tool_data := Saved_Tool_Data{
        tool_data = app.tool_data,
        global_pen_sens = f_pen_sens
    }
    if json_data, json_err := json.marshal(save_tool_data, allocator = context.temp_allocator); json_err == nil {
        write_err := os.write_entire_file("user/tool_data.conf.json", json_data)
        if write_err != nil {
            log.errorf("Couldn't save tool data! Error: %v", write_err)
        }
    } else {
        log.errorf("Couldn't save tool data! Error: %v", json_err)
    }
}

load_tool_data :: proc(app: ^Application) {
    log.info("Loading tool data")
    if json_data, json_err := os.read_entire_file("user/tool_data.conf.json", context.temp_allocator); json_err == nil {
        loaded_tool_data: Saved_Tool_Data

        
        if unmarshal_err := json.unmarshal(json_data, &loaded_tool_data); unmarshal_err == nil {
            f_pen_sens = loaded_tool_data.global_pen_sens
            app.tool_data = loaded_tool_data.tool_data
            if loaded_tool_data.tool_data.current_preset >= 0 && loaded_tool_data.tool_data.current_preset < len(loaded_tool_data.tool_data.presets) {
                g_tool_state = loaded_tool_data.tool_data.presets[loaded_tool_data.tool_data.current_preset]
            }
            log.info("Loaded previous tool data from \"tool_data.conf.json\"")
        } else {
            log.errorf("Failed to load previous tool data. Error: %v", unmarshal_err)
        }

        jval, parse_err := json.parse(json_data, allocator = context.temp_allocator)
        if parse_err != nil{
            log.error(parse_err)
        }
        obj, ok := jval.(json.Object)
        obj2, ok2 := obj["tool_data"].(json.Object)
        tl, ok3 := obj2["presets"].(json.Array)
        for tool, idx in tl {
            t, err4 := tool.(json.Object)
            // for k, v in t {
            //     fmt.printfln("%v :: %v (%T)", k, v, cast(any)v)
            //     switch a in v {
            //         case json.Null:
            //             fmt.println("null")
            //         case json.Integer:
            //             fmt.println("int")
            //         case json.Float:
            //             fmt.println("float")
            //         case json.Boolean:
            //             fmt.println("bool")
            //         case json.String:
            //             fmt.println("string")
            //         case json.Array:
            //             fmt.println("array")
            //         case json.Object:
            //             fmt.println("object")
            //     }
            // }

            brush_type, err5 := t["brush_type"].(json.Float)
            options, err6 := t["brush_tip_options"].(json.Object)
            brush_type_enum := cast(Brush_Tip)(int(brush_type))
            switch brush_type_enum {
                case .UNDEFINED:
                case .ROUND_PIXEL:
                    opts: Brush_Round_Pixel_Opt
                    app.tool_data.presets[idx].brush_tip_options = opts
                case .SQUARE:
                    opts: Brush_Round_Square_Opt
                    app.tool_data.presets[idx].brush_tip_options = opts
                case .ROUND_FEATHER:
                    opts: Brush_Round_Feather_Opt

                    fs, ok := options["feather_size"]
                    if ok {
                        opts.feather_size = f32(fs.(json.Float))
                        app.tool_data.presets[idx].brush_tip_options = opts
                    }
                case .ROUND_SOFT:
                    opts: Brush_Round_Soft_Opt

                    ff, ok := options["feather"]
                    if ok {
                        opts.feather = f32(ff.(json.Float))
                        app.tool_data.presets[idx].brush_tip_options = opts
                    }
            }
            g_tool_state = app.tool_data.presets[app.tool_data.current_preset]
        }

    } else {
        log.debug("Failed to read \"tool_data.conf.json\". Error: &v", json_err)
    }
}

Saved_UI_Config :: struct {
    ui_state: UI_State,
    window_size: [2]int,
    window_position: [2]c.int,
}

save_ui_state :: proc(app: ^Application) {
    log.info("Saving ui state")
    saved_state: Saved_UI_Config = {
        ui_state = app.ui_state,
        window_position = app.window_position,
        window_size = app.window_size,
    }
    win_pos: [2]c.int
    sdl.PumpEvents()
    err := sdl.GetWindowPosition(app.window, &win_pos.x, &win_pos.y)
    if !err do print_sdl_err()
    saved_state.window_position = win_pos
    if json_data, json_err := json.marshal(saved_state, allocator = context.temp_allocator); json_err == nil {
        write_err := os.write_entire_file("user/ui_state.conf.json", json_data)
        if write_err != nil {
            log.errorf("Couldn't save ui state! Error: %v", write_err)
        }
    } else {
        log.errorf("Couldn't save ui state! Error: %v", json_err)
    }
}

load_ui_state :: proc(app: ^Application) {
    log.info("Loading ui state")
    if json_data, json_err := os.read_entire_file("user/ui_state.conf.json", context.temp_allocator); json_err == nil {
        loaded_state: Saved_UI_Config

        if unmarshal_err := json.unmarshal(json_data, &loaded_state); unmarshal_err == nil {
            app.ui_state = loaded_state.ui_state
            app.window_size = loaded_state.window_size
            app.window_position = loaded_state.window_position
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

    os.make_directory("user")
    load_tool_data(application)
    load_ui_state(application)



    if application.window_size == {0,0} {
        application.window_size = {window_w, window_h}
    }
    application.window = sdl.CreateWindow(name, c.int(application.window_size.x), c.int(application.window_size.y), {.RESIZABLE})
    if application.window == nil do print_sdl_err()
    if application.window_position != {0,0} {
        sdl.SetWindowPosition(application.window, c.int(application.window_position.x), c.int(application.window_position.y))
    }


    application.render_info = new(render.Render_Info)
    render.init(application.window, application.render_info)

    application.text_renderer = new(Text_Renderer)
    application.text_renderer.text_engine = ttf.CreateGPUTextEngine(application.render_info.device)

    application.fg_color = {0.5,0.5,0.5,1}
    col_f = 0.5

   
    application.ui_context = new(Ui_Context)
    ui_init(application.ui_context, application.render_info)
}

print_sdl_err :: proc() {
    fmt.printfln("SDL Error: {}", sdl.GetError())
}

save_img :: proc(layer: ^canvas.Layer) {
    image_surf := sdl.CreateSurface(i32(layer.size_px.x), i32(layer.size_px.y), .RGBA64_FLOAT)
    t_size := layer.tile_size
    surfs := make([dynamic]^sdl.Surface, context.temp_allocator)
    for tile, idx in layer.tiles_rect.data {
        tile_surf := sdl.CreateSurfaceFrom(i32(t_size), i32(t_size), .RGBA64_FLOAT, raw_data(layer.tiles.data[idx].pixels.data), i32(t_size*size_of(canvas.Pixel)))
        append(&surfs, tile_surf)
        blit_rect := sdl.Rect {
            x = i32(tile.x),
            y = i32(tile.y),
            w = i32(tile.w),
            h = i32(tile.h)}
        sdl.BlitSurface(tile_surf, nil, image_surf, &blit_rect)
    }
    image.SavePNG(image_surf, "saved.png")
    for s in surfs {
        sdl.DestroySurface(s)
    }
    sdl.DestroySurface(image_surf)
}