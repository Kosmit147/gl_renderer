package gl_renderer

import "base:runtime"

import "glue"
import imgui "glue/vendor/imgui"
import gl "vendor:OpenGL"

import "core:log"
import "core:slice"
import "core:math"
import "core:math/linalg"
import "core:mem"

Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32
Mat4 :: matrix[4, 4]f32

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

MODEL_UNIFORM :: glue.Uniform(Mat4) { location = 0 }
COLOR_UNIFORM :: glue.Uniform(Vec4) { location = 5 }

Mvp_Buffer_Data :: struct {
	view: Mat4,
	projection: Mat4,
}

WINDOW_TITLE  :: "GL Renderer"
WINDOW_WIDTH  :: 1920
WINDOW_HEIGHT :: 1080

g_context: runtime.Context

main :: proc() {
	context.logger = log.create_console_logger(.Debug when ODIN_DEBUG else .Info)
	defer log.destroy_console_logger(context.logger)

	when ODIN_DEBUG {
		tracking_allocator: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking_allocator, context.allocator)
		context.allocator = mem.tracking_allocator(&tracking_allocator)
		defer {
			if len(tracking_allocator.allocation_map) > 0 {
				log.errorf("MEMORY LEAK: %v allocations not freed:",
					   len(tracking_allocator.allocation_map))
				for _, entry in tracking_allocator.allocation_map {
					log.errorf("- %v bytes at %v", entry.size, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&tracking_allocator)
		}
	}

	g_context = context

	if !glue.init(WINDOW_WIDTH, WINDOW_HEIGHT, WINDOW_TITLE) do log.panic("Failed to create a window")
	defer glue.deinit()

	glue.set_cursor_enabled(false)
	glue.set_raw_mouse_motion_enabled(true)

	gl.CullFace(gl.BACK)
	gl.FrontFace(gl.CCW)
	gl.Enable(gl.CULL_FACE)

	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
	gl.Enable(gl.BLEND)

	gl.Enable(gl.DEPTH_TEST)

	cube_mesh := glue.create_mesh(vertices = slice.to_bytes(cube_vertices[:]),
				      vertex_stride = size_of(Vertex_3D),
				      vertex_format = vertex_3d_format[:],
				      indices = slice.to_bytes(cube_indices[:]),
				      index_type = glue.gl_index(Cube_Index))
	defer glue.destroy_mesh(&cube_mesh)

	sphere_mesh, sphere_mesh_ok := glue.create_mesh_from_obj("models/sphere.obj")
	if !sphere_mesh_ok do log.panic("Failed to load the sphere model.")
	defer glue.destroy_mesh(&sphere_mesh)

	texture, texture_ok := glue.create_texture_from_jpeg_in_memory(#load("textures/container.jpg"))
	if !texture_ok do log.panic("Failed to create the texture.")
	defer glue.destroy_texture(&texture)

	mvp_buffer: glue.Gl_Buffer
	glue.create_static_gl_buffer(&mvp_buffer, size_of(Mvp_Buffer_Data))
	defer glue.destroy_gl_buffer(&mvp_buffer)
	glue.bind_uniform_buffer(mvp_buffer, 0)

	lit_shader, lit_shader_ok := glue.create_shader(#load("shaders/lit.vert"), #load("shaders/lit.frag"))
	if !lit_shader_ok do log.panic("Failed to compile the lit shader.")
	defer glue.destroy_shader(lit_shader)

	unlit_shader, unlit_shader_ok := glue.create_shader(#load("shaders/unlit.vert"), #load("shaders/unlit.frag"))
	if !unlit_shader_ok do log.panic("Failed to compile the unlit shader.")
	defer glue.destroy_shader(unlit_shader)

	camera := glue.Camera {
		position = { 0, 0, 2 },
		yaw = math.to_radians(f32(-90.0)),
	}

	clear_color := glue.BLACK
	set_clear_color(clear_color)
	color := glue.WHITE
	glue.set_uniform(lit_shader, COLOR_UNIFORM, color)
	glue.set_uniform(unlit_shader, COLOR_UNIFORM, color)

	prev_time := glue.time()

	for !glue.window_should_close() {
		glue.begin_frame()

		time := glue.time()
		dt := f32(time - prev_time)
		prev_time = time

		for event in glue.pop_event() {
			#partial switch event in event {
			case glue.Key_Pressed_Event:
				if event.key == .Escape do glue.close_window()
				else if event.key == .Left_Control do glue.set_cursor_enabled(!glue.cursor_enabled())
			}
		}

		imgui.Begin("Window")
		if imgui.ColorEdit4("Clear color", &clear_color) do set_clear_color(clear_color)
		if imgui.ColorEdit4("Color", &color) {
			glue.set_uniform(lit_shader, COLOR_UNIFORM, color)
			glue.set_uniform(unlit_shader, COLOR_UNIFORM, color)
		}
		imgui.End()

		if !glue.cursor_enabled() {
			LOOK_SPEED :: 1
			cursor_position_delta := linalg.array_cast(glue.cursor_position_delta(), f32)
			camera.yaw += cursor_position_delta.x * LOOK_SPEED * 0.001
			camera.pitch += -cursor_position_delta.y * LOOK_SPEED * 0.001
			camera.pitch = clamp(camera.pitch, math.to_radians(f32(-89)), math.to_radians(f32(89)))
		}

		camera_vectors := glue.camera_vectors(camera)

		MOVEMENT_SPEED :: 5
		if glue.key_pressed(.W) do camera.position += camera_vectors.forward * MOVEMENT_SPEED * dt
		if glue.key_pressed(.S) do camera.position -= camera_vectors.forward * MOVEMENT_SPEED * dt
		if glue.key_pressed(.A) do camera.position -= camera_vectors.right   * MOVEMENT_SPEED * dt
		if glue.key_pressed(.D) do camera.position += camera_vectors.right   * MOVEMENT_SPEED * dt

		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

		view := linalg.matrix4_look_at(eye = camera.position,
					       centre = camera.position + camera_vectors.forward,
					       up = camera_vectors.up)
		projection := linalg.matrix4_perspective(fovy = math.to_radians(f32(45)),
							 aspect = glue.window_aspect_ratio(),
							 near = 0.1,
							 far = 1000)
		mvp_buffer_data := Mvp_Buffer_Data {
			view = view,
			projection = projection,
		}
		glue.upload_static_gl_buffer_data(mvp_buffer, mem.any_to_bytes(mvp_buffer_data))

		{
			glue.bind_texture(texture, 0)
			glue.use_shader(lit_shader)
			model: Mat4 = 1
			glue.set_uniform(lit_shader, MODEL_UNIFORM, model)

			glue.bind_mesh(cube_mesh)
			gl.DrawElements(gl.TRIANGLES,
					i32(cube_mesh.vertex_count),
					cube_mesh.index_type,
					rawptr(uintptr(cube_mesh.index_data_offset)))
		}

		{
			glue.bind_texture(texture, 0)
			glue.use_shader(unlit_shader)
			model := linalg.matrix4_translate(Vec3{ 10, 1, 10 })
			glue.set_uniform(unlit_shader, MODEL_UNIFORM, model)

			glue.bind_mesh(sphere_mesh)
			gl.DrawElements(gl.TRIANGLES,
					i32(sphere_mesh.vertex_count),
					sphere_mesh.index_type,
					rawptr(uintptr(sphere_mesh.index_data_offset)))
		}

		glue.end_frame()
		free_all(context.temp_allocator)
	}
}

set_clear_color :: proc(color: Vec4) {
	gl.ClearColor(color.r, color.g, color.b, color.a)
}
