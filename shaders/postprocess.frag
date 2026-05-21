#version 460 core

out vec4 out_color;

layout (binding = 0) uniform sampler2D texture0;

void main() {
  out_color = texelFetch(texture0, ivec2(gl_FragCoord), 0);
}
