#version 460 core

layout (location = 0) in vec3 in_position;
layout (location = 1) in vec3 in_normal;
layout (location = 2) in vec2 in_uv;

out vec2 UV;

uniform mat4 projection;
uniform mat4 view;
uniform mat4 model;

void main() {
	UV = in_uv;
	gl_Position = projection * view * model * vec4(in_position, 1.0);
}
