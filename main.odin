package gl_renderer

import "base:runtime"
import "base:intrinsics"

import "glue"
import imgui "glue/vendor/imgui"
import gl "vendor:OpenGL"
import "gizmo"
import "vendor:glfw"

import "core:log"
import "core:slice"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:fmt"

Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32
Mat4 :: matrix[4, 4]f32
Quat :: quaternion128

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

// TODO: Delete
@(private="file")
s_gizmo_draw_data_triangle_vertices_count: int

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

	if !glue.init(WINDOW_WIDTH, WINDOW_HEIGHT, WINDOW_TITLE, maximized = true, vsync = false, fps_limit = 260) {
		log.panic("Failed to create a window")
	}
	defer glue.deinit()

	// TODO: Add fullscreen to glue.
	monitor := glfw.GetPrimaryMonitor()
	video_mode := glfw.GetVideoMode(monitor)
	glfw.SetWindowMonitor(window = glue.window_handle(),
			      monitor = monitor,
			      xpos = 0,
			      ypos = 0,
			      width = video_mode.width,
			      height = video_mode.height,
			      refresh_rate = video_mode.refresh_rate)

	glue.set_cursor_enabled(false)
	glue.set_raw_mouse_motion_enabled(true)

	gl.CullFace(gl.BACK)
	gl.FrontFace(gl.CCW)
	gl.Enable(gl.CULL_FACE)

	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
	gl.Enable(gl.BLEND)

	gl.Enable(gl.DEPTH_TEST)

	gizmo_triangles_vertex_format := []glue.Vertex_Attribute{ .Float_3, .Float_4 }

	gizmo_triangles_va: glue.Vertex_Array
	gizmo_triangles_vb: glue.Gl_Buffer
	glue.create_vertex_array(&gizmo_triangles_va)
	defer glue.destroy_vertex_array(&gizmo_triangles_va)
	glue.create_dynamic_gl_buffer(&gizmo_triangles_vb)
	defer glue.destroy_gl_buffer(&gizmo_triangles_vb)
	glue.set_vertex_array_format(gizmo_triangles_va, gizmo_triangles_vertex_format)
	glue.bind_vertex_buffer(gizmo_triangles_va, gizmo_triangles_vb, size_of(gizmo.Triangle_Vertex))

	gizmo_triangle_shader, gizmo_triangle_shader_ok := glue.create_shader(#load("shaders/gizmo_triangle.vert"),
									      #load("shaders/gizmo_triangle.frag"))
	if !gizmo_triangle_shader_ok do log.panic("Failed to compile the gizmo triangle shader.")
	defer glue.destroy_shader(gizmo_triangle_shader)

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
	lit_color := glue.WHITE
	unlit_color := glue.WHITE
	glue.set_uniform(lit_shader, COLOR_UNIFORM, lit_color)
	glue.set_uniform(unlit_shader, COLOR_UNIFORM, unlit_color)

	cube_translation := Vec3{ 0, 0, -1 }
	cube_rotation := Quat(1)
	cube_scale := Vec3(1)
	gizmo_mode := gizmo.Mode.Translate

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

		if !glue.cursor_enabled() {
			LOOK_SPEED :: 1
			cursor_position_delta := cast(Vec2)glue.cursor_position_delta()
			camera.yaw += cursor_position_delta.x * LOOK_SPEED * 0.001
			camera.pitch += -cursor_position_delta.y * LOOK_SPEED * 0.001
			camera.pitch = clamp(camera.pitch, math.to_radians(f32(-89)), math.to_radians(f32(89)))
		}

		camera_vectors := glue.camera_vectors(camera)

		BASE_MOVEMENT_SPEED :: 0.3
		SPRINT_MOVEMENT_SPEED :: 2
		movement_speed: f32 = BASE_MOVEMENT_SPEED
		if glue.key_pressed(.Left_Shift) do movement_speed = SPRINT_MOVEMENT_SPEED
		if glue.key_pressed(.W) do camera.position += camera_vectors.forward * movement_speed * dt
		if glue.key_pressed(.S) do camera.position -= camera_vectors.forward * movement_speed * dt
		if glue.key_pressed(.A) do camera.position -= camera_vectors.right   * movement_speed * dt
		if glue.key_pressed(.D) do camera.position += camera_vectors.right   * movement_speed * dt

		imgui.Begin("Window")
		if imgui.ColorEdit4("Clear color", &clear_color) do set_clear_color(clear_color)
		if imgui.ColorEdit4("Lit Color", &lit_color) do glue.set_uniform(lit_shader, COLOR_UNIFORM, lit_color)
		if imgui.ColorEdit4("Unlit Color", &unlit_color) do glue.set_uniform(unlit_shader, COLOR_UNIFORM, unlit_color)
		imgui_enum_select("Gizmo Mode", &gizmo_mode)
		imgui.TextUnformatted(fmt.ctprintf("Camera Forward = %v", camera_vectors.forward))
		imgui.TextUnformatted(fmt.ctprintf("TRANSLATION TRIANGLE COUNT = %v", gizmo.TRANSLATION_TRIANGLE_COUNT))
		imgui.TextUnformatted(fmt.ctprintf("ROTATION TRIANGLE COUNT = %v", gizmo.ROTATION_TRIANGLE_COUNT))
		imgui.TextUnformatted(fmt.ctprintf("MAX TRIANGLES = %v", gizmo.MAX_TRIANGLES))
		imgui.TextUnformatted(fmt.ctprintf("actual returned triangle count = %v", s_gizmo_draw_data_triangle_vertices_count / 3))
		imgui.TextUnformatted(fmt.ctprintf("size_of(Gizmo) = %v", size_of(gizmo.Gizmo)))
		imgui.End()

		view := linalg.matrix4_look_at_from_fru(camera.position,
							camera_vectors.forward,
							camera_vectors.right,
							camera_vectors.up)
		projection := linalg.matrix4_perspective(fovy = math.to_radians(f32(45)),
							 aspect = glue.window_aspect_ratio(),
							 near = 0.1,
							 far = 1000)

		ndc_cursor_pos := get_normalized_cursor_position()
		gizmo.manipulate(mode = gizmo_mode,
				 translation = &cube_translation,
				 rotation = &cube_rotation,
				 mouse_position = cast(Vec2)ndc_cursor_pos,
				 mouse_pressed = glue.mouse_button_pressed(.Left),
				 view = view,
				 projection = projection)

		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

		mvp_buffer_data := Mvp_Buffer_Data {
			view = view,
			projection = projection,
		}
		glue.upload_static_gl_buffer_data(mvp_buffer, mem.any_to_bytes(mvp_buffer_data))

		{
			// CUBE
			glue.bind_texture(texture, 0)
			glue.use_shader(lit_shader)
			translation := linalg.matrix4_translate(cube_translation)
			rotation := linalg.matrix4_from_quaternion(cube_rotation)
			scale := linalg.matrix4_scale(cube_scale)
			model := translation * rotation * scale
			glue.set_uniform(lit_shader, MODEL_UNIFORM, model)

			glue.bind_mesh(cube_mesh)
			gl.DrawElements(gl.TRIANGLES,
					i32(cube_mesh.vertex_count),
					cube_mesh.index_type,
					rawptr(uintptr(cube_mesh.index_data_offset)))
		}

		{
			// SPHERE
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

		{
			gl.Disable(gl.DEPTH_TEST)
			defer gl.Enable(gl.DEPTH_TEST)

			gizmo_triangle_vertices := gizmo.get_draw_data()
			s_gizmo_draw_data_triangle_vertices_count = len(gizmo_triangle_vertices)

			glue.upload_dynamic_gl_buffer_data(&gizmo_triangles_vb, slice.to_bytes(gizmo_triangle_vertices[:]))

			glue.use_shader(gizmo_triangle_shader)
			glue.bind_vertex_array(gizmo_triangles_va)
			gl.DrawArrays(gl.TRIANGLES,
				      0,
				      cast(i32)len(gizmo_triangle_vertices))
		}

		glue.end_frame()
		free_all(context.temp_allocator)
	}
}

set_clear_color :: proc(color: Vec4) {
	gl.ClearColor(color.r, color.g, color.b, color.a)
}

get_normalized_cursor_position :: proc() -> [2]f64 {
	pos := glue.cursor_position()
	window_size := cast([2]f64)glue.window_size()
	pos = pos / window_size * 2 - 1
	pos.y = -pos.y
	return pos
}

imgui_enum_select :: proc(label: cstring, value: ^$E) -> bool where intrinsics.type_is_enum(E) {
	value_changed := false
	if imgui.BeginCombo(label, fmt.ctprintf("%v", value^)) {
		for enum_value in E {
			is_selected := enum_value == value^
			if imgui.Selectable(fmt.ctprintf("%v", enum_value), is_selected) {
				value^ = enum_value
				value_changed = true
			}
			if is_selected do imgui.SetItemDefaultFocus()
		}
		imgui.EndCombo()
	}
	return value_changed
}
