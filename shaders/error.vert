#version 460 core

layout (location = 0) in vec3 in_position;
layout (location = 1) in vec3 in_normal;

layout (std140, binding = 0) uniform Camera {
	mat4 view;
	mat4 projection;
};

layout (location = 0) uniform mat4 model;

void main() {
	gl_Position = projection * view * model * vec4(in_position, 1.0);
}
