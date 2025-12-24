#version 460

layout(location=0) in vec2 uv;
layout(location=0) out vec4 color;

layout(set=2, binding=0) uniform sampler2D tex;

void main() {
    color = texture(tex, uv);
    if (color.a < 0.1) {
        discard;
    }
}