package whatde

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

VERTEX_BUFFER_SIZE : u32 :      8 * mem.Megabyte
TRANSFER_BUFFER_SIZE : u32 :    8 * mem.Megabyte

SizeU32 :: struct {
    w, h: u32
}

Vec2 :: linalg.Vector2f32
Color :: linalg.Vector4f32

Vertex_Data :: struct {
    pos: Vec2,
    uv: Vec2
}

Render_Info :: struct {
    texture: ^sdl.GPUTexture,
    texture2: ^sdl.GPUTexture,
    sampler: ^sdl.GPUSampler,
}

Program_State_Flags :: enum {
    QUIT
}
program_state : bit_set[Program_State_Flags]

WIDTH :: 600
HEIGHT :: 600

renderer: ^sdl.Renderer
window: ^sdl.Window

ticks: u64
time: f64

print_err :: proc() {
    fmt.printfln("SDL Error: {}", sdl.GetError())
}

main_context: runtime.Context

vert_shader_spirv := #load("shaders/shader.spv.vert")
frag_shader_spirv := #load("shaders/shader.spv.frag")


main :: proc() {
    context.logger = log.create_console_logger()
    sdl.SetLogPriorities(.VERBOSE)
    main_context =  context
    sdl.SetLogOutputFunction(proc "c" (userdata: rawptr, category: sdl.LogCategory, priority: sdl.LogPriority, message: cstring) {
        context = main_context
        log.debugf("SDL {} [{}]: {}", category, priority, message)
    }, nil)

    ok := sdl.Init({.VIDEO}); assert(ok)

    window := sdl.CreateWindow("hmmm", WIDTH, HEIGHT, {.RESIZABLE}); assert(window != nil)
    gpu := sdl.CreateGPUDevice({.SPIRV}, true, nil); assert(gpu != nil)
    ok = sdl.ClaimWindowForGPUDevice(gpu, window); assert(ok)
    ok = sdl.SetGPUSwapchainParameters(gpu, window, .SDR_LINEAR, .VSYNC); assert(ok)

    ok = shadercross.Init(); assert(ok)
    formats := shadercross.GetHLSLShaderFormats()
    fmt.println(formats)

    frag_res_info: shadercross.GraphicsShaderResourceInfo = {
        num_smaplers = 0,
        num_storage_buffers = 0,
        num_storage_textures = 0,
        num_uniform_buffers = 0
    }
    frag_spirv_info: shadercross.SPIRV_Info = {

    }

    vert_shader := create_shader(gpu, vert_shader_spirv, .VERTEX)

    frag_shader := create_shader(gpu, frag_shader_spirv, .FRAGMENT)

    vertices_size := 6 * 10 * size_of(Vertex_Data)

    vertex_buf := sdl.CreateGPUBuffer(
        gpu,
        {
            usage = {.VERTEX},
            size = VERTEX_BUFFER_SIZE,
        }
    )


    transfer_buffer := sdl.CreateGPUTransferBuffer(gpu, {
        usage = .UPLOAD,
        size = TRANSFER_BUFFER_SIZE
    })

    vertex_attrs := []sdl.GPUVertexAttribute {
        {   // POSITION
            location = 0,
            format = .FLOAT2,
            offset = u32(offset_of(Vertex_Data, pos))
        },
        {   // UV
            location = 1,
            format = .FLOAT2,
            offset = u32(offset_of(Vertex_Data, uv))
        }
    }

    sampler := sdl.CreateGPUSampler(
        gpu,
        {
            mag_filter = .LINEAR,
            min_filter = .LINEAR,
            address_mode_u = .REPEAT,
            address_mode_v = .REPEAT,
            mipmap_mode = .LINEAR,
        }
    )

    // load_texture(gpu, "sdsd.jpp")

    img_cpul := image.Load("img.jpg")
    img_cpu := sdl.ConvertSurface(img_cpul, .RGBA32)

    tex := load_texture(gpu, "img.jpg")
    tex_cirno := load_texture(gpu, "cirno_wplace.png")

    pipeline := sdl.CreateGPUGraphicsPipeline(
        gpu,
        {
            // vertex_shader = load_shader(gpu, vert_shader_spirv, .VERTEX),
            // fragment_shader = load_shader(gpu, frag_shader_spirv, .FRAGMENT),
            vertex_shader = vert_shader,
            fragment_shader = frag_shader,
            primitive_type = .TRIANGLELIST,
            vertex_input_state = {
                num_vertex_buffers = 1,
                vertex_buffer_descriptions = &sdl.GPUVertexBufferDescription {
                    slot = 0,
                    pitch = size_of(Vertex_Data),
                    input_rate = .VERTEX
                },
                num_vertex_attributes = u32(len(vertex_attrs)),
                vertex_attributes = raw_data(vertex_attrs)
            },
            target_info = {
                num_color_targets = 1,
                color_target_descriptions = &sdl.GPUColorTargetDescription{
                    format = sdl.GetGPUSwapchainTextureFormat(gpu, window),
                }
            }
        }
    )



    main_loop: for {
        ticks = sdl.GetTicksNS()
        time = f64(ticks) / 1_000_000_000

        handle_input()

        verts: [dynamic]Vertex_Data

        quad1 := make_quad({-0.2, -0.2}, {0.2, 0.2})
        quad2 := make_quad({-0.2, -0.2}, {0.2, 0.2})
        quad3 := make_quad({-0.9, 0.05}, {0.9, -0.05})

        // rot := linalg.matrix2_rotate_f32(f32(time))
        // rot3 := linalg.Matrix3x3f32(rot)
        // translate := linalg.MATRIX3F32_IDENTITY
        // translate[2][0] = math.sin(f32(time)) * 0.5
        // translate[2][1] = math.cos(f32(time)) * 0.5
        // for &point in quad {
        //     pos3: linalg.Vector3f32
        //     pos3.xy = point.pos.xy
        //     pos3.z = 1
        //     pos3 = translate * rot3 * pos3
        //     point.pos = pos3.xy
        // }

        quad_1 := xform_points(quad1[:], {math.sin(f32(time)) * 0.5, math.cos(f32(time)) * 0.5}, f32(time))
        quad_2 := xform_points(quad2[:], {-math.sin(f32(time)) * 0.2, -math.cos(f32(time)) * 0.2}, -f32(time))
        quad_3 := xform_points(quad3[:], {0, -math.cos(f32(time)) * 0.8}, 0)

        append(&verts, ..quad_1)
        append(&verts, ..quad_2)
        append(&verts, ..quad_3)

        render(gpu, window, pipeline, vertex_buf, transfer_buffer, verts[:], {texture = tex, sampler = sampler, texture2 = tex_cirno})

        delete(verts)

        if .QUIT in program_state do break main_loop
    }

    sdl.Quit()
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

handle_input :: proc() {
    ev: sdl.Event
    for sdl.PollEvent(&ev) {
        #partial switch ev.type {
            case .QUIT:
                program_state += {.QUIT}
                return
        }
    }
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

render :: proc(gpu: ^sdl.GPUDevice, window: ^sdl.Window, pipeline: ^sdl.GPUGraphicsPipeline, v_buff: ^sdl.GPUBuffer, transf_buf: ^sdl.GPUTransferBuffer, vertex_data: []Vertex_Data, info: Render_Info) {
    
    vertices_size := len(vertex_data) * size_of(Vertex_Data)

    transfer_ptr := sdl.MapGPUTransferBuffer(gpu, transf_buf, false)
    mem.copy_non_overlapping(transfer_ptr, raw_data(vertex_data), vertices_size)
    mem.copy_non_overlapping(transfer_ptr, raw_data(vertex_data), vertices_size)
    sdl.UnmapGPUTransferBuffer(gpu, transf_buf)

    copy_cmd := sdl.AcquireGPUCommandBuffer(gpu)
    copy_pass := sdl.BeginGPUCopyPass(copy_cmd)
    sdl.UploadToGPUBuffer(copy_pass, {transfer_buffer = transf_buf, offset = 0}, {buffer = v_buff, offset = 0, size = u32(vertices_size)}, false)
    sdl.EndGPUCopyPass(copy_pass)
    ok := sdl.SubmitGPUCommandBuffer(copy_cmd); assert(ok)
    
    
    
    cmd_buff := sdl.AcquireGPUCommandBuffer(gpu)
    swapchain_tex: ^sdl.GPUTexture
    swapchain_size: SizeU32
    ok = sdl.WaitAndAcquireGPUSwapchainTexture(cmd_buff, window, &swapchain_tex, &swapchain_size.w, &swapchain_size.h); assert(ok)
    
    color_target1 := sdl.GPUColorTargetInfo {
        texture = swapchain_tex,
        load_op = .CLEAR,
        clear_color = {0.1, 0.05, 0.15, 1},
        store_op = .STORE
    }

    color_targets := [?]sdl.GPUColorTargetInfo{color_target1}

    render_pass := sdl.BeginGPURenderPass(cmd_buff, &color_targets[0], 1, nil)

    sdl.BindGPUGraphicsPipeline(render_pass, pipeline)

    
    sdl.BindGPUVertexBuffers(render_pass, 0, &sdl.GPUBufferBinding{
        buffer = v_buff,
        offset = 0
    }, 1 )
    
    
    sdl.BindGPUFragmentSamplers(render_pass, 0,
        &sdl.GPUTextureSamplerBinding { sampler = info.sampler, texture = info.texture2}, 1)
        
    sdl.DrawGPUPrimitives(render_pass, 6, 1, 0, 0)

    sdl.BindGPUFragmentSamplers(render_pass, 0,
        &sdl.GPUTextureSamplerBinding { sampler = info.sampler, texture = info.texture}, 1)
        
    sdl.DrawGPUPrimitives(render_pass, 12, 1, 6, 0)
    
    sdl.EndGPURenderPass(render_pass)

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

load_texture :: proc(device: ^sdl.GPUDevice, file: cstring, type: Texture_Type = .COLOR) -> ^sdl.GPUTexture {
    img := image.Load(file)
    if img == nil {
        log.warnf("Couldn't load image \"%s\"", file)
        return nil
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

    tex := sdl.CreateGPUTexture(
        device,
        {
            format = texture_format,
            width = w,
            height = h,
            layer_count_or_depth = 1,
            num_levels = 1,
            type = .D2,
            usage = {.SAMPLER}
        }
    )

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
    return tex
}