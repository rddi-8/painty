#version 460

layout(location=0) in vec4 in_color;
layout(location=0) out vec4 color;

void main() {
    color = pow(in_color, vec4(1/2.2));
}