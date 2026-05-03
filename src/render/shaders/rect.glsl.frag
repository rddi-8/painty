#version 460

layout(location=0) flat in uint in_layer;
layout(location=1) in vec2 uv;

layout(location=0) out vec4 color;

layout(set=2, binding=0) uniform sampler2DArray tiles;

vec3 linear_to_srgb(vec3 c) {
    bvec3 cutoff = lessThanEqual(c, vec3(0.0031308));
    vec3 linear_part = c * 12.92;
    vec3 pow_part = 1.055 * pow(c, vec3(1.0/2.4)) - 0.055;
    return mix(pow_part, linear_part, cutoff);
}

void main() {
    vec4 linear_color = texture(tiles, vec3(uv, in_layer));
    color = vec4(linear_to_srgb(linear_color.rgb), linear_color.a);
}