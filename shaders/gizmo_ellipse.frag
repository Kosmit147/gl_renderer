#version 460 core

in vec4 Color;
in vec2 Position;
in vec2 Center;
in vec2 RadiusInner;
in vec2 RadiusOuter;

out vec4 out_color;

void main() {
	vec4 color = Color;

	float x_squish = RadiusInner.y / RadiusInner.x;
	// float outer_x_squish = RadiusOuter.y / RadiusOuter.x;

	// float radius_inner_max = max(RadiusInner.x, RadiusInner.y);
	// float radius_outer_max = max(RadiusOuter.x, RadiusOuter.y);

	float dist_x = abs(Position.x - Center.x);
	float dist_y = abs(Position.y - Center.y);
	// float dist_sum = dist_x + dist_y;

	// if (dist_x * dist_x < RadiusInner.x || dist_sum > RadiusOuter.x)
	// 	color *= 0.3;

	float ellipse_dist = (dist_x * dist_x * x_squish * x_squish) + (dist_y * dist_y);

	if (ellipse_dist < RadiusInner.y * RadiusInner.y)
		color *= 0.3;
	else if (ellipse_dist > RadiusOuter.y * RadiusOuter.y)
		color *= 0.3;

	out_color = color;
}
