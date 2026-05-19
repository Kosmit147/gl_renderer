package gl_renderer

import gl "vendor:OpenGL"
import "glue"

import "core:mem"
import "core:math/linalg"

@(export, rodata) NvOptimusEnablement: u32 = 1
@(export, rodata) AmdPowerXpressRequestHighPerformance: u32 = 1

MODEL_UNIFORM :: glue.Uniform(Mat4) { location = 0 }
COLOR_UNIFORM :: glue.Uniform(Vec4) { location = 5 }

Vertex_3D :: struct {
	position: Vec3,
	normal: Vec3,
	uv: Vec2,
}

@(rodata)
vertex_3d_format := [?]glue.Vertex_Attribute{
	.Float_3,
	.Float_3,
	.Float_2,
}

Camera_Buffer_Data :: struct {
	view: Mat4,
	projection: Mat4,
}

Renderer :: struct {
	camera_buffer: glue.Gl_Buffer,
	clear_color: Vec4,
}

renderer_init :: proc(renderer: ^Renderer) -> (ok := false) {
	renderer.clear_color = BLACK

	gl.CullFace(gl.BACK)
	gl.FrontFace(gl.CCW)
	gl.Enable(gl.CULL_FACE)

	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
	gl.Enable(gl.BLEND)

	gl.Enable(gl.DEPTH_TEST)

	glue.create_static_gl_buffer(&renderer.camera_buffer, size_of(Camera_Buffer_Data))
	defer if !ok do glue.destroy_gl_buffer(&renderer.camera_buffer)
	glue.bind_uniform_buffer(renderer.camera_buffer, 0)

	ok = true
	return
}

renderer_deinit :: proc(renderer: ^Renderer) {
	glue.destroy_gl_buffer(&renderer.camera_buffer)
}

renderer_render_scene :: proc(renderer: Renderer, scene: Scene) {
	gl.ClearColor(expand_values(renderer.clear_color))
	gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT | gl.STENCIL_BUFFER_BIT)

	camera_buffer_data := Camera_Buffer_Data {
		view = camera_view(scene.camera),
		projection = camera_projection(scene.camera),
	}

	glue.upload_static_gl_buffer_data(renderer.camera_buffer, mem.ptr_to_bytes(&camera_buffer_data))

	for entity in scene.entities {
		renderer_render_entity(entity^)
	}
}

renderer_render_entity :: proc(entity: Entity) {
	glue.use_shader(entity.material.shader^)
	glue.bind_texture(entity.material.texture_0^, 0)

	translation := linalg.matrix4_translate(entity.translation)
	rotation := linalg.matrix4_from_quaternion(entity.rotation)
	scale := linalg.matrix4_scale(entity.scale)
	model := translation * rotation * scale
	glue.set_uniform(entity.material.shader^, MODEL_UNIFORM, model)

	glue.bind_mesh(entity.mesh^)
	gl.DrawElements(gl.TRIANGLES,
					i32(entity.mesh.vertex_count),
					entity.mesh.index_type,
					rawptr(uintptr(entity.mesh.index_data_offset)))
}
