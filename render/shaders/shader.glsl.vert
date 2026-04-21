#version 460

// layout(set=1, binding=0) uniform UBO {
//     mat3 cam;
// };

layout(set=1, binding=0) uniform UBO {
    vec2 screen_size;
};

layout(location = 0) in vec2 position;
layout(location = 1) in vec2 uv;
layout(location = 2) in vec4 color;

layout(location = 0) out vec2 out_uv;
layout(location = 1) out vec4 out_color;

void main() {
    out_uv = uv;
    out_color.r = color.r;
    out_color.g = color.g;
    out_color.b = color.b;
    out_color.a = color.a;
    vec3 pos = vec3(position.xy/screen_size*2*vec2(1.0,-1.0) - vec2(1.0), 1.0)*vec3(1.0,-1.0,1.0);
    // mat3 id = mat3(1.0);
    // pos = cam * pos;
    gl_Position = vec4(pos, 1.0);

}