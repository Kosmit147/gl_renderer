package gl_renderer

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

VERTEX_SOURCE ::
`
#version 460 core

layout (location = 0) in vec3 in_position;
layout (location = 1) in vec3 in_normal;
layout (location = 2) in vec2 in_uv;

out vec2 UV;

uniform mat4 projection;
uniform mat4 view;
uniform mat4 model;

void main() {
	UV = in_uv;
	gl_Position = projection * view * model * vec4(in_position, 1.0);
}
`

FRAGMENT_SOURCE ::
`
#version 460 core

in vec2 UV;

out vec4 out_color;

uniform vec4 color;
layout (binding = 0) uniform sampler2D texture0;

void main() {
	out_color = texture(texture0, UV) * color;
}
`

Cube_Vertex :: struct {
	position: Vec3,
	normal: Vec3,
	uv: Vec2,
}

Cube_Index :: u8

@(rodata)
cube_vertex_format := [?]glue.Vertex_Attribute{
	.Float_3,
	.Float_3,
	.Float_2,
}

@(private="file", rodata)
cube_vertices := [24]Cube_Vertex{
	// Front wall.
	{ position = { 0, 0, 1 }, normal = {  0,  0,  1 }, uv = { 0, 1 } },
	{ position = { 1, 0, 1 }, normal = {  0,  0,  1 }, uv = { 1, 1 } },
	{ position = { 1, 1, 1 }, normal = {  0,  0,  1 }, uv = { 1, 0 } },
	{ position = { 0, 1, 1 }, normal = {  0,  0,  1 }, uv = { 0, 0 } },

	// Back wall.
	{ position = { 0, 0, 0 }, normal = {  0,  0, -1 }, uv = { 0, 1 } },
	{ position = { 0, 1, 0 }, normal = {  0,  0, -1 }, uv = { 0, 0 } },
	{ position = { 1, 1, 0 }, normal = {  0,  0, -1 }, uv = { 1, 0 } },
	{ position = { 1, 0, 0 }, normal = {  0,  0, -1 }, uv = { 1, 1 } },

	// Left wall.
	{ position = { 0, 1, 1 }, normal = { -1,  0,  0 }, uv = { 1, 0 } },
	{ position = { 0, 1, 0 }, normal = { -1,  0,  0 }, uv = { 0, 0 } },
	{ position = { 0, 0, 0 }, normal = { -1,  0,  0 }, uv = { 0, 1 } },
	{ position = { 0, 0, 1 }, normal = { -1,  0,  0 }, uv = { 1, 1 } },

	// Right wall.
	{ position = { 1, 1, 1 }, normal = {  1,  0,  0 }, uv = { 0, 0 } },
	{ position = { 1, 0, 1 }, normal = {  1,  0,  0 }, uv = { 0, 1 } },
	{ position = { 1, 0, 0 }, normal = {  1,  0,  0 }, uv = { 1, 1 } },
	{ position = { 1, 1, 0 }, normal = {  1,  0,  0 }, uv = { 1, 0 } },

	// Bottom wall.
	{ position = { 0, 0, 0 }, normal = {  0, -1,  0 }, uv = { 0, 0 } },
	{ position = { 1, 0, 0 }, normal = {  0, -1,  0 }, uv = { 1, 0 } },
	{ position = { 1, 0, 1 }, normal = {  0, -1,  0 }, uv = { 1, 1 } },
	{ position = { 0, 0, 1 }, normal = {  0, -1,  0 }, uv = { 0, 1 } },

	// Top wall.
	{ position = { 0, 1, 0 }, normal = {  0,  1,  0 }, uv = { 0, 0 } },
	{ position = { 0, 1, 1 }, normal = {  0,  1,  0 }, uv = { 0, 1 } },
	{ position = { 1, 1, 1 }, normal = {  0,  1,  0 }, uv = { 1, 1 } },
	{ position = { 1, 1, 0 }, normal = {  0,  1,  0 }, uv = { 1, 0 } },
}

@(private="file", rodata)
cube_indices := [36]Cube_Index{
	// Front wall.
	0, 1, 2, 0, 2, 3,

	// Back wall.
	4, 5, 6, 4, 6, 7,

	// Left wall.
	8, 9, 10, 8, 10, 11,

	// Right wall.
	12, 13, 14, 12, 14, 15,

	// Bottom wall.
	16, 17, 18, 16, 18, 19,

	// Top wall.
	20, 21, 22, 20, 22, 23,
}

WINDOW_TITLE  :: "GL Renderer"
WINDOW_WIDTH  :: 1920
WINDOW_HEIGHT :: 1080

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

	cube_mesh: glue.Mesh
	glue.create_mesh(mesh = &cube_mesh,
			 vertices = slice.to_bytes(cube_vertices[:]),
			 vertex_stride = size_of(Cube_Vertex),
			 vertex_format = cube_vertex_format[:],
			 indices = slice.to_bytes(cube_indices[:]),
			 index_type = glue.gl_index(Cube_Index))
	defer glue.destroy_mesh(&cube_mesh)

	texture, texture_ok := glue.create_texture_from_jpeg_in_memory(#load("textures/container.jpg"))
	if !texture_ok do log.panic("Failed to create the texture.")
	defer glue.destroy_texture(&texture)

	shader, shader_ok := glue.create_shader(VERTEX_SOURCE, FRAGMENT_SOURCE)
	if !shader_ok do log.panic("Failed to compile the shader.")
	defer glue.destroy_shader(shader)

	camera := glue.Camera {
		position = { 0, 0, 2 },
		yaw = math.to_radians(f32(-90.0)),
	}

	model_uniform := glue.get_uniform(shader, "model", Mat4)
	view_uniform := glue.get_uniform(shader, "view", Mat4)
	projection_uniform := glue.get_uniform(shader, "projection", Mat4)
	color_uniform := glue.get_uniform(shader, "color", Vec4)

	glue.bind_mesh(cube_mesh)
	glue.bind_texture(texture, 0)
	glue.use_shader(shader)

	clear_color := glue.BLACK
	set_clear_color(clear_color)
	quad_color := glue.WHITE
	glue.set_uniform(shader, color_uniform, quad_color)

	prev_time := glue.time()

	for !glue.window_should_close() {
		glue.begin_frame()

		for event in glue.pop_event() {
			#partial switch event in event {
			case glue.Key_Pressed_Event:
				if event.key == .Escape do glue.close_window()
				else if event.key == .Left_Control do glue.set_cursor_enabled(!glue.cursor_enabled())
			}
		}

		time := glue.time()
		dt := f32(time - prev_time)
		prev_time = time

		imgui.Begin("Window")
		if imgui.ColorEdit4("Clear color", &clear_color) do set_clear_color(clear_color)
		if imgui.ColorEdit4("Quad color", &quad_color) do glue.set_uniform(shader, color_uniform, quad_color)
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

		model: Mat4 = 1
		view := linalg.matrix4_look_at(eye = camera.position,
					       centre = camera.position + camera_vectors.forward,
					       up = camera_vectors.up)
		projection := linalg.matrix4_perspective(fovy = math.to_radians(f32(45)),
							 aspect = glue.window_aspect_ratio(),
							 near = 0.1,
							 far = 1000)

		glue.set_uniform(shader, model_uniform, model)
		glue.set_uniform(shader, view_uniform, view)
		glue.set_uniform(shader, projection_uniform, projection)

		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
		gl.DrawElements(gl.TRIANGLES,
				i32(cube_mesh.vertex_count),
				cube_mesh.index_type,
				rawptr(uintptr(cube_mesh.index_data_offset)))

		glue.end_frame()
		free_all(context.temp_allocator)
	}
}

set_clear_color :: proc(color: Vec4) {
	gl.ClearColor(color.r, color.g, color.b, color.a)
}
