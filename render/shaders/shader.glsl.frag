#version 460

layout(location=0) in vec2 uv;
layout(location=1) in vec4 in_color;

layout(location=0) out vec4 color;

layout(set=2, binding=0) uniform sampler2D tex;

void main() {
    if (uv.x < 0)
    {
        color = in_color;
    }
    else
    {
        color = texture(tex, uv) * in_color;
    }
}