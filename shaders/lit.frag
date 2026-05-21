#version 460 core

in vec2 UV;
in vec3 AmbientDiffuse;

out vec4 out_color;

layout (location = 5) uniform vec4 color;
layout (binding = 0) uniform sampler2D texture0;

void main() {
  out_color = vec4(AmbientDiffuse, 1.0) * texture(texture0, UV) * color;
}
