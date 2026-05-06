#version 460 core

layout (location = 0) in vec2 in_position;
layout (location = 1) in vec4 in_color;
layout (location = 2) in vec2 in_center;
layout (location = 3) in vec2 in_radius_inner;
layout (location = 4) in vec2 in_radius_outer;

out vec4 Color;
out vec2 Position;
out vec2 Center;
out vec2 RadiusInner;
out vec2 RadiusOuter;

void main() {
	Color = in_color;
	Center = in_center;
	RadiusInner = in_radius_inner;
	RadiusOuter = in_radius_outer;
	gl_Position = vec4(in_position, 0.0, 1.0);
	Position = in_position.xy;
}
