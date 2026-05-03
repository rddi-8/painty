package color

import "core:math"

Color :: [4]f16
Opaque :: [3]f16
Color8 :: [4]u8
Color32 :: [4]f32
Opaque32 :: [3]f32

@(require_results)
col8_to_color :: proc "contextless" (in_col: Color8) -> Color {
    return {
        f16(in_col.r) / 255,
        f16(in_col.g) / 255,
        f16(in_col.b) / 255,
        f16(in_col.a) / 255,
    }
}

@(require_results)
opaque_to_color :: proc "contextless" (in_col: Opaque) -> Color {
    return {in_col.r, in_col.g, in_col.b, 1}
}

@(require_results)
col32_to_color :: proc "contextless" (in_col: Color32) -> Color {
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
color_to_col8 :: proc "contextless" (in_col: Color) -> Color8 {
    return {
        u8(in_col.r * 255),
        u8(in_col.g * 255),
        u8(in_col.b * 255),
        u8(in_col.a * 255),
    }
}

@(require_results)
col32_to_col8 :: proc "contextless" (in_col: Color32) -> Color8 {
    return {
        u8(in_col.r * 255),
        u8(in_col.g * 255),
        u8(in_col.b * 255),
        u8(in_col.a * 255),
    }
}

to_col8 :: proc {
    color_to_col8,
    col32_to_col8,
}

@(require_results)
color_to_col32 :: proc "contextless" (in_col: Color) -> Color32 {
    return {
        f32(in_col.r),
        f32(in_col.g),
        f32(in_col.b),
        f32(in_col.a),
    }
}

to_col32 :: proc {
    color_to_col32,
}

to_linear_rgb :: proc "contextless" (c: [3]f32) -> [3]f32 {
    return {
        srgb_to_linear(c.r),
        srgb_to_linear(c.g),
        srgb_to_linear(c.b),
    }
}
to_linear_rgba :: proc "contextless" (c: [4]f32) -> [4]f32 {
    col: Color32
	col.rgb = {
        srgb_to_linear(c.r),
        srgb_to_linear(c.g),
        srgb_to_linear(c.b),
    }
	col.a = c.a
	return col
}
to_linear_rgb16 :: proc "contextless" (c: [3]f16) -> [3]f16 {
    return {
        f16(srgb_to_linear(f32(c.r))),
        f16(srgb_to_linear(f32(c.g))),
        f16(srgb_to_linear(f32(c.b))),
    }
}
to_linear_rgba16 :: proc "contextless" (c: [4]f16) -> [4]f16 {
    col: Color32
	col.rgb = {
        srgb_to_linear(f32(c.r)),
        srgb_to_linear(f32(c.g)),
        srgb_to_linear(f32(c.b)),
    }
	col.a = f32(c.a)
	return to_color(col)
}

to_linear :: proc{
	to_linear_rgb,
	to_linear_rgba,
	to_linear_rgb16,
	to_linear_rgba16,
}

to_srgb :: proc "contextless" (c: [3]f32) -> [3]f32 {
    return {
        linear_to_srgb(c.r),
        linear_to_srgb(c.g),
        linear_to_srgb(c.b),
    }
} 

srgb_to_linear :: proc "contextless" (c: f32) -> f32 {
    if c <= 0.04045 {
        return c / 12.92
    }
    return math.pow((c + 0.055) / 1.055, 2.4)
}

linear_to_srgb :: proc "contextless" (c: f32) -> f32 {
    if c <= 0.0031308 {
        return c * 12.92
    }
    return 1.055 * math.pow(c, 1.0/2.4) - 0.055
}

srgb_transfer_function :: proc "contextless" (a: f32) -> f32
{
	return .0031308 >= a ? 12.92 * a : 1.055 * math.pow(a, .4166666666666667) - .055;
}

srgb_transfer_function_inv :: proc "contextless" (a: f32) -> f32
{
	return .04045 < a ? math.pow((a + .055) / 1.055, 2.4) : a / 12.92;
}

RGB :: distinct [3]f32
Lab :: distinct struct {
    L,a,b :f32
}

cbrtf :: proc "contextless" (x: f32) -> f32 {
    return math.pow(x, 1.0/3.0)
}

linear_srgb_to_oklab :: proc "contextless" (c: RGB) -> Lab
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

oklab_to_linear_srgb :: proc "contextless" (c: Lab) -> RGB
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

HSL :: struct { h,s,l: f32 };
HSV :: struct { h,s,v: f32 };
LC :: struct { L,C: f32 };

// Alternative representation of (L_cusp, C_cusp)
// Encoded so S = C_cusp/L_cusp and T = C_cusp/(1-L_cusp) 
// The maximum value for C in the triangle is then found as fmin(S*L, T*(1-L)), for a given L
ST :: struct { S,T: f32 };

// toe function for L_r
toe :: proc "contextless" (x: f32) -> f32
{
	k_1 :: 0.206
	k_2 :: 0.03
	k_3 :: (1 + k_1) / (1 + k_2)
	return 0.5 * (k_3 * x - k_1 + math.sqrt((k_3 * x - k_1) * (k_3 * x - k_1) + 4 * k_2 * k_3 * x));
}

// inverse toe function for L_r
toe_inv :: proc "contextless" (x: f32) -> f32
{
    k_1 :: 0.206;
    k_2 :: 0.03;
    k_3 :: (1 + k_1) / (1 + k_2);
	return (x * x + k_1 * x) / (k_3 * (x + k_2));
}

to_ST :: proc "contextless" (cusp: LC) -> ST
{
	return { cusp.C / cusp.L, cusp.C / (1 - cusp.L) };
}
// Returns a smooth approximation of the location of the cusp
// This polynomial was created by an optimization process
// It has been designed so that S_mid < S_max and T_mid < T_max
get_ST_mid :: proc "contextless" (a_, b_: f32) -> ST
{
	S: f32 = 0.11516993 + 1 / (
        7.44778970 + 4.15901240 * b_ +
		a_ * (-2.19557347 + 1.75198401 * b_ +
			a_ * (-2.13704948 - 10.02301043 * b_ +
				a_ * (-4.24894561 + 5.38770819 * b_ + 4.69891013 * a_
					)))
		);

	T: f32 = 0.11239642 + 1 / (
		1.61320320 - 0.68124379 * b_ +
		a_ * (+0.40370612 + 0.90148123 * b_ +
			a_ * (-0.27087943 + 0.61223990 * b_ +
				a_ * (+0.00299215 - 0.45399568 * b_ - 0.14661872 * a_
					)))
		);

	return { S, T };
}

compute_max_saturation :: proc "contextless" (a, b: f32) -> f32
{
	// Max saturation will be when one of r, g or b goes below zero.

	// Select different coefficients depending on which component goes below zero first
	k0, k1, k2, k3, k4, wl, wm, ws: f32;

	if (-1.88170328 * a - 0.80936493 * b > 1)
	{
		// Red component
		k0 = +1.19086277; k1 = +1.76576728; k2 = +0.59662641; k3 = +0.75515197; k4 = +0.56771245;
		wl = +4.0767416621; wm = -3.3077115913; ws = +0.2309699292;
	}
	else if (1.81444104 * a - 1.19445276 * b > 1)
	{
		// Green component
		k0 = +0.73956515; k1 = -0.45954404; k2 = +0.08285427; k3 = +0.12541070; k4 = +0.14503204;
		wl = -1.2684380046; wm = +2.6097574011; ws = -0.3413193965;
	}
	else
	{
		// Blue component
		k0 = +1.35733652; k1 = -0.00915799; k2 = -1.15130210; k3 = -0.50559606; k4 = +0.00692167;
		wl = -0.0041960863; wm = -0.7034186147; ws = +1.7076147010;
	}

	// Approximate max saturation using a polynomial:
	S: f32 = k0 + k1 * a + k2 * b + k3 * a * a + k4 * a * b;

	// Do one step Halley's method to get closer
	// this gives an error less than 10e6, except for some blue hues where the dS/dh is close to infinite
	// this should be sufficient for most applications, otherwise do two/three steps 

	k_l: f32 = +0.3963377774 * a + 0.2158037573 * b;
	k_m: f32 = -0.1055613458 * a - 0.0638541728 * b;
	k_s: f32 = -0.0894841775 * a - 1.2914855480 * b;

	{
		l_: f32 = 1 + S * k_l;
		m_: f32 = 1 + S * k_m;
		s_: f32 = 1 + S * k_s;

		l: f32 = l_ * l_ * l_;
		m: f32 = m_ * m_ * m_;
		s: f32 = s_ * s_ * s_;

		l_dS: f32 = 3 * k_l * l_ * l_;
		m_dS: f32 = 3 * k_m * m_ * m_;
		s_dS: f32 = 3 * k_s * s_ * s_;

		l_dS2: f32 = 6 * k_l * k_l * l_;
		m_dS2: f32 = 6 * k_m * k_m * m_;
		s_dS2: f32 = 6 * k_s * k_s * s_;

		f: f32 = wl * l + wm * m + ws * s;
		f1: f32 = wl * l_dS + wm * m_dS + ws * s_dS;
		f2: f32 = wl * l_dS2 + wm * m_dS2 + ws * s_dS2;

		S = S - f * f1 / (f1 * f1 - 0.5 * f * f2);
	}

	return S;
}

find_cusp :: proc "contextless" (a,b: f32) -> LC
{
	// First, find the maximum saturation (saturation S = C/L)
	S_cusp: f32 = compute_max_saturation(a, b);

	// Convert to linear sRGB to find the first point where at least one of r,g or b >= 1:
	rgb_at_max: RGB = oklab_to_linear_srgb({ 1, S_cusp * a, S_cusp * b });
	L_cusp: f32 = cbrtf(1 / math.max(math.max(rgb_at_max.r, rgb_at_max.g), rgb_at_max.b))
	C_cusp: f32 = L_cusp * S_cusp;

	return { L_cusp , C_cusp };
}

// Finds intersection of the line defined by 
// L = L0 * (1 - t) + t * L1;
// C = t * C1;
// a and b must be normalized so a^2 + b^2 == 1
find_gamut_intersection :: proc "contextless" (a, b, L1, C1, L0: f32, cusp: LC) -> f32
{
	// Find the intersection for upper and lower half seprately
	t: f32;
	if (((L1 - L0) * cusp.C - (cusp.L - L0) * C1) <= 0)
	{
		// Lower half

		t = cusp.C * L0 / (C1 * cusp.L + cusp.C * (L0 - L1));
	}
	else
	{
		// Upper half

		// First intersect with triangle
		t = cusp.C * (L0 - 1) / (C1 * (cusp.L - 1) + cusp.C * (L0 - L1));

		// Then one step Halley's method
		{
			dL: f32 = L1 - L0;
			dC: f32 = C1;

			k_l: f32 = +0.3963377774 * a + 0.2158037573 * b;
			k_m: f32 = -0.1055613458 * a - 0.0638541728 * b;
			k_s: f32 = -0.0894841775 * a - 1.2914855480 * b;

			l_dt: f32 = dL + dC * k_l;
			m_dt: f32 = dL + dC * k_m;
			s_dt: f32 = dL + dC * k_s;


			// If higher accuracy is required, 2 or 3 iterations of the following block can be used:
			{
				L: f32 = L0 * (1 - t) + t * L1;
				C: f32 = t * C1;

				l_: f32 = L + C * k_l;
				m_: f32 = L + C * k_m;
				s_: f32 = L + C * k_s;

				l: f32 = l_ * l_ * l_;
				m: f32 = m_ * m_ * m_;
				s: f32 = s_ * s_ * s_;

				ldt: f32 = 3 * l_dt * l_ * l_;
				mdt: f32 = 3 * m_dt * m_ * m_;
				sdt: f32 = 3 * s_dt * s_ * s_;

				ldt2: f32 = 6 * l_dt * l_dt * l_;
				mdt2: f32 = 6 * m_dt * m_dt * m_;
				sdt2: f32 = 6 * s_dt * s_dt * s_;

				r: f32 = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s - 1;
				r1: f32 = 4.0767416621 * ldt - 3.3077115913 * mdt + 0.2309699292 * sdt;
				r2: f32 = 4.0767416621 * ldt2 - 3.3077115913 * mdt2 + 0.2309699292 * sdt2;

				u_r: f32 = r1 / (r1 * r1 - 0.5 * r * r2);
				t_r: f32 = -r * u_r;

				g: f32 = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s - 1;
				g1: f32 = -1.2684380046 * ldt + 2.6097574011 * mdt - 0.3413193965 * sdt;
				g2: f32 = -1.2684380046 * ldt2 + 2.6097574011 * mdt2 - 0.3413193965 * sdt2;

				u_g: f32 = g1 / (g1 * g1 - 0.5 * g * g2);
				t_g: f32 = -g * u_g;

				b: f32 = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s - 1;
				b1: f32 = -0.0041960863 * ldt - 0.7034186147 * mdt + 1.7076147010 * sdt;
				b2: f32 = -0.0041960863 * ldt2 - 0.7034186147 * mdt2 + 1.7076147010 * sdt2;

				u_b: f32 = b1 / (b1 * b1 - 0.5 * b * b2);
				t_b: f32 = -b * u_b;

				t_r = u_r >= 0 ? t_r : math.F32_MAX;
				t_g = u_g >= 0 ? t_g : math.F32_MAX;
				t_b = u_b >= 0 ? t_b : math.F32_MAX;

				t += math.min(t_r, math.min(t_g, t_b));
			}
		}
	}

	return t;
}


Cs :: struct {C_0, C_mid, C_max: f32}
get_Cs :: proc "contextless" (L, a_, b_: f32) -> Cs
{
	cusp: LC = find_cusp(a_, b_)

	C_max: f32 = find_gamut_intersection(a_, b_, L, 1, L, cusp)
	ST_max: ST = to_ST(cusp);
	
	// Scale factor to compensate for the curved part of gamut shape:
	k: f32 = C_max / math.min((L * ST_max.S), (1 - L) * ST_max.T)

	C_mid: f32
	{
		ST_mid: ST = get_ST_mid(a_, b_)

		// Use a soft minimum function, instead of a sharp triangle shape to get a smooth value for chroma.
		C_a: f32 = L * ST_mid.S
		C_b: f32 = (1 - L) * ST_mid.T
		C_mid = 0.9 * k * math.sqrt(math.sqrt(1 / (1 / (C_a * C_a * C_a * C_a) + 1 / (C_b * C_b * C_b * C_b))));
	}

	C_0: f32
	{
		// for C_0, the shape is independent of hue, so ST are constant. Values picked to roughly be the average values of ST.
		C_a: f32 = L * 0.4;
		C_b: f32 = (1 - L) * 0.8;

		// Use a soft minimum function, instead of a sharp triangle shape to get a smooth value for chroma.
		C_0 = math.sqrt(1 / (1 / (C_a * C_a) + 1 / (C_b * C_b)));
	}

	return { C_0, C_mid, C_max };
}

okhsl_to_srgb :: proc "contextless" (hsl: HSL) -> RGB
{
	h: f32 = hsl.h;
	s: f32 = hsl.s;
	l: f32 = hsl.l;

	if (l == 1.0)
	{
		return { 1, 1, 1 };
	}
	else if (l == 0)
	{
		return { 0, 0, 0 };
	}

	a_: f32 = math.cos(2 * math.PI * h);
	b_: f32 = math.sin(2 * math.PI * h);
	L : f32 = toe_inv(l);

	cs: Cs = get_Cs(L, a_, b_);
	C_0: f32 = cs.C_0;
	C_mid: f32 = cs.C_mid;
	C_max: f32 = cs.C_max;

    // Interpolate the three values for C so that:
    // At s=0: dC/ds = C_0, C=0
    // At s=0.8: C=C_mid
    // At s=1.0: C=C_max

	mid: f32 = 0.8
	mid_inv: f32 = 1.25

	C, t, k_0, k_1, k_2: f32

	if (s < mid)
	{
		t = mid_inv * s;

		k_1 = mid * C_0;
		k_2 = (1 - k_1 / C_mid);

		C = t * k_1 / (1 - k_2 * t);
	}
	else
	{
		t = (s - mid)/ (1 - mid);

		k_0 = C_mid;
		k_1 = (1 - mid) * C_mid * C_mid * mid_inv * mid_inv / C_0;
		k_2 = (1 - (k_1) / (C_max - C_mid));

		C = k_0 + t * k_1 / (1 - k_2 * t);
	}

	rgb :RGB = oklab_to_linear_srgb({ L, C * a_, C * b_ });
	return {
		srgb_transfer_function(rgb.r),
		srgb_transfer_function(rgb.g),
		srgb_transfer_function(rgb.b),
	};
}

srgb_to_okhsl :: proc "contextless" (rgb: RGB) -> HSL
{
	lab: Lab = linear_srgb_to_oklab({
		srgb_transfer_function_inv(rgb.r),
		srgb_transfer_function_inv(rgb.g),
		srgb_transfer_function_inv(rgb.b)
		});

	C: f32 = math.sqrt(lab.a * lab.a + lab.b * lab.b);
	a_: f32 = lab.a / C;
	b_: f32 = lab.b / C;

	L: f32 = lab.L;
	h: f32 = 0.5 + 0.5 * math.atan2(-lab.b, -lab.a) / math.PI;

	cs: Cs = get_Cs(L, a_, b_);
	C_0: f32 = cs.C_0;
	C_mid: f32 = cs.C_mid;
	C_max: f32 = cs.C_max;

    // Inverse of the interpolation in okhsl_to_srgb:

	mid: f32 = 0.8;
	mid_inv: f32 = 1.25;

	s: f32;
	if (C < C_mid)
	{
		k_1: f32 = mid * C_0
		k_2: f32 = (1 - k_1 / C_mid)

		t: f32 = C / (k_1 + k_2 * C)
		s = t * mid;
	}
	else
	{
		k_0: f32 = C_mid
		k_1: f32 = (1 - mid) * C_mid * C_mid * mid_inv * mid_inv / C_0
		k_2: f32 = (1 - (k_1) / (C_max - C_mid))

		t: f32 = (C - k_0) / (k_1 + k_2 * (C - k_0));
		s = mid + (1 - mid) * t;
	}

	l: f32 = toe(L);
	return { h, s, l };
}