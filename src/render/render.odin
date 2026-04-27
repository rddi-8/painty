package render

import "vendor:sdl3/ttf"
import "core:strings"
import "core:slice"
import "vendor:sdl3/image"
import "core:mem"
import "base:runtime"
import "core:log"
import sdl "vendor:sdl3"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "shadercross"


DEBUG : bool : true when ODIN_DEBUG else false

VERTEX_BUFFER_SIZE : u32 :      100 * mem.Megabyte
TRANSFER_BUFFER_SIZE : u32 :    100 * mem.Megabyte

SizeU32 :: struct {
    w, h: u32
}

Vec2 :: linalg.Vector2f32
Vec3 :: linalg.Vector3f32
Color8 :: [4]u8
Matrix2 :: linalg.Matrix2f32
Matrix3 :: linalg.Matrix3f32
Matrix3align :: matrix[4,3]f32
Color :: linalg.Vector4f32

Rect :: struct {
    pos: [2]f32,
    size: [2]f32,
}
Vertex_Data :: struct {
    pos: Vec2,
    uv: Vec2,
    color: Color8
}
Vertex_Data_Tile :: struct {
    pos: Vec2,
    uv: Vec2,
    array_layer: u32,
    _: f32,
}
Rect_Instance :: struct {
    pos: Vec2,
    size: Vec2,
    color: Color,
    uv: Vec2
}
Contex_Switch :: struct {
    num_primitives: int,
    scissor: sdl.Rect
}
VUB :: struct {
    camera: Matrix3align,
    width, height: int,
    tile_size: int,
}
Render_Info :: struct {
    device: ^sdl.GPUDevice,
    window: ^sdl.Window,
    vertex_buff: ^sdl.GPUBuffer,
    vertex_buff_size: u32,
    transfer_buff: ^sdl.GPUTransferBuffer,
    transfer_buff_size: u32,
    texture: [10]^sdl.GPUTexture,
    linear_sampler: ^sdl.GPUSampler,
    canvas_sampler: ^sdl.GPUSampler,
    VUB: VUB,
    pipeline_tex: ^sdl.GPUGraphicsPipeline,
    pipeline_tile: ^sdl.GPUGraphicsPipeline,
    render_target: ^sdl.GPUTexture,
    render_target_info: sdl.GPUTextureCreateInfo,
}

Program_State_Flags :: enum {
    QUIT
}
program_state : bit_set[Program_State_Flags]

Input_Action_FLags :: enum {
    LEFT,
    RIGHT,
    UP,
    DOWN
}
input_action : bit_set[Input_Action_FLags]

WIDTH :: 600
HEIGHT :: 600

ticks: u64
time: f64

print_err :: proc() {
    fmt.printfln("SDL Error: {}", sdl.GetError())
}

main_context: runtime.Context

I_shader_vert := #load("shaders/shader.spv.vert")
I_shader_frag := #load("shaders/shader.spv.frag")
I_rect_vert := #load("shaders/rect.spv.vert")
I_rect_frag := #load("shaders/rect.spv.frag")

//MARK: INIT
init :: proc(window: ^sdl.Window, render_info: ^Render_Info) {
    gpu := sdl.CreateGPUDevice({.SPIRV}, DEBUG, nil); assert(gpu != nil)
    ok := sdl.ClaimWindowForGPUDevice(gpu, window); assert(ok)
    ok = sdl.SetGPUSwapchainParameters(gpu, window, .SDR, .IMMEDIATE); assert(ok)
    ok = shadercross.Init(); assert(ok)

    render_info.device = gpu
    render_info.window = window

    render_info.vertex_buff = sdl.CreateGPUBuffer(
        gpu,
        {
            usage = {.VERTEX},
            size = VERTEX_BUFFER_SIZE,
        }
    )
    render_info.vertex_buff_size = VERTEX_BUFFER_SIZE
    
    render_info.transfer_buff = sdl.CreateGPUTransferBuffer(gpu, {
        usage = .UPLOAD,
        size = TRANSFER_BUFFER_SIZE
    })
    render_info.transfer_buff_size = TRANSFER_BUFFER_SIZE


    setup_samplers(gpu, render_info)
    setup_pipelines(gpu, render_info, sdl.GetGPUSwapchainTextureFormat(gpu, window))
}

xform_points :: proc(points: []Vertex_Data, translation: Vec2, angle: f32) -> []Vertex_Data {
    rot := linalg.matrix2_rotate_f32(angle)
    rot3 := linalg.Matrix3x3f32(rot)
    translate := linalg.MATRIX3F32_IDENTITY
    translate[2][0] = translation.x
    translate[2][1] = translation.y
    for &point in points {
        pos3: linalg.Vector3f32
        pos3.xy = point.pos.xy
        pos3.z = 1
        pos3 = translate * rot3 * pos3
        point.pos = pos3.xy
    }
    return points
}

make_quad :: proc(tl, br: Vec2) -> [6]Vertex_Data {
    return [6]Vertex_Data{
        { pos = {tl.x, tl.y}, uv = {0, 0} },
        { pos = {br.x, br.y}, uv = {1, 1} },
        { pos = {tl.x, br.y}, uv = {0, 1} },

        { pos = {tl.x, tl.y}, uv = {0, 0} },
        { pos = {br.x, tl.y}, uv = {1, 0} },
        { pos = {br.x, br.y}, uv = {1, 1} },
    }
}

make_quad_t :: proc(tl, br: Vec2, layer: u32) -> [6]Vertex_Data_Tile {
    return [6]Vertex_Data_Tile{
        { pos = {tl.x, tl.y}, uv = {0, 0}, array_layer = layer },
        { pos = {br.x, br.y}, uv = {1, 1}, array_layer = layer },
        { pos = {tl.x, br.y}, uv = {0, 1}, array_layer = layer },

        { pos = {tl.x, tl.y}, uv = {0, 0}, array_layer = layer },
        { pos = {br.x, tl.y}, uv = {1, 0}, array_layer = layer },
        { pos = {br.x, br.y}, uv = {1, 1}, array_layer = layer },
    }
}


setup_samplers :: proc(device: ^sdl.GPUDevice, render_info: ^Render_Info) {
    render_info.linear_sampler = sdl.CreateGPUSampler(
        device,
        {
            mag_filter = .LINEAR,
            min_filter = .LINEAR,
            address_mode_u = .REPEAT,
            address_mode_v = .REPEAT,
            mipmap_mode = .LINEAR,
            max_lod = 10
        }
    )
    render_info.canvas_sampler = sdl.CreateGPUSampler(
        device,
        {
            mag_filter = .NEAREST,
            min_filter = .LINEAR,
            address_mode_u = .REPEAT,
            address_mode_v = .REPEAT,
            mipmap_mode = .LINEAR,
            max_lod = 1
        }
    )
}

setup_pipelines :: proc(device: ^sdl.GPUDevice, render_info: ^Render_Info, swapchain_format: sdl.GPUTextureFormat) {
    vert_shader := create_shader(device, I_shader_vert, .VERTEX)
    frag_shader := create_shader(device, I_shader_frag, .FRAGMENT)
    vert_shader_tile := create_shader(device, I_rect_vert, .VERTEX)
    frag_shader_tile := create_shader(device, I_rect_frag, .FRAGMENT)

    //MARK: tex pipeline
    vertex_attrs_tex := []sdl.GPUVertexAttribute {
        {   // POSITION
            buffer_slot = 0,
            location = 0,
            format = .FLOAT2,
            offset = u32(offset_of(Vertex_Data, pos))
        },
        {   // UV
            buffer_slot = 0,
            location = 1,
            format = .FLOAT2,
            offset = u32(offset_of(Vertex_Data, uv))
        },
        {   // COLOR
            buffer_slot = 0,
            location = 2,
            format = .UBYTE4_NORM,
            offset = u32(offset_of(Vertex_Data, color)),
        }
    }

    render_info.pipeline_tex = sdl.CreateGPUGraphicsPipeline(
        device,
        {
            vertex_shader = vert_shader,
            fragment_shader = frag_shader,
            primitive_type = .TRIANGLELIST,
            vertex_input_state = {
                num_vertex_buffers = 1,
                vertex_buffer_descriptions = raw_data([]sdl.GPUVertexBufferDescription{
                    {
                        slot = 0,
                        pitch = size_of(Vertex_Data),
                        input_rate = .VERTEX
                    }
                }),
                num_vertex_attributes = u32(len(vertex_attrs_tex)),
                vertex_attributes = raw_data(vertex_attrs_tex)
            },
            target_info = {
                num_color_targets = 1,
                color_target_descriptions = &sdl.GPUColorTargetDescription{
                    format = .R16G16B16A16_FLOAT,
                    blend_state = {
                        enable_blend = true,
                        color_blend_op = .ADD,
                        alpha_blend_op = .ADD,
                        src_color_blendfactor = .SRC_ALPHA,
                        dst_color_blendfactor = .ONE_MINUS_SRC_ALPHA,
                        src_alpha_blendfactor = .SRC_ALPHA,
                        dst_alpha_blendfactor = .ONE_MINUS_SRC_ALPHA
                    }
                },
            }
        })

    //MARK: tile pipeline
    vertex_attrs_tile := []sdl.GPUVertexAttribute {
        {
            buffer_slot = 0,
            location = 0,
            format = .FLOAT2,
            offset = u32(offset_of(Vertex_Data_Tile, pos))
        },
        {
            buffer_slot = 0,
            location = 1,
            format = .FLOAT2,
            offset = u32(offset_of(Vertex_Data_Tile, uv))
        },
        {
            buffer_slot = 0,
            location = 2,
            format = .UINT,
            offset = u32(offset_of(Vertex_Data_Tile, array_layer))
        }
    }

    render_info.pipeline_tile = sdl.CreateGPUGraphicsPipeline(
        device,
        {
            vertex_shader = vert_shader_tile,
            fragment_shader = frag_shader_tile,
            primitive_type = .TRIANGLELIST,
            vertex_input_state = {
                num_vertex_buffers = 1,
                num_vertex_attributes = 3,
                vertex_buffer_descriptions = raw_data([]sdl.GPUVertexBufferDescription{
                    {
                        slot = 0,
                        pitch = size_of(Vertex_Data_Tile),
                        input_rate = .VERTEX
                    }
                }),
                vertex_attributes = raw_data(vertex_attrs_tile)
            },
            target_info = {
                num_color_targets = 1,
                color_target_descriptions = &sdl.GPUColorTargetDescription{
                    format = .R16G16B16A16_FLOAT,
                    blend_state = {
                        enable_blend = true,
                        color_blend_op = .ADD,
                        alpha_blend_op = .ADD,
                        src_color_blendfactor = .SRC_ALPHA,
                        dst_color_blendfactor = .ONE_MINUS_SRC_ALPHA,
                        src_alpha_blendfactor = .SRC_ALPHA,
                        dst_alpha_blendfactor = .ONE_MINUS_SRC_ALPHA
                    }
                }
            }
            
        }
    )

}

ptr_offset :: proc(ptr: rawptr, offset: u32) -> rawptr {
    return rawptr(uintptr(ptr) + uintptr(offset))
}

render_start_frame :: proc() {
    ok: bool

}

create_render_target :: proc(render_info: ^Render_Info, w, h: u32) {
    if (render_info.render_target != nil) {
        sdl.ReleaseGPUTexture(render_info.device, render_info.render_target)
    }
    create_info := sdl.GPUTextureCreateInfo{
        format = .R16G16B16A16_FLOAT,
        width = w,
        height = h,
        layer_count_or_depth = 1,
        num_levels = 1,
        type = .D2,
        usage = {.SAMPLER, .COLOR_TARGET},
    }
    render_info.render_target = sdl.CreateGPUTexture(render_info.device, create_info)
    render_info.render_target_info = create_info

}

present :: proc(render_info: ^Render_Info) {
    ok: bool
    ok = sdl.WaitForGPUSwapchain(render_info.device, render_info.window); assert(ok)
    cmd_buff := sdl.AcquireGPUCommandBuffer(render_info.device)
    swapchain_tex: ^sdl.GPUTexture
    swapchain_size: SizeU32
    ok = sdl.WaitAndAcquireGPUSwapchainTexture(cmd_buff, render_info.window, &swapchain_tex, &swapchain_size.w, &swapchain_size.h); assert(ok)

    rt := render_info.render_target
    rti := render_info.render_target_info

    sdl.BlitGPUTexture(cmd_buff, {
        source = {
            texture = rt,
            w = rti.width,
            h = rti.height,
            layer_or_depth_plane = 0,
            x = 0,
            y = 0,
        },
        destination = {
            texture = swapchain_tex,
            w = swapchain_size.w,
            h = swapchain_size.h,
            layer_or_depth_plane = 0,
            x = 0,
            y = 0,
        },
    })

    ok = sdl.SubmitGPUCommandBuffer(cmd_buff); assert(ok)

}

render_canvas :: proc(render_info: ^Render_Info, tex: ^sdl.GPUTexture, num_verts: u32, vbuffer: ^Buffer_Portion, vub: VUB,  load: sdl.GPULoadOp) {
    cmd_buff := sdl.AcquireGPUCommandBuffer(render_info.device)
    sdl.PushGPUDebugGroup(cmd_buff, "Canvas")

    color_target := sdl.GPUColorTargetInfo {
        texture = render_info.render_target,
        load_op = load,
        store_op = .STORE,
        clear_color = {0.0, 0.0, 0.0, 1.0}
    }

    color_targets := [?]sdl.GPUColorTargetInfo{color_target}
    
    render_pass := sdl.BeginGPURenderPass(cmd_buff, raw_data(color_targets[:]), 1, nil)


    sdl.BindGPUGraphicsPipeline(render_pass, render_info.pipeline_tile)
    sdl.BindGPUVertexBuffers(render_pass, 0,
        raw_data([]sdl.GPUBufferBinding{
            {
                buffer = vbuffer.vbuffer.buffer,
                offset = vbuffer.offset
            }
        }), 1)

    sdl.BindGPUFragmentSamplers(render_pass, 0,
        raw_data([]sdl.GPUTextureSamplerBinding{
            {
                texture = tex,
                sampler = render_info.canvas_sampler
            },

        }), 1)
    
    uniform_data := vub
    sdl.PushGPUVertexUniformData(cmd_buff, 0, &uniform_data, size_of(vub))

    sdl.DrawGPUPrimitives(render_pass, num_verts, 1, 0, 0)
    sdl.EndGPURenderPass(render_pass)

    sdl.PopGPUDebugGroup(cmd_buff)
    ok := sdl.SubmitGPUCommandBuffer(cmd_buff)
}

render_ui_elements :: proc(render_info: ^Render_Info, tex: ^sdl.GPUTexture, icon_tex: ^sdl.GPUTexture, num_indices: u32, vbuffer: ^Buffer_Portion, idxbuffer: ^Buffer_Portion, cts: []Contex_Switch) {
    ok: bool



    cmd_buff := sdl.AcquireGPUCommandBuffer(render_info.device)

    sdl.PushGPUDebugGroup(cmd_buff, "UI")

    color_target := sdl.GPUColorTargetInfo {
        texture = render_info.render_target,
        load_op = .LOAD,
        store_op = .STORE,
        clear_color = {0.1, 0.07, 0.08, 1.0}
    }

    color_targets := [?]sdl.GPUColorTargetInfo{color_target}
    
    render_pass := sdl.BeginGPURenderPass(cmd_buff, raw_data(color_targets[:]), 1, nil)


    sdl.BindGPUGraphicsPipeline(render_pass, render_info.pipeline_tex)
    sdl.BindGPUVertexBuffers(render_pass, 0,
        raw_data([]sdl.GPUBufferBinding{
            {
                buffer = vbuffer.vbuffer.buffer,
                offset = vbuffer.offset
            }
        }), 1)
    sdl.BindGPUIndexBuffer(render_pass,
        {
            buffer = idxbuffer.vbuffer.buffer,
            offset = idxbuffer.offset
        }, ._32BIT)
    sdl.BindGPUFragmentSamplers(render_pass, 0,
        raw_data([]sdl.GPUTextureSamplerBinding{
            {
                texture = tex,
                sampler = render_info.linear_sampler
            },
            {
                texture = icon_tex,
                sampler = render_info.linear_sampler
            }
        }), 2)
    
    sizew := render_info.render_target_info.width
    sizeh := render_info.render_target_info.height
    screen_size := Vec2{f32(sizew), f32(sizeh)}
    sdl.PushGPUVertexUniformData(cmd_buff, 0, &screen_size, size_of(screen_size))
    
    num: int = 0
    counter: int = 0
    for c in cts {
        // fmt.println(c)
        sdl.DrawGPUIndexedPrimitives(render_pass, u32(c.num_primitives) , 1, u32(num), 0, 0)
        sdl.SetGPUScissor(render_pass, c.scissor)
        num += c.num_primitives
        counter += 1
    }
    // fmt.printfln("scisor_ops: {} num: {} / {}", counter, num, num_indices)
    // sdl.SetGPUScissor(render_pass, {10, 10, 500, 300})
    sdl.DrawGPUIndexedPrimitives(render_pass, num_indices - u32(num) , 1, u32(num), 0, 0)
    // sdl.SetGPUScissor(render_pass, {210, 30, 200, 300})
    // sdl.DrawGPUIndexedPrimitives(render_pass, 100 , 1, 0, 0, 0)
    // sdl.SetGPUScissor(render_pass, {10,10, 200, 300})
    // sdl.DrawGPUIndexedPrimitives(render_pass, num_indices - 100 , 1, 0, 0, 0)

    sdl.EndGPURenderPass(render_pass)
    sdl.PopGPUDebugGroup(cmd_buff)
    ok = sdl.SubmitGPUCommandBuffer(cmd_buff); assert(ok)
}

create_shader :: proc(device: ^sdl.GPUDevice, spirv_code: []byte, stage: shadercross.ShaderStage) -> ^sdl.GPUShader {
    metadata := shadercross.ReflectGraphicsSPIRV(raw_data(spirv_code), len(spirv_code), {})
    
    return shadercross.CompileGraphicsShaderFromSPIRV(
        device,
        {
            bytecode_size = len(spirv_code),
            bytecote = raw_data(spirv_code),
            entrypoint = "main",
            shader_stage = stage,
        },
        metadata.resource_info,
        {}
    )
}

Texture_Type :: enum {
    COLOR
}

MAX_TILE_ATLAS_SIZE :: 2048
MAX_ARRAY_TEX_SIZE :: 512
MAX_ARRAY_LAYERS :: 1000

Tile_Atlas :: struct {
    backing_texture : ^sdl.GPUTexture,
    tile_size: int,
    tiles: [dynamic]Texture_Tile,
}

Tile_Array :: struct {
    backing_texture: ^sdl.GPUTexture,
    tile_size: int,
    array_size: int,
}

create_tile_atlas :: proc(render_info: ^Render_Info, tile_size: int, tile_count: int) -> (res: Tile_Atlas, ok: bool) {
    device := render_info.device
    max_tiles: int = (MAX_TILE_ATLAS_SIZE / tile_size) * (MAX_TILE_ATLAS_SIZE / tile_size)
    if (tile_count > max_tiles) {
        log.errorf("Number of tiles too big for tile atlas. Requested: %v, Max: %v", tile_count, max_tiles)
        return {}, false
    }

    atlas: Tile_Atlas
    atlas.tile_size = tile_size

    tile_w, fract := math.modf(math.sqrt(f32(tile_count)))
    if fract > 0 do tile_w += 1
    tex_size: u32 = u32(int(tile_w) * tile_size)

    tex_info := sdl.GPUTextureCreateInfo{
        format = .R16G16B16A16_FLOAT,
        width = tex_size,
        height = tex_size,
        layer_count_or_depth = 1,
        num_levels = 1,
        type = .D2,
        usage = {.SAMPLER}
    }
    atlas.backing_texture = sdl.CreateGPUTexture(device, tex_info)
    
    tile_uv_step: f32 = (f32(tex_size) / tile_w) / f32(tex_size)
    assigned_count: int = 0
    for x in 0..<tile_w {
        for y in 0..<tile_w {
            if assigned_count >= tile_count {
                return atlas, true
            }
            xf := f32(x)
            yf := f32(y)
            rect: Rect = {
                pos = {xf*tile_uv_step, yf*tile_uv_step},
                size = {tile_uv_step, tile_uv_step}
            }
            append(&atlas.tiles, Texture_Tile{rect = rect, texture = atlas.backing_texture})
            assigned_count += 1
        }
    }
    if assigned_count >= tile_count {
        return atlas, true
    }

    return {}, false
}


create_tile_array :: proc(render_info: ^Render_Info, tile_size: int, tile_count: int) -> (res: Tile_Array, ok: bool) {
    device := render_info.device
    if (tile_count > MAX_ARRAY_LAYERS) {
        log.errorf("Number of tiles too big for tile atlas. Requested: %v, Max: %v", tile_count, MAX_ARRAY_LAYERS)
        return {}, false
    }
    if (tile_size > MAX_ARRAY_TEX_SIZE) {
        log.errorf("Tile size too big. Requested: %v, Max: %v", tile_size, MAX_ARRAY_TEX_SIZE)
        return {}, false
    }

    tile_array: Tile_Array
    tile_array.tile_size = tile_size


    tex_info := sdl.GPUTextureCreateInfo{
        format = .R16G16B16A16_FLOAT,
        width = u32(tile_size),
        height = u32(tile_size),
        layer_count_or_depth = u32(tile_count),
        num_levels = 1,
        type = .D2_ARRAY,
        usage = {.SAMPLER}
    }
    tile_array.backing_texture = sdl.CreateGPUTexture(device, tex_info)
    tile_array.array_size = tile_count

    return tile_array, true
}

load_texture :: proc(device: ^sdl.GPUDevice, file: cstring, type: Texture_Type = .COLOR, mip_levels: u32 = 1) -> (^sdl.GPUTexture, sdl.GPUTextureCreateInfo) {
    img := image.Load(file)
    if img == nil {
        log.warnf("Couldn't load image \"%s\"", file)
        return nil, {}
    }
    convert_format: sdl.PixelFormat
    texture_format: sdl.GPUTextureFormat
    switch type {
        case .COLOR:
            convert_format = .RGBA32
            texture_format = .R8G8B8A8_UNORM_SRGB
    }
    img_convert := sdl.ConvertSurface(img, convert_format)
    w := u32(img.w)
    h := u32(img.h)

    usage: sdl.GPUTextureUsageFlags
    usage |= {.SAMPLER}
    if (mip_levels > 1) {
        usage |= {.COLOR_TARGET}
    }

    tex_info := sdl.GPUTextureCreateInfo{
            format = texture_format,
            width = w,
            height = h,
            layer_count_or_depth = 1,
            num_levels = mip_levels,
            type = .D2,
            usage = usage,
        }
    tex := sdl.CreateGPUTexture(device, tex_info)

    tex_size := sdl.CalculateGPUTextureFormatSize(texture_format, w, h, 1)

    transfer_buffer := sdl.CreateGPUTransferBuffer(
        device,
        {
            usage = .UPLOAD,
            size = tex_size
        }
    )

    transfer_ptr := sdl.MapGPUTransferBuffer(device, transfer_buffer, false)
    mem.copy_non_overlapping(transfer_ptr, img_convert.pixels, int(tex_size))
    sdl.UnmapGPUTransferBuffer(device, transfer_buffer)

    cmdbuf := sdl.AcquireGPUCommandBuffer(device)
    copy_pass := sdl.BeginGPUCopyPass(cmdbuf)

    sdl.UploadToGPUTexture(copy_pass,
        {
            transfer_buffer = transfer_buffer
        },
        {
            texture = tex,
            d = 1,
            w = w,
            h = h,
        }, false)
    sdl.EndGPUCopyPass(copy_pass)
    ok := sdl.SubmitGPUCommandBuffer(cmdbuf); assert(ok)
    sdl.ReleaseGPUTransferBuffer(device, transfer_buffer)

    if (mip_levels > 1) {
        gen_mips := sdl.AcquireGPUCommandBuffer(device)
        sdl.GenerateMipmapsForGPUTexture(gen_mips, tex)
        ok = sdl.SubmitGPUCommandBuffer(gen_mips); assert(ok)
    }
    return tex, tex_info
}

align_matrix3 :: proc(mat: Matrix3) -> (out: Matrix3align) {
    out[0].xyz = mat[0]
    out[1].xyz = mat[1]
    out[2].xyz = mat[2]
    return out
}