#version 460

layout(location=0) in vec2 uv;
layout(location=0) out vec4 color;

layout(set=2, binding=0) uniform sampler2D tex;

void main() {
    vec3 c = texture(tex, uv).rgb;
    // c = pow(c, vec3(1/2.2));
    color = vec4(c, 1);
}