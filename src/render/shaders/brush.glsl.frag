#version 460

layout(location=0) flat in uint in_layer;
layout(location=1) in vec2 uv;


layout(location=0) out vec4 color;

layout(set=2, binding=0) uniform sampler2DArray tiles;
layout(set=2, binding=1) uniform sampler2D brush;

layout(set=3, binding=0) uniform UBO {
    mat3 cam;
    float scale;
    vec2 uv_max;
    int width;
    int height;
    int tile_size;
};

vec3 linear_to_srgb(vec3 c) {
    bvec3 cutoff = lessThanEqual(c, vec3(0.0031308));
    vec3 linear_part = c * 12.92;
    vec3 pow_part = 1.055 * pow(c, vec3(1.0/2.4)) - 0.055;
    return mix(pow_part, linear_part, cutoff);
}

void main() {
    // vec4 linear_color = texture(brush, uv);
    // color = vec4(linear_to_srgb(linear_color.rgb), linear_color.a);
    float px_size = 1.0/(1024*scale);
    float s = texture(brush, uv).r;
    float s_t = texture(brush, uv + vec2(0, -px_size)).r;
    float s_b = texture(brush, uv + vec2(0, +px_size)).r;
    float s_l = texture(brush, uv + vec2(-px_size, 0)).r;
    float s_r = texture(brush, uv + vec2(px_size, 0)).r;
    float edge = 0.5;
    float st = step(edge, s);
    float st_t = step(edge, s_t);
    float st_b = step(edge, s_b);
    float st_l = step(edge, s_l);
    float st_r = step(edge, s_r);
    vec4 col = vec4(0);
    if (uv.x > uv_max.x - 2*px_size || uv.y > uv_max.y - 2*px_size ) {
        col = vec4(0);
    }
    else if ( st < 0.5 && st_t + st_b + st_l + st_r > 0.5 ) {
        col = vec4(0.9,0.9,0.9, 0.7);
    }
    else if ( st > 0.5 && st_t + st_b + st_l + st_r < 3.5 ) {
        col = vec4(0.1,0.1,0.1, 0.7);
    }
    // color = vec4(scale/3,scale/3,scale/3,1);
    color = col;
    // color = vec4(1.0,0.0,0.0,1.0);
}