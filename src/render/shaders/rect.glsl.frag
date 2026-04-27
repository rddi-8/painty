#version 460

layout(location=0) flat in uint in_layer;
layout(location=1) in vec2 uv;

layout(location=0) out vec4 color;

layout(set=2, binding=0) uniform sampler2DArray tiles;

void main() {
    color = texture(tiles, vec3(uv, in_layer));
}