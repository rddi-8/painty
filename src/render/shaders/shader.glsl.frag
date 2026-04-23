#version 460

layout(location=0) in vec2 uv;
layout(location=1) in vec4 in_color;

layout(location=0) out vec4 color;

layout(set=2, binding=0) uniform sampler2D tex;
layout(set=2, binding=1) uniform sampler2D tex_icon;

void main() {
    vec4 glyph = texture(tex, uv);
    vec4 icon = texture(tex_icon, -uv);
    if (uv.x < 0)
    {
        color = icon * in_color;
    }
    else
    {
        color = glyph * in_color;
    }
}