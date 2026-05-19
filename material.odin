package gl_renderer

import "glue"

Shader :: glue.Shader
Texture :: glue.Texture

Material :: struct {
	shader: ^Shader,
	texture_0: ^Texture,
}
