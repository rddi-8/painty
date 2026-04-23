package lcms

import "core:c"

foreign import lib "lcms2.lib"

Signature :: distinct u32
U8Fixed8Number :: distinct u16
S15Fixed16Number :: distinct i32
U16Fixed16Number :: distinct u32

HANDLE :: distinct rawptr
HPROFILE :: distinct rawptr
HTRANSFORM :: distinct rawptr

Context :: distinct rawptr
ToneCurve :: distinct rawptr
MLU :: distinct rawptr
IOHANDLER :: distinct rawptr
NAMEDCOLORLIST :: distinct rawptr

ErrorCode :: enum u32 {
    UNDEFINED = 0,
    FILE,
    RANGE,
    INTERNAL,
    NULL,
    READ,
    SEEK,
    WRITE,
    UNKNOWN_EXTENSION,
    COLORSPACE_CHECK,
    ALREADY_DEFINED,
    BAD_SIGNATURE,
    CORRUPTION_DETECTED,
    NOT_SUITABLE
}

Intent :: enum u32 {
    PERCEPTUAL = 0,
    RELATIVE_COLORIMETRIC,
    SATURATION,
    ABSOLUTE_COLORIMETRIC
}

dwFlags :: enum u32 {
    NOCACHE = 0x0040,
    NOOPTIMIZE = 0x0100,
    NULLTRANSFORM = 0x0200,
    NONEGATIVES = 0x8000,
    COPY_ALPHA = 0x04000000,
    BLACKPOINTCOMPENSATION = 0x2000,
}

ColorSpace :: enum {
    PT_RGB = 4
}

Format :: distinct u32

format_float :: proc(fmt: ^Format, use_float: bool) {
    fmt^ |= Format(use_float) << 22
}
format_colorspace :: proc(fmt: ^Format, color_space: ColorSpace) {
    fmt^ |= Format(color_space) << 16
}
format_extra :: proc(fmt: ^Format, extra_samples: bool, do_swap: bool, endian16: bool) {
    fmt^ |= Format(extra_samples) << 7
    fmt^ |= Format(do_swap) << 10
    fmt^ |= Format(endian16) << 11
}
format_swap_first :: proc(fmt: ^Format, swap_first: bool) {
    fmt^ |= Format(swap_first) << 14
}
format_pixel :: proc(fmt: ^Format, bytes: int, channels: int) {
    fmt^ |= Format(bytes)
    fmt^ |= Format(channels) << 3
}

get_format_rgba16 :: proc() -> Format {
    fmt: Format = 0
    format_colorspace(&fmt, .PT_RGB)
    format_extra(&fmt, true, false, false)
    format_pixel(&fmt, 2, 3)
    return fmt
}

get_format_rgba8:: proc() -> Format {
    fmt: Format = 0
    format_colorspace(&fmt, .PT_RGB)
    format_extra(&fmt, true, false, false)
    format_pixel(&fmt, 1, 3)
    return fmt
}

get_format_rgb16 :: proc() -> Format {
    fmt: Format = 0
    format_colorspace(&fmt, .PT_RGB)
    format_pixel(&fmt, 2, 3)
    return fmt
}

get_format_rgb8:: proc() -> Format {
    fmt: Format = 0
    format_colorspace(&fmt, .PT_RGB)
    format_pixel(&fmt, 1, 3)
    return fmt
}

get_format_bgra8 :: proc() -> Format {
    fmt: Format = 0
    format_colorspace(&fmt, .PT_RGB)
    format_extra(&fmt, true , true, false)
    format_pixel(&fmt, 1, 3)
    format_swap_first(&fmt, true)
    return fmt
}

LogErrorHandlerFunction :: #type proc(ContextID: Context, ErrorCode: ErrorCode, text: cstring)

@(default_calling_convention="c", link_prefix="cms")
foreign lib {
    GetEncodedCMMversion :: proc() -> c.int ---
    SetLogErrorHandler :: proc(handler: LogErrorHandlerFunction) ---
    OpenProfileFromFile :: proc(ICCProfile: cstring, sAccess: cstring) -> HPROFILE ---
    OpenProfileFromMem :: proc(MemPtr: rawptr, size: u32) -> HPROFILE ---
    Create_sRGBProfile :: proc() -> HPROFILE ---
    CloseProfile :: proc(hProfile: HPROFILE) -> bool ---
    CreateTransform :: proc(Input: HPROFILE, InputFormat: Format, Output: HPROFILE, OutputFormat: Format, Intent: Intent, dwFlags: u32) -> HTRANSFORM ---
    DoTransform :: proc(hTransform: HTRANSFORM, InputBuffer: rawptr, OutputBuffer: rawptr, size: u32) ---
    DeleteTransform :: proc(hTransform: HTRANSFORM) ---
}