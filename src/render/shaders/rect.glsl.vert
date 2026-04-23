#version 460

layout(set=1, binding=0) uniform UBO {
    vec2 screen_size;
};

layout(location=0) in vec2 pos;
layout(location=1) in vec2 uv;

layout(location=2) in vec2 rectPos;
layout(location=3) in vec2 rectSize;
layout(location=4) in vec4 color;

layout(location=0) out vec4 out_color;


void main() {
    out_color = color;
    gl_Position = vec4((rectPos + rectSize*pos)/screen_size*2 - vec2(1,1), 0, 1.0);
    gl_Position.y *= -1;
}