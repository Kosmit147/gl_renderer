#version 460 core

layout (location = 0) in vec3 in_position;
layout (location = 1) in vec3 in_normal;
layout (location = 2) in vec2 in_uv;

out vec2 UV;
out vec3 AmbientDiffuse;

layout (std140, binding = 0) uniform Camera {
	mat4 view;
	mat4 projection;
};

layout (std430, binding = 1) readonly buffer Light {
	vec3 light_ambient;
	vec3 light_direction;
	vec3 light_diffuse;
};

layout (location = 0) uniform mat4 model;

vec3 ambient() {
	return light_ambient;
}

vec3 diffuse(vec3 normal, vec3 light_direction) {
	float d = dot(normal, -light_direction);
	d = clamp(d, 0.0, 1.0);
	return d * light_diffuse;
}

void main() {
	UV = in_uv;
	AmbientDiffuse = ambient() + diffuse(in_normal, light_direction);
	gl_Position = projection * view * model * vec4(in_position, 1.0);
}
