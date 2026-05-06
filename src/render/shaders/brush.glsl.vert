#version 460

layout(set=1, binding=0) uniform UBO {
    mat3 cam;
    int width;
    int height;
    int tile_size;
    int brush_size;
};

layout(location=0) in vec2 pos;
layout(location=1) in vec2 uv;
layout(location=2) in uint layer;

layout(location=0) out uint out_layer;
layout(location=1) out vec2 out_uv;



void main() {
    out_layer = layer;
    out_uv = uv;

    // mat3 cam2 = mat3(1) * 0.001;
    gl_Position = vec4(cam * vec3(pos, 1.0), 1.0);
}