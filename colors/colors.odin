package colors

import "core:math"

Color :: [4]f16
Opaque :: [3]f16
Color8 :: [4]u8
Color32 :: [4]f32
Opaque32 :: [3]f32

@(require_results)
col8_to_color :: proc(in_col: Color8) -> Color {
    return {
        f16(in_col.r) / 255,
        f16(in_col.g) / 255,
        f16(in_col.b) / 255,
        f16(in_col.a) / 255,
    }
}

@(require_results)
opaque_to_color :: proc(in_col: Opaque) -> Color {
    return {in_col.r, in_col.g, in_col.b, 1}
}

@(require_results)
col32_to_color :: proc(in_col: Color32) -> Color {
    return {
        f16(in_col.r),
        f16(in_col.g),
        f16(in_col.b),
        f16(in_col.a),
    }
}

to_color :: proc {
    col8_to_color,
    opaque_to_color,
    col32_to_color,
}

@(require_results)
color_to_col8 :: proc(in_col: Color) -> Color8 {
    return {
        u8(in_col.r * 255),
        u8(in_col.g * 255),
        u8(in_col.b * 255),
        u8(in_col.a * 255),
    }
}

to_col8 :: proc {
    color_to_col8,
}

@(require_results)
color_to_col32 :: proc(in_col: Color) -> Color32 {
    return {
        f32(in_col.r),
        f32(in_col.g),
        f32(in_col.b),
        f32(in_col.a),
    }
}

to_col32 :: proc {
    color_to_col8,
}

to_linear :: proc(c: [3]f32) -> [3]f32 {
    return {
        srgb_to_linear(c.r),
        srgb_to_linear(c.g),
        srgb_to_linear(c.b),
    }
}

to_srgb :: proc(c: [3]f32) -> [3]f32 {
    return {
        linear_to_srgb(c.r),
        linear_to_srgb(c.g),
        linear_to_srgb(c.b),
    }
} 

srgb_to_linear :: proc(c: f32) -> f32 {
    if c <= 0.04045 {
        return c / 12.92
    }
    return math.pow((c + 0.055) / 1.055, 2.4)
}

linear_to_srgb :: proc(c: f32) -> f32 {
    if c <= 0.0031308 {
        return c * 12.92
    }
    return 1.055 * math.pow(c, 1.0/2.4) - 0.055
}

RGB :: distinct [3]f32
Lab :: distinct struct {
    L,a,b :f32
}

cbrtf :: proc(x: f32) -> f32 {
    return math.pow(x, 1.0/3.0)
}

linear_srgb_to_oklab :: proc(c: RGB) -> Lab
{
    l : f32 = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b
	m : f32 = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b
	s : f32 = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b

    l_: f32 = cbrtf(l);
    m_: f32 = cbrtf(m);
    s_: f32 = cbrtf(s);

    return {
        0.2104542553*l_ + 0.7936177850*m_ - 0.0040720468*s_,
        1.9779984951*l_ - 2.4285922050*m_ + 0.4505937099*s_,
        0.0259040371*l_ + 0.7827717662*m_ - 0.8086757660*s_,
    };
}

oklab_to_linear_srgb :: proc(c: Lab) -> RGB
{
    l_: f32  = c.L + 0.3963377774 * c.a + 0.2158037573 * c.b;
    m_: f32  = c.L - 0.1055613458 * c.a - 0.0638541728 * c.b;
    s_: f32  = c.L - 0.0894841775 * c.a - 1.2914855480 * c.b;

    l : f32 = l_*l_*l_;
    m : f32 = m_*m_*m_;
    s : f32 = s_*s_*s_;

    return {
		+4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
		-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
		-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
    };
}