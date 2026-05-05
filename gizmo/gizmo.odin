package gizmo

import "core:math/linalg"

X_COLOR :: Vec4{ 1, 0, 0, 0.8 }
Y_COLOR :: Vec4{ 0, 1, 0, 0.8 }
Z_COLOR :: Vec4{ 0, 0, 1, 0.8 }

Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32
Mat4 :: matrix[4, 4]f32
Quat :: quaternion128

Axis :: enum {
	X,
	Y,
	Z,
}

@(rodata)
axis_colors := [Axis]Vec4{
	.X = X_COLOR,
	.Y = Y_COLOR,
	.Z = Z_COLOR,
}

@(rodata)
axis_vectors := [Axis]Vec3{
	.X = Vec3{ 1, 0, 0 },
	.Y = Vec3{ 0, 1, 0 },
	.Z = Vec3{ 0, 0, 1 },
}

Mode :: enum {
	Translate,
	Rotate,
	Scale,
}

Gizmo :: struct {
	mode: Mode,

	prev_mouse_position: Vec2, // In NDC.
	mouse_was_pressed: bool,

	selected_axis: Maybe(Axis),
	dragging: bool,

	// These are the final triangles in ndc which are going to be drawn on the screen.
	triangles: [dynamic]Triangle,

	axis_world_directions: [Axis]Vec3,
	axis_screen_directions: [Axis]Vec3,
	axis_depths: [Axis]f32,
}

@(private="file")
s_gizmo: Gizmo

// TODO: These functions should be "contextless".

init :: proc() {
	s_gizmo.triangles = make([dynamic]Triangle)
}

deinit :: proc() {
	delete(s_gizmo.triangles)
}

manipulate :: proc(translation: ^Vec3,
		   // rotation: ^Quat,
		   // scale: ^Vec3,
		   mouse_position: Vec2, // In NDC.
		   mouse_pressed: bool,
		   view: Mat4,
		   projection: Mat4) -> (value_changed := false) {
	clear(&s_gizmo.triangles)

	aspect_ratio := projection[1, 1] / projection[0, 0]

	translation_arrow :: proc(translation: Vec3,
				  projection: Mat4,
				  view: Mat4,
				  axis: Axis) {
		axis_vec := axis_vectors[axis]

		line_start := Vec4{ translation.x, translation.y, translation.z, 1 }
		line_end := line_start + Vec4{ axis_vec.x, axis_vec.y, axis_vec.z, 0 }

		s_gizmo.axis_world_directions[axis] = (line_end - line_start).xyz

		line_start = view * line_start
		line_end = view * line_end

		s_gizmo.axis_depths[axis] = -line_end.z

		// TODO: Do we have to do projection here? Maybe we could just draw the lines in view space?
		line_start = projection * line_start
		line_end = projection * line_end

		line_start /= line_start.w
		line_end /= line_end.w

		line_direction := linalg.normalize0((line_end - line_start).xyz)
		s_gizmo.axis_screen_directions[axis] = line_direction
		orthogonal_direction := linalg.normalize0(linalg.cross(line_direction, Vec3{ 0, 0, -1 }))

		{
			// Line
			p1 := line_start.xyz + orthogonal_direction *  0.004
			p2 := line_start.xyz + orthogonal_direction * -0.004
			p3 := line_start.xyz + line_direction * 0.2 + orthogonal_direction *  0.004
			p4 := line_start.xyz + line_direction * 0.2 + orthogonal_direction * -0.004

			append(&s_gizmo.triangles, Triangle{ { p1, p2, p3 }, axis })
			append(&s_gizmo.triangles, Triangle{ { p4, p3, p2 }, axis })
		}

		{
			// Arrow
			p1 := line_start.xyz + line_direction * 0.2 + orthogonal_direction *  0.02
			p2 := line_start.xyz + line_direction * 0.2 + orthogonal_direction * -0.02
			p3 := line_start.xyz + line_direction * 0.22

			append(&s_gizmo.triangles, Triangle{ { p1, p2, p3 }, axis })
		}
	}

	switch s_gizmo.mode {
	case .Translate:
		translation_arrow(translation^, projection, view, .X)
		translation_arrow(translation^, projection, view, .Y)
		translation_arrow(translation^, projection, view, .Z)
	case .Rotate:
	case .Scale:
	}

	if !mouse_pressed {
		s_gizmo.selected_axis = nil
		for triangle in s_gizmo.triangles {
			if triangle_intersect(mouse_position, triangle) {
				s_gizmo.selected_axis = triangle.axis
			}
		}
	}
	s_gizmo.dragging = mouse_pressed && s_gizmo.selected_axis != nil

	switch s_gizmo.mode {
	case .Translate:
		if s_gizmo.dragging {
			if mouse_position != s_gizmo.prev_mouse_position {
				mouse_delta := mouse_position - s_gizmo.prev_mouse_position
				axis := s_gizmo.selected_axis.(Axis)

				axis_world_dir := s_gizmo.axis_world_directions[axis]
				axis_screen_dir := s_gizmo.axis_screen_directions[axis]
				axis_depth := s_gizmo.axis_depths[axis]

				movement := linalg.dot(axis_screen_dir.xy, linalg.normalize(mouse_delta)) * linalg.length(mouse_delta)
				// screen_movement := linalg.length(axis_screen_dir.xy * mouse_delta)
				movement *= axis_depth
				translation^ += axis_world_dir * movement
				value_changed = true
			}
		}
	case .Rotate:
	case .Scale:
	}

	s_gizmo.prev_mouse_position = mouse_position
	s_gizmo.mouse_was_pressed = mouse_pressed
	return
}

get_draw_data :: proc(allocator := context.temp_allocator) -> (draw_data: Draw_Data) {
	draw_data.triangle_vertices = make([dynamic]Triangle_Vertex, allocator)
	draw_data.ring_vertices = make([dynamic]Ring_Vertex, allocator)

	switch s_gizmo.mode {
	case .Translate:
	case .Rotate:
	case .Scale:
	}

	for triangle in s_gizmo.triangles {
		color := axis_colors[triangle.axis]
		if triangle.axis == s_gizmo.selected_axis {
			highlight: f32 = 0.3 if s_gizmo.dragging else 0.15
			color = linalg.clamp(color + Vec4{ 1, 1, 1, 1 } * highlight, Vec4{ 0, 0, 0, 0 }, Vec4{ 1, 1, 1, 1 })
		}

		v1 := Triangle_Vertex{ position = triangle.p[0], color = color }
		v2 := Triangle_Vertex{ position = triangle.p[1], color = color }
		v3 := Triangle_Vertex{ position = triangle.p[2], color = color }

		append(&draw_data.triangle_vertices, v1, v2, v3)
	}

	return
}

Triangle :: struct {
	p: [3]Vec3,
	axis: Axis,
}

Triangle_Vertex :: struct {
	position: Vec3,
	color: Vec4,
}

Ring_Vertex :: struct {
	position: Vec3,
	color: Vec4,
}

// We could probably have a static buffer for the draw data, since the data has a defined max size. Then we would not
// need to use dynamic arrays; we could use slices instead.
Draw_Data :: struct {
	triangle_vertices: [dynamic]Triangle_Vertex,
	ring_vertices: [dynamic]Ring_Vertex,
}

free_draw_data :: proc(draw_data: Draw_Data) {
	delete(draw_data.triangle_vertices)
	delete(draw_data.ring_vertices)
}

@(private="file")
triangle_intersect :: proc(point: Vec2, triangle: Triangle) -> bool {
	v := [3]Vec2{ triangle.p[0].xy, triangle.p[1].xy, triangle.p[2].xy }

	edge_dir0 := v[1] - v[0]
	edge_dir1 := v[2] - v[1]
	edge_dir2 := v[0] - v[2]

	point_dir0 := point - v[0]
	point_dir1 := point - v[1]
	point_dir2 := point - v[2]

	cross_0 := linalg.cross(edge_dir0, point_dir0)
	cross_1 := linalg.cross(edge_dir1, point_dir1)
	cross_2 := linalg.cross(edge_dir2, point_dir2)

	return cross_0 >= 0 && cross_1 >= 0 && cross_2 >= 0
}
