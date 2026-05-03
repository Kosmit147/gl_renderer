package gl_renderer

import "base:runtime"

import "glue"
import imgui "glue/vendor/imgui"
import gl "vendor:OpenGL"
import tinyobj "vendor/tinyobjloader"

import "core:c"
import "core:log"
import "core:slice"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:os"

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

	cube_mesh: glue.Mesh
	glue.create_mesh(mesh = &cube_mesh,
			 vertices = slice.to_bytes(cube_vertices[:]),
			 vertex_stride = size_of(Vertex_3D),
			 vertex_format = vertex_3d_format[:],
			 indices = slice.to_bytes(cube_indices[:]),
			 index_type = glue.gl_index(Cube_Index))
	defer glue.destroy_mesh(&cube_mesh)

	sphere_mesh, sphere_mesh_ok := create_mesh_from_obj("models/sphere.obj")
	if !sphere_mesh_ok do log.panic("Failed to load the sphere model.")
	defer glue.destroy_mesh(&sphere_mesh)

	texture, texture_ok := glue.create_texture_from_jpeg_in_memory(#load("textures/container.jpg"))
	if !texture_ok do log.panic("Failed to create the texture.")
	defer glue.destroy_texture(&texture)

	lit_shader, lit_shader_ok := glue.create_shader(#load("shaders/lit.vert"), #load("shaders/lit.frag"))
	if !lit_shader_ok do log.panic("Failed to compile the lit shader.")
	defer glue.destroy_shader(lit_shader)

	camera := glue.Camera {
		position = { 0, 0, 2 },
		yaw = math.to_radians(f32(-90.0)),
	}

	model_uniform := glue.get_uniform(lit_shader, "model", Mat4)
	view_uniform := glue.get_uniform(lit_shader, "view", Mat4)
	projection_uniform := glue.get_uniform(lit_shader, "projection", Mat4)
	tint_uniform := glue.get_uniform(lit_shader, "tint", Vec4)

	clear_color := glue.BLACK
	set_clear_color(clear_color)
	tint := glue.WHITE
	glue.set_uniform(lit_shader, tint_uniform, tint)

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
		if imgui.ColorEdit4("Tint", &tint) do glue.set_uniform(lit_shader, tint_uniform, tint)
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

		glue.bind_texture(texture, 0)
		glue.use_shader(lit_shader)

		view := linalg.matrix4_look_at(eye = camera.position,
					       centre = camera.position + camera_vectors.forward,
					       up = camera_vectors.up)
		projection := linalg.matrix4_perspective(fovy = math.to_radians(f32(45)),
							 aspect = glue.window_aspect_ratio(),
							 near = 0.1,
							 far = 1000)
		glue.set_uniform(lit_shader, view_uniform, view)
		glue.set_uniform(lit_shader, projection_uniform, projection)

		{
			model: Mat4 = 1
			glue.set_uniform(lit_shader, model_uniform, model)

			glue.bind_mesh(cube_mesh)
			gl.DrawElements(gl.TRIANGLES,
					i32(cube_mesh.vertex_count),
					cube_mesh.index_type,
					rawptr(uintptr(cube_mesh.index_data_offset)))
		}

		{
			model := linalg.matrix4_translate(Vec3{ 10, 1, 10 })
			glue.set_uniform(lit_shader, model_uniform, model)

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

create_mesh_from_obj :: proc(file_path: cstring) -> (mesh: glue.Mesh, ok := false) {
	file_reader :: proc "c" (ctx: rawptr,
				 filename: cstring,
				 is_mtl: c.int,
				 obj_filename: cstring,
				 buf: ^[^]c.char,
				 buf_len: ^c.size_t) {
		context = g_context
		data, error := os.read_entire_file(cast(string)obj_filename, context.temp_allocator)
		if error != nil {
			log.errorf("Failed to read model file `%v`: %v", obj_filename, error)
			buf^ = nil
			buf_len^ = 0
			return
		}
		buf^ = raw_data(data)
		buf_len^ = len(data)
		return
	}

	attrib: tinyobj.attrib_t
	shapes_data: [^]tinyobj.shape_t
	num_shapes: uint
	materials_data: [^]tinyobj.material_t
	num_materials: uint

	if tinyobj.parse_obj(attrib = &attrib,
			     shapes = &shapes_data,
			     num_shapes = &num_shapes,
			     materials = &materials_data,
			     num_materials = &num_materials,
			     file_name = file_path,
			     file_reader = file_reader,
			     ctx = nil,
			     flags = tinyobj.FLAG_TRIANGULATE) != tinyobj.SUCCESS {
		return
	}
	defer {
		tinyobj.attrib_free(&attrib)
		tinyobj.shapes_free(shapes_data, num_shapes)
		tinyobj.materials_free(materials_data, num_materials)
	}

	Mesh_Vertex :: Vertex_3D
	Mesh_Index :: u32
	mesh_vertex_format := vertex_3d_format

	vertices := make([dynamic]Mesh_Vertex, context.temp_allocator)
	indices := make([dynamic]Mesh_Index, context.temp_allocator)

	num_triangles := attrib.num_face_num_verts
	model_vertices := attrib.faces[:num_triangles * 3]
	unique_vertex_indices := make(map[Mesh_Vertex]Mesh_Index, context.temp_allocator)
	for vertex in model_vertices {
		vertex := Mesh_Vertex {
			position = Vec3{
				attrib.vertices[vertex.v_idx * 3 + 0],
				attrib.vertices[vertex.v_idx * 3 + 1],
				attrib.vertices[vertex.v_idx * 3 + 2],
			},
			normal = Vec3{
				attrib.normals[vertex.vn_idx * 3 + 0],
				attrib.normals[vertex.vn_idx * 3 + 1],
				attrib.normals[vertex.vn_idx * 3 + 2],
			},
			uv = Vec2{
				attrib.texcoords[vertex.vt_idx * 2 + 0],
				attrib.texcoords[vertex.vt_idx * 2 + 1],
			},
		}

		if vertex_index, vertex_index_ok := unique_vertex_indices[vertex]; vertex_index_ok {
			append(&indices, vertex_index)
		} else {
			vertex_index = cast(Mesh_Index)len(unique_vertex_indices)
			unique_vertex_indices[vertex] = vertex_index
			append(&vertices, vertex)
			append(&indices, vertex_index)
		}
	}

	glue.create_mesh(mesh = &mesh,
			 vertices = slice.to_bytes(vertices[:]),
			 vertex_stride = size_of(Mesh_Vertex),
			 vertex_format = mesh_vertex_format[:],
			 indices = slice.to_bytes(indices[:]),
			 index_type = glue.gl_index(Mesh_Index))
	defer if !ok do glue.destroy_mesh(&mesh)

	ok = true
	return
}
