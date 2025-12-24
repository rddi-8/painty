package whatde

import "core:mem"
import "base:runtime"
import "core:log"
import sdl "vendor:sdl3"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "shadercross"

//general types
SizeU32 :: struct {
    w, h: u32
}

Vec2 :: linalg.Vector2f32
Color :: linalg.Vector4f32

Vertex_Data :: struct {
    pos: Vec2,
    color: Color
}

Program_State_Flags :: enum {
    QUIT
}
program_state : bit_set[Program_State_Flags]

WIDTH :: 600
HEIGHT :: 400

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

    window := sdl.CreateWindow("hmmm", WIDTH, HEIGHT, {}); assert(window != nil)
    gpu := sdl.CreateGPUDevice({.SPIRV}, true, nil); assert(gpu != nil)
    ok = sdl.ClaimWindowForGPUDevice(gpu, window); assert(ok)

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

    vert_metadata := shadercross.ReflectGraphicsSPIRV(raw_data(vert_shader_spirv), len(vert_shader_spirv), {})
    vert_shader := shadercross.CompileGraphicsShaderFromSPIRV(
        gpu,
        {
            bytecode_size = len(vert_shader_spirv),
            bytecote = raw_data(vert_shader_spirv),
            entrypoint = "main",
            shader_stage = .SDL_SHADERCROSS_SHADERSTAGE_VERTEX,
        },
        vert_metadata.resource_info,
        {}
    )

    frag_metadata := shadercross.ReflectGraphicsSPIRV(raw_data(frag_shader_spirv), len(frag_shader_spirv), {})
    frag_shader := shadercross.CompileGraphicsShaderFromSPIRV(
        gpu,
        {
            bytecode_size = len(frag_shader_spirv),
            bytecote = raw_data(frag_shader_spirv),
            entrypoint = "main",
            shader_stage = .SDL_SHADERCROSS_SHADERSTAGE_FRAGMENT,
        },
        frag_metadata.resource_info,
        {}
    )

    vertices := []Vertex_Data{
        { pos = {-0.8, -0.8}, color = {1, 0, 0, 1} },
        { pos = { 0.8, -0.8}, color = {0, 1, 0, 1} },
        { pos = {-0.8,  0.8}, color = {0, 0, 1, 1} },

        { pos = { 0.8, -0.8}, color = {0, 1, 0, 1} },
        { pos = { 0.8,  0.8}, color = {1, 0, 0, 1} },
        { pos = {-0.8,  0.8}, color = {0, 0, 1, 1} },
    }
  
    vertices_size := len(vertices) * size_of(Vertex_Data)

    vertex_buf := sdl.CreateGPUBuffer(
        gpu,
        {
            usage = {.VERTEX},
            size = u32(vertices_size),
        }
    )


    transfer_buffer := sdl.CreateGPUTransferBuffer(gpu, {
        usage = .UPLOAD,
        size = u32(vertices_size)
    })

    transfer_ptr := sdl.MapGPUTransferBuffer(gpu, transfer_buffer, false)
    mem.copy_non_overlapping(transfer_ptr, raw_data(vertices), vertices_size)
    mem.copy_non_overlapping(transfer_ptr, raw_data(vertices), vertices_size)
    sdl.UnmapGPUTransferBuffer(gpu, transfer_buffer)

    copy_cmd := sdl.AcquireGPUCommandBuffer(gpu)
    copy_pass := sdl.BeginGPUCopyPass(copy_cmd)
    sdl.UploadToGPUBuffer(copy_pass, {transfer_buffer = transfer_buffer, offset = 0}, {buffer = vertex_buf, offset = 0, size = u32(vertices_size)}, false)
    sdl.EndGPUCopyPass(copy_pass)
    ok = sdl.SubmitGPUCommandBuffer(copy_cmd); assert(ok)

    vertex_attrs := []sdl.GPUVertexAttribute {
        {
            location = 0,
            format = .FLOAT2,
            offset = u32(offset_of(Vertex_Data, pos))
        },
        {
            location = 1,
            format = .FLOAT4,
            offset = u32(offset_of(Vertex_Data, color))
        }
    }

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

        render(gpu, window, pipeline, vertex_buf)

        if .QUIT in program_state do break main_loop
    }

    sdl.Quit()
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

render :: proc(gpu: ^sdl.GPUDevice, window: ^sdl.Window, pipeline: ^sdl.GPUGraphicsPipeline, v_buff: ^sdl.GPUBuffer) {
    cmd_buff := sdl.AcquireGPUCommandBuffer(gpu)
    swapchain_tex: ^sdl.GPUTexture
    swapchain_size: SizeU32
    ok := sdl.WaitAndAcquireGPUSwapchainTexture(cmd_buff, window, &swapchain_tex, &swapchain_size.w, &swapchain_size.h); assert(ok)
    
    color_target1 := sdl.GPUColorTargetInfo {
        texture = swapchain_tex,
        load_op = .CLEAR,
        clear_color = {0.1, f32(math.mod(time, 1.0)), 0.15, 1},
        store_op = .STORE
    }

    color_targets := [?]sdl.GPUColorTargetInfo{color_target1}

    render_pass := sdl.BeginGPURenderPass(cmd_buff, &color_targets[0], 1, nil)

    sdl.BindGPUGraphicsPipeline(render_pass, pipeline)

    
    sdl.BindGPUVertexBuffers(render_pass, 0, &sdl.GPUBufferBinding{
        buffer = v_buff,
        offset = 0
    }, 1 )

    sdl.DrawGPUPrimitives(render_pass, 6, 1, 0, 0)
    
    sdl.EndGPURenderPass(render_pass)

    ok = sdl.SubmitGPUCommandBuffer(cmd_buff); assert(ok)

}

load_shader :: proc(device: ^sdl.GPUDevice, code: []byte, stage: sdl.GPUShaderStage) -> ^sdl.GPUShader {
    return sdl.CreateGPUShader(
        device,
        {
            code_size = len(code),
            code = raw_data(code),
            entrypoint = "main",
            format = {.SPIRV},
            stage = stage
        }
    )
}