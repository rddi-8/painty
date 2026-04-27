package main

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

import mu "microui"
import "render"
import "color"
import "math2"
import "canvas"

DEBUG_PRINT :: false

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
    dev_panel: UI_Panel,
}
Application :: struct {
    window: ^sdl.Window,
    window_size: [2]int,
    ui_context: ^Ui_Context,
    render_info: ^render.Render_Info,
    text_renderer: ^Text_Renderer,
    ui_state: UI_State,
    fg_color: Color,
    current_canvas: ^canvas.Canvas
}

mouse_just_pressed: bool
view: Canvas_View

font_cache: map[f32]^ttf.Font

main_context: runtime.Context

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
    main_canvas := canvas.make_canvas({2100, 2600})
    layer, err := canvas.create_layer(main_canvas)
    fmt.println(err)
    canvas.fill_layer(layer, {0.1, 0.4, 0, 1})

    {
        for t in layer.tiles {
            slice.fill(t.pixel_data, canvas.Pixel{f16(rand.float32()),f16(rand.float32()),f16(rand.float32()),1})
            for &d in t.pixel_data {
                d.rgb += f16(rand.float32()*0.2-0.1)
            }
        }
    }
    // i := 0
    // for tile in lr.tiles {
    //     fmt.printfln("tile[%v] size=%v len=%v data=%p", i, tile.size, len(tile.pixel_data), raw_data(tile.pixel_data))
    //     fmt.println(tile.pixel_data)
    //     i += 1
    // }


    
    
    //TODO remove
    test_mesh := render.gen_circle(8,3, map_wheel_col)
    
    app := new(Application)
    init_app(app, WINDOW_W, WINDOW_H, "Painty")
    
    app.current_canvas = main_canvas

    //FIXME this is here for now
    view.scale = 1
    view.screen = {f32(app.window_size.x), f32(app.window_size.y)}
    view_fit(&view, {f32(main_canvas.size.x), f32(main_canvas.size.y)})

    //TODO remove tile thingy
    // tt, tte := render.create_tile_atlas(app.render_info, layer.tile_size, len(layer.tiles))

    tile_array, terr := render.create_tile_array(app.render_info, layer.tile_size, len(layer.tiles))

    // fmt.printfln("canvas tiles = %v, atlas_tiles = %v", len(layer.tiles), len(tt.tiles))

    
    
    action_binds := new(Action_Binds)
    create_default_keybinds(action_binds)
    add_keybind(&action_binds.key_binds, Input_Event_Key{ctx = .PAINTING, key = .C}, 
        Action_BoolToggle{ value = &app.ui_state.color_picker.open})
    

    current_context := InputContext.PAINTING

    actions: [dynamic]Action
    held_actions: Currently_Held_Actions

 
    vbuff := render.create_vbuffer(app.render_info.device, {.VERTEX}, 30 * mem.Megabyte)
    
    idxbuff := render.create_vbuffer(app.render_info.device, {.INDEX}, 30 * mem.Megabyte)

    tilebuff := render.create_vbuffer(app.render_info.device, {.VERTEX}, 10 * mem.Megabyte)

    buncha_tiles: [dynamic]render.Vertex_Data_Tile
    arr_layer: u32 = 0
    for tile in layer.tiles {
        ensure(int(arr_layer) < tile_array.array_size, "Messed up texture array size")
        pos: [2]f32 = {f32(tile.pos.x), f32(tile.pos.y)}
        size: [2]f32 = {f32(tile.size), f32(tile.size)}
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

    render.vbuffer_batch_copy(app.render_info, cpds[:])

    { //populate texture
        arr_layer: u32 = 0
        cmd := sdl.AcquireGPUCommandBuffer(app.render_info.device)
        copy_pass := sdl.BeginGPUCopyPass(cmd)
        for tile in layer.tiles {
            //FIXME: don't allocate million cycled transfer buffers
            tb := sdl.MapGPUTransferBuffer(app.render_info.device, app.render_info.transfer_buff, true)
            mem.copy_non_overlapping(tb, raw_data(tile.pixel_data), tile.size * tile.size * size_of(canvas.Pixel))
            sdl.UnmapGPUTransferBuffer(app.render_info.device, app.render_info.transfer_buff)
            
            sdl.UploadToGPUTexture(copy_pass,
            {
                transfer_buffer = app.render_info.transfer_buff
            },
            {
                layer = arr_layer,
                d = 1,
                w = u32(tile.size),
                h = u32(tile.size),
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

    main_loop: for {
        last_frame = sdl.GetTicksNS() - timer
        // fmt.printfln("%.2f ms", f64(last_frame)/1000000)
        timer = sdl.GetTicksNS()
        
        //MARK: EVENTS
        keybind_map := action_binds.key_binds
        mouse_map := action_binds.mouse_binds
        pen_map := action_binds.pen_binds
        
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
            }
        }

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
                    }
                case Action_Canvas_Location:
                    log.debug("Canvas Location Action:", a.type, "loc:", a.location)
                case Action_ToolToggle:
                    log.debug("Toggle Tool Action:", "tool_id:", a.tool_id)
                case Action_Held:
                    if !a.up {
                        held_actions += {a.type}
                    }
                    else {
                        held_actions -= {a.type}
                    }
                    log.debug("Held Action:", a.type, "up:", a.up)
                case Action_BoolToggle:
                    a.value^ = !a.value^
            }
        }

        //MARK: update view
        view.screen = {f32(app.window_size.x), f32(app.window_size.y)}
        // view_fit(&view, {f32(main_canvas.size.x), f32(main_canvas.size.y)})
        

        muctx := app.ui_context.mu_context
        mu.begin(muctx)
        
        compose_main(app)
        compose_color_picker(app, &app.ui_state.color_picker)
        compose_dev_panel(app, &app.ui_state.dev_panel)

        mu.end(muctx)


        

        render.vbuffer_reset(vbuff)
        render.vbuffer_reset(idxbuff)


        uniform_data := render.VUB{
            camera = render.align_matrix3(view_transform(&view)),
            width = main_canvas.size.x,
            height = main_canvas.size.y,
            tile_size = main_canvas.tile_size,
        }
        render.render_canvas(app.render_info, tile_array.backing_texture, u32(len(buncha_tiles)), &tilebffr, uniform_data, .CLEAR)
        render_ui(app.ui_context, app, vbuff, idxbuff)
        render.present(app.render_info)
        
        when DEBUG_PRINT do fmt.print(fmt.tprintfln("MEM: %M", tracking_alloc.current_memory_allocated))
        
        free_all(context.temp_allocator)
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