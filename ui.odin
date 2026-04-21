package main

import sdl "vendor:sdl3"
import "core:strings"
import "core:log"
import "core:fmt"
import mu "vendor:microui"
import "vendor:sdl3/ttf"
import "render"

Rect_List :: [dynamic]render.Rect_Instance

Ui_Context :: struct {
    mu_context: ^mu.Context,
    default_font: mu.Font,
    rect_list: Rect_List,
    text_seq: [dynamic]^ttf.GPUAtlasDrawSequence,
}

ui_init :: proc(ui_ctx: ^Ui_Context) {
    ui_ctx.mu_context = new(mu.Context)
    mu.init(ui_ctx.mu_context)

    ui_font := ttf.OpenFont("fonts/DroidSans.ttf", 16)
    ui_ctx.default_font = cast(mu.Font)ui_font

    ui_ctx.mu_context.text_height = mu_text_height
    ui_ctx.mu_context.text_width = mu_text_width
    ui_ctx.mu_context.style.font = cast(mu.Font)ui_font

    ui_ctx.text_seq = make([dynamic]^ttf.GPUAtlasDrawSequence)
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

    w: i32 = 16
    text_size := ttf.GetTextSize(text, &w, nil)
    ttf.DestroyText(text)
    return w
}

Vertex_Feeder :: struct {
    vertices: [^]render.Vertex_Data,
    current_vertex: int,
    max_vert_capacity: int,
    vertex_count: int,

    indices_offset: int,
    indices: [^]i32,
    current_index: int,
    max_idx_capacity: int,
    index_count: int,

    atlas: ^sdl.GPUTexture,
}



push_vertex :: proc(vf: ^Vertex_Feeder, vertex: render.Vertex_Data) -> bool {
    if (vf.current_vertex >= vf.max_vert_capacity) {
        log.error("Vertex_Feeder capacity reached")
        return false
    }
    vf.vertices[vf.current_vertex] = vertex
    vf.vertex_count += 1
    vf.current_vertex += 1
    return true
}

push_index :: proc(vf: ^Vertex_Feeder, index: i32) -> bool {
    if (vf.current_index >= vf.max_idx_capacity) {
        log.error("Vertex_Feeder index capacity reached")
        return false
    }
    vf.indices[vf.current_index] = index
    vf.index_count += 1
    vf.current_index += 1
    return true
}


render_ui :: proc(ui_ctx: ^Ui_Context, app: ^Application, vb: ^render.Virtual_Buffer, ib: ^render.Virtual_Buffer) {
    mu_ctx := ui_ctx.mu_context
    clear(&ui_ctx.rect_list)

    raw_tb := sdl.MapGPUTransferBuffer(app.render_info.device, app.render_info.transfer_buff, true)
    vf: Vertex_Feeder
    vf.vertices = ([^]render.Vertex_Data)(raw_tb)
    vf.current_vertex = 0
    indices_size: int = size_of(u32) * 10000
    vf.indices = ([^]i32)(raw_tb)
    vf.max_vert_capacity = int(app.render_info.transfer_buff_size / size_of(render.Vertex_Data)) - indices_size
    vf.max_idx_capacity = int(app.render_info.transfer_buff_size / size_of(u32))
    vf.indices_offset = vf.max_idx_capacity - indices_size
    vf.current_index = vf.indices_offset



    cmd_backing: ^mu.Command
    for cmd_variant in mu.next_command_iterator(mu_ctx, &cmd_backing) {
        #partial switch cmd in cmd_variant {
            case ^mu.Command_Rect:
                mu_draw_rect(cmd.rect, cmd.color, &vf)
            case ^mu.Command_Text:
                mu_draw_text(cmd.str, cmd.pos, cmd.color, &vf, app)
            case ^mu.Command_Icon:
                mu_draw_icon(cmd.id, cmd.rect, cmd.color, &ui_ctx.rect_list)
        }
    }

    sdl.UnmapGPUTransferBuffer(app.render_info.device, app.render_info.transfer_buff)

    vbuff, errv := render.vbuffer_reserve(vb, u32(vf.vertex_count) * size_of(render.Vertex_Data))
    idxbuff, erri := render.vbuffer_reserve(ib, u32(vf.index_count) * size_of(u32))
    if (errv != nil || erri != nil) {
        fmt.printfln("Unable to reserve v. buffers (vertex: {}, index: {})", errv, erri)
    }

    copy_cmd := sdl.AcquireGPUCommandBuffer(app.render_info.device)
    copy_pass := sdl.BeginGPUCopyPass(copy_cmd)

    sdl.UploadToGPUBuffer(copy_pass,
        {transfer_buffer = app.render_info.transfer_buff, offset = 0},
        {buffer = vbuff.vbuffer.buffer, offset = vbuff.offset, size = vbuff.size},
        false
    )
    sdl.UploadToGPUBuffer(copy_pass,
        {transfer_buffer = app.render_info.transfer_buff, offset = u32(vf.indices_offset) * size_of(u32)},
        {buffer = idxbuff.vbuffer.buffer , offset = idxbuff.offset, size = idxbuff.size},
        false
    )

    sdl.EndGPUCopyPass(copy_pass)
    ok := sdl.SubmitGPUCommandBuffer(copy_cmd); assert(ok)

    render.render_ui_elements(app.render_info, vf.atlas, u32(vf.index_count), &vbuff, &idxbuff)


}

Corner :: enum {
    TL,
    TR,
    BL,
    BR
}

get_corner :: proc(rect: mu.Rect, corner: Corner) -> [2]f32 {
    switch corner {
        case .TL:
            return {f32(rect.x), -f32(rect.y)}
        case .TR:
            return {f32(rect.x + rect.w), -f32(rect.y)}
        case .BL:
            return {f32(rect.x), -f32(rect.y + rect.h)}
        case .BR:
            return {f32(rect.x + rect.w), -f32(rect.y + rect.h)}
        case:
            return {0,0}
    }
}

mu_draw_rect :: proc(rect: mu.Rect, color: mu.Color, vf: ^Vertex_Feeder) {
    col: render.Color8 = {color.r, color.g, color.b, color.a}

    start_idx: i32 = i32(vf.current_vertex)
    push_vertex(vf, {pos = get_corner(rect, .TL), uv = {-1,-1}, color = col})
    push_vertex(vf, {pos = get_corner(rect, .TR), uv = {-1,-1}, color = col})
    push_vertex(vf, {pos = get_corner(rect, .BR), uv = {-1,-1}, color = col})
    push_vertex(vf, {pos = get_corner(rect, .BL), uv = {-1,-1}, color = col})

    push_index(vf, start_idx + 0)
    push_index(vf, start_idx + 1)
    push_index(vf, start_idx + 2)

    push_index(vf, start_idx + 0)
    push_index(vf, start_idx + 2)
    push_index(vf, start_idx + 3)

}

mu_draw_text :: proc(text: string, pos: mu.Vec2, color: mu.Color, vf: ^Vertex_Feeder, app: ^Application) {
    text := ttf.CreateText(app.text_renderer.text_engine, app.text_renderer.font, fmt.ctprint(text), 0)
    ttf.SetTextPosition(text, pos.x, pos.y)

    col: render.Color8 = {color.r, color.g, color.b, color.a}

    draw_data := ttf.GetGPUTextDrawData(text)
    for draw_data != nil {
        vf.atlas = draw_data.atlas_texture
        start_idx: i32 = i32(vf.current_vertex)
        for i in 0..<draw_data.num_vertices {
            push_vertex(vf, {
                pos = ([2]f32)(draw_data.xy[i]),
                uv = ([2]f32)(draw_data.uv[i]),
                color = col
            })
        }
        for i in 0..<draw_data.num_indices {
            push_index(vf, start_idx + draw_data.indices[i])
        }
        draw_data = draw_data.next
    }
    //TODO re-enable
    // ttf.DestroyText(text)
}

mu_draw_icon :: proc(id: mu.Icon, rect: mu.Rect, color: mu.Color, rect_list: ^Rect_List) {

}