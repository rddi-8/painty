package shadercross

import "core:c"
import "vendor:sdl3"

foreign import lib "SDL3_shadercross.lib"

IOVarType :: enum c.int {
    UNKNOWN,
    INT8,
    UINT8,
    INT16,
    UINT16,
    INT32,
    UINT32,
    INT64,
    UINT64,
    FLOAT16,
    FLOAT32,
    FLOAT64
}

ShaderStage :: enum c.int {
    VERTEX,
    FRAGMENT,
    COMPUTE
}

IOVarMetadata :: struct {
    name: cstring,
    location: u32,
    vector_type: IOVarType,
    vector_size: u32
}

GraphicsShaderResourceInfo :: struct {
    num_smaplers: u32,
    num_storage_textures: u32,
    num_storage_buffers: u32,
    num_uniform_buffers: u32
}

GraphicsShaderMetadata :: struct {
    resource_info: GraphicsShaderResourceInfo,
    num_inputs: u32,
    inputs: [^]IOVarMetadata,
    num_outputs: u32,
    outputs: [^]IOVarMetadata
}

ComputePipelineMetadata :: struct {
    num_samplers: u32,
    num_readonly_storage_textures: u32,
    num_readonly_storage_buffers: u32,
    num_readwrite_storage_textures: u32,
    num_readwrite_storage_buffers: u32,
    num_uniform_buffers: u32,
    threadcount_x: u32,
    threadcount_y: u32,
    threadcount_z: u32
    
}

SPIRV_Info :: struct {
    bytecote: [^]byte,
    bytecode_size: c.size_t,
    entrypoint: cstring,
    shader_stage: ShaderStage,
    props: sdl3.PropertiesID
}

HLSL_Define :: struct {
    name: cstring,
    value: cstring
}

HLSL_Info :: struct {
    source: cstring,
    entrypoint: cstring,
    include_dir: cstring,
    defines: [^]HLSL_Define,
    shader_stage: ShaderStage,
    props: sdl3.PropertiesID
}

@(default_calling_convention="c", link_prefix="SDL_ShaderCross_")
foreign lib {
    Init :: proc() -> bool ---
    Quit :: proc() ---
    GetSPIRVShaderFormats :: proc() -> sdl3.GPUShaderFormat ---
    TranspileMSLFromSPIRV :: proc(#by_ptr info: SPIRV_Info) -> rawptr ---
    TranspileHLSLFromSPIRV :: proc(#by_ptr info: SPIRV_Info) -> rawptr ---
    CompileDXBCFromSPIRV :: proc(#by_ptr info: SPIRV_Info, size: ^c.size_t) -> rawptr ---
    CompileDXILFromSPIRV :: proc(#by_ptr info: SPIRV_Info, size: ^c.size_t) -> rawptr ---
    CompileGraphicsShaderFromSPIRV :: proc(device: ^sdl3.GPUDevice, #by_ptr info: SPIRV_Info, #by_ptr resource_info: GraphicsShaderResourceInfo, props: sdl3.PropertiesID) -> ^sdl3.GPUShader ---
    CompileComputePipelineFromSPIRV :: proc(device: ^sdl3.GPUDevice, #by_ptr info: SPIRV_Info, #by_ptr metadata: ComputePipelineMetadata, props: sdl3.PropertiesID) -> ^sdl3.GPUShader ---
    ReflectGraphicsSPIRV :: proc(bytecode: [^]byte, bytecode_size: c.size_t, props: sdl3.PropertiesID) -> ^GraphicsShaderMetadata ---
    ReflectComputeSPIRV :: proc(bytecode: [^]byte, bytecode_size: c.size_t, props: sdl3.PropertiesID) -> ^ComputePipelineMetadata ---
    GetHLSLShaderFormats :: proc() -> sdl3.GPUShaderFormat ---
    CompileDXBCFFromHLSL :: proc(#by_ptr info: HLSL_Info, size: ^c.size_t) -> rawptr ---
    CompileDXILFromHLSL :: proc(#by_ptr info: HLSL_Info, size: ^c.size_t) -> rawptr ---
    CompileSPIRVFromHLSL :: proc(#by_ptr info: HLSL_Info, size: ^c.size_t) -> rawptr ---
}