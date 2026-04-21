package render

import "core:fmt"
import "core:mem"
import "core:log"
import sdl "vendor:sdl3"

VBuffErrEnum :: enum {
    VBUFF_OUT_OF_CAPACITY,
    TBUFF_OUT_OF_CAPACITY,
    SRC_SIZE_TOO_LARGE,
    INVALID_GPU_DEVICE,
}
VBuffErr :: union {
    VBuffErrEnum
}

Virtual_Buffer :: struct {
    buffer: ^sdl.GPUBuffer,
    usage: sdl.GPUBufferUsageFlags,
    size: u32,
    pointer: u32
}

Buffer_Portion :: struct {
    vbuffer: ^Virtual_Buffer,
    offset, size: u32
}

Copy_Source :: struct {
    ptr: rawptr,
    size: u32
}

Transfer_Source :: struct {
    transfer_buffer: ^sdl.GPUTransferBuffer,
    offset, size: u32
}

Copy_Description :: struct {
    src: Copy_Source,
    dst: Buffer_Portion
}

create_vbuffer :: proc(device: ^sdl.GPUDevice, usage: sdl.GPUBufferUsageFlags, size: u32) -> ^Virtual_Buffer {
    gpu_buffer := sdl.CreateGPUBuffer(
        device,
        {
            usage = usage,
            size = size
        }
    )
    vbuff := new(Virtual_Buffer)
    vbuff.buffer = gpu_buffer
    vbuff.usage = usage
    vbuff.size = size
    vbuff.pointer = 0
    return vbuff
}

vbuffer_reserve_explicit :: proc(vbuffer: ^Virtual_Buffer, size: u32) -> (result: Buffer_Portion, err: VBuffErr) {
    // fmt.printfln("reserving %d + %d/%d", vbuffer.pointer, size, vbuffer.size)
    // fmt.println(vbuffer.size)
    if vbuffer.pointer + size > vbuffer.size {
        return {}, .VBUFF_OUT_OF_CAPACITY
    }
    else {
        result = {
            vbuffer = vbuffer,
            offset = vbuffer.pointer,
            size = size,
        }
        vbuffer.pointer += size
        return
    }
}

vbuffer_reserve_slice :: proc(vbuffer: ^Virtual_Buffer, data: $T/[]$E) -> (result: Buffer_Portion, err: VBuffErr) {
    // fmt.printfln("reserving %d/%d", size, vbuffer.size)
    size: u32 = (u32)(len(data) * size_of(E))
    if vbuffer.pointer + size > vbuffer.size {
        return {}, .VBUFF_OUT_OF_CAPACITY
    }
    else {
        result = {
            vbuffer = vbuffer,
            offset = vbuffer.pointer,
            size = size,
        }
        vbuffer.pointer += size
        return
    }
}

vbuffer_reserve :: proc{
    vbuffer_reserve_explicit,
    vbuffer_reserve_slice,
}

vbuffer_reset :: proc(vbuffer: ^Virtual_Buffer) {
    vbuffer.pointer = 0
}

vbuffer_batch_copy :: proc(render_info: ^Render_Info, batch: []Copy_Description) -> (err: VBuffErr) {
    device := render_info.device
    t_buff := render_info.transfer_buff

    t_sources: [dynamic]Transfer_Source

    t_ptr: = sdl.MapGPUTransferBuffer(device, t_buff, true)
    offset: u32 = 0

    for copy_op in batch {
        src := copy_op.src
        if offset + src.size > TRANSFER_BUFFER_SIZE {
            return .TBUFF_OUT_OF_CAPACITY
        }
        mem.copy_non_overlapping(ptr_offset(t_ptr, offset), src.ptr, int(src.size))
        append(&t_sources,
            Transfer_Source {
                transfer_buffer = t_buff,
                offset = offset,
                size = src.size
            })
        offset += src.size
    }

    sdl.UnmapGPUTransferBuffer(device, t_buff)

    copy_cmd := sdl.AcquireGPUCommandBuffer(device)
    copy_pass := sdl.BeginGPUCopyPass(copy_cmd)
    
    i: int = 0
    for copy_op in batch {
        dst := copy_op.dst
        src := t_sources[i]
        if src.size > dst.size {
            return .SRC_SIZE_TOO_LARGE
        }
        
        // fmt.println(sdl.GPUTransferBufferLocation{transfer_buffer = src.transfer_buffer, offset = src.offset},
        //     sdl.GPUBufferRegion{buffer = dst.vbuffer.buffer, offset = dst.offset, size = src.size})
        sdl.UploadToGPUBuffer(copy_pass,
            {transfer_buffer = src.transfer_buffer, offset = src.offset},
            {buffer = dst.vbuffer.buffer, offset = dst.offset, size = src.size},
            false
        )
        i += 1
    }
    delete(t_sources)
    sdl.EndGPUCopyPass(copy_pass)
    ok := sdl.SubmitGPUCommandBuffer(copy_cmd); assert(ok)

    return
}

