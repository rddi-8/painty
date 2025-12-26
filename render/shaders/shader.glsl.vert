#version 460

layout(set=1, binding=0) uniform UBO {
    mat3 cam;
};

layout(location = 0) in vec2 position;
layout(location = 1) in vec2 uv;

layout(location = 0) out vec2 out_uv;

void main() {
    out_uv = uv;
    vec3 pos = vec3(position.xy, 1.0);
    mat3 id = mat3(1.0);
    pos = cam * pos;
    gl_Position = vec4(pos, 1.0);

}