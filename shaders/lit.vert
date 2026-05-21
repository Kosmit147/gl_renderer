#version 460 core

layout (location = 0) in vec3 in_position_os;
layout (location = 1) in vec3 in_normal_os;
layout (location = 2) in vec2 in_uv;

out vec2 UV;
out flat vec3 AmbientDiffuse;

layout (std140, binding = 0) uniform Camera {
  mat4 view;
  mat4 projection;
};

layout (std430, binding = 1) readonly buffer Light {
  vec3 light_ambient;
  vec3 light_direction_ws;
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
  // TODO: Precalculate the normal matrix on the CPU.
  mat3 normal_matrix = transpose(inverse(mat3(model)));
  vec3 normal_ws = normalize(normal_matrix * in_normal_os);
  AmbientDiffuse = ambient() + diffuse(normal_ws, light_direction_ws);
  UV = in_uv;
  gl_Position = projection * view * model * vec4(in_position_os, 1.0);
}
