#version 460 core

layout (location = 0) in vec3 in_position;
layout (location = 1) in vec4 in_color;

out vec4 Color;

void main() {
	Color = in_color;
	gl_Position = vec4(in_position, 1.0);
}
