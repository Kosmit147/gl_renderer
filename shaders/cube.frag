#version 460 core

in vec2 UV;

out vec4 out_color;

uniform vec4 color;
layout (binding = 0) uniform sampler2D texture0;

void main() {
	out_color = texture(texture0, UV) * color;
}
