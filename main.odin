package gl_renderer

import "base:runtime"

import "glue"
import imgui "glue/vendor/imgui"

import "core:log"
import "core:math"
import "core:mem"

WINDOW_TITLE  :: "GL Renderer"
WINDOW_WIDTH  :: 1920
WINDOW_HEIGHT :: 1080

CLOSE_WINDOW_KEY  :: glue.Key.Escape
TOGGLE_CURSOR_KEY :: glue.Key.Left_Control

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

	if !glue.init(WINDOW_WIDTH, WINDOW_HEIGHT, WINDOW_TITLE, maximized = true, vsync = false, fps_limit = 260) {
		log.panic("Failed to create a window")
	}
	defer glue.deinit()

	glue.set_cursor_enabled(false)
	glue.set_raw_mouse_motion_enabled(true)

	renderer: Renderer
	if !renderer_init(&renderer) do log.panic("Failed to initialize the renderer.")
	defer renderer_deinit(&renderer)

	asset_cache: Asset_Cache
	if !asset_cache_init(&asset_cache) do log.panic("Failed to initialize the asset cache.")
	defer asset_cache_deinit(asset_cache)

	lit_shader, _ := asset_cache_get_shader(asset_cache, LIT_SHADER)
	unlit_shader, _ := asset_cache_get_shader(asset_cache, UNLIT_SHADER)

	lit_color := glue.WHITE
	unlit_color := glue.WHITE
	glue.set_uniform(lit_shader, COLOR_UNIFORM, lit_color)
	glue.set_uniform(unlit_shader, COLOR_UNIFORM, unlit_color)

	scene: Scene
	scene_init(&scene)
	defer scene_destroy(scene)

	scene.camera = glue.Camera {
		position = { 0, 0, 2 },
		yaw = math.to_radians(f32(-90.0)),
	}

	{
		container_texture, texture_ok := glue.create_texture_from_jpeg_in_memory(#load("textures/container.jpg"))
		ensure(texture_ok)
		container_texture_id := asset_cache_add_texture(&asset_cache, container_texture)
		cube_material := Material {
			shader = LIT_SHADER,
			texture_0 = container_texture_id,
		}
		cube_material_id := asset_cache_add_material(&asset_cache, cube_material)
		cube := scene_add_entity(&scene, "Cube")
		cube.translation = { 0, 0, -1 }
		cube.rotation = 1
		cube.scale = 1
		cube.mesh = CUBE_MESH
		cube.material = cube_material_id
	}

	{
		sphere := scene_add_entity(&scene, "Sphere")
		sphere.translation = { 10, 1, 10 }
		sphere.rotation = 1
		sphere.scale = 1
		sphere.mesh = SPHERE_MESH
		sphere.material = UNLIT_MATERIAL
	}

	editor: Editor
	if !editor_init(&editor) do log.panic("Failed to initialize the editor.")
	defer editor_deinit(&editor)

	prev_time := glue.time()

	for !glue.window_should_close() {
		glue.begin_frame()

		time := glue.time()
		dt := f32(time - prev_time)
		prev_time = time

		for event in glue.pop_event() {
			#partial switch event in event {
			case glue.Key_Pressed_Event:
				#partial switch event.key {
				case CLOSE_WINDOW_KEY:   glue.close_window()
				case TOGGLE_CURSOR_KEY:  glue.set_cursor_enabled(!glue.cursor_enabled())
				}
			}

			editor_on_event(&editor, event)
		}

		if !glue.cursor_enabled() {
			LOOK_SPEED :: 1
			cursor_position_delta := cast(Vec2)glue.cursor_position_delta()
			scene.camera.yaw += cursor_position_delta.x * LOOK_SPEED * 0.001
			scene.camera.pitch += -cursor_position_delta.y * LOOK_SPEED * 0.001
			scene.camera.pitch = clamp(scene.camera.pitch, math.to_radians(f32(-89)), math.to_radians(f32(89)))
		}

		camera_vectors := glue.camera_vectors(scene.camera)

		BASE_MOVEMENT_SPEED :: 0.3
		SPRINT_MOVEMENT_SPEED :: 2
		movement_speed: f32 = BASE_MOVEMENT_SPEED
		if glue.key_pressed(.Left_Shift) do movement_speed = SPRINT_MOVEMENT_SPEED
		if glue.key_pressed(.W) do scene.camera.position += camera_vectors.forward * movement_speed * dt
		if glue.key_pressed(.S) do scene.camera.position -= camera_vectors.forward * movement_speed * dt
		if glue.key_pressed(.A) do scene.camera.position -= camera_vectors.right   * movement_speed * dt
		if glue.key_pressed(.D) do scene.camera.position += camera_vectors.right   * movement_speed * dt

		editor_ui(&editor, &scene)

		imgui.Begin("Window")
		imgui.ColorEdit4("Clear Color", &renderer.clear_color)
		if imgui.ColorEdit4("Lit Color", &lit_color) do glue.set_uniform(lit_shader, COLOR_UNIFORM, lit_color)
		if imgui.ColorEdit4("Unlit Color", &unlit_color) do glue.set_uniform(unlit_shader, COLOR_UNIFORM, unlit_color)
		imgui.End()

		renderer_render_scene(renderer, scene, asset_cache)
		editor_render(&editor)

		glue.end_frame()
		free_all(context.temp_allocator)
	}
}
