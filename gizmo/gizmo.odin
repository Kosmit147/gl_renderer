package gizmo

import "core:math/linalg"

GIZMO_SIZE     :: 0.1
LINE_LENGTH    :: 0.2
LINE_THICKNESS :: 0.004
ARROW_WIDTH    :: 0.02
ARROW_HEIGHT   :: 0.02

X_COLOR :: Vec4{ 1, 0, 0, 0.7 }
Y_COLOR :: Vec4{ 0, 1, 0, 0.7 }
Z_COLOR :: Vec4{ 0, 0, 1, 0.7 }

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
	prev_mouse_position: Vec2, // In NDC.
	mouse_was_pressed: bool,

	selected_axis: Maybe(Axis),
	dragging: bool,

	// These are the final triangles in ndc which are going to be drawn on the screen.
	triangles: [dynamic]Triangle,

	axis_directions_ss: [Axis]Vec2,
	axis_depths_vs: [Axis]f32,
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

manipulate :: proc(mode: Mode,
		   translation: ^Vec3,
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
		aspect_ratio := projection[1, 1] / projection[0, 0]
		axis_vec := axis_vectors[axis]
		axis_vec_vs := linalg.matrix3_from_matrix4(view) * axis_vec

		line_start_vs := view * Vec4{ translation.x, translation.y, translation.z, 1 }
		line_end_vs := line_start_vs + Vec4{ axis_vec_vs.x, axis_vec_vs.y, axis_vec_vs.z, 0 } * (-line_start_vs.z * GIZMO_SIZE)
		arrow_tip_vs := line_end_vs + Vec4{ axis_vec_vs.x, axis_vec_vs.y, axis_vec_vs.z, 0 } * (-line_start_vs.z * ARROW_HEIGHT)

		s_gizmo.axis_depths_vs[axis] = -line_end_vs.z

		line_start_cs := projection * line_start_vs
		line_end_cs := projection * line_end_vs
		arrow_tip_cs := projection * arrow_tip_vs

		line_start_ss := line_start_cs / line_start_cs.w
		line_end_ss := line_end_cs / line_end_cs.w
		arrow_tip_ss := arrow_tip_cs / arrow_tip_cs.w

		line_direction_ss := linalg.normalize0((line_end_ss - line_start_ss).xy)
		s_gizmo.axis_directions_ss[axis] = line_direction_ss
		line_direction_orthogonal_ss := linalg.orthogonal(line_direction_ss)
		line_direction_orthogonal_ss.x /= aspect_ratio
		line_direction_orthogonal_ss = linalg.normalize0(line_direction_orthogonal_ss)

		{
			// Line
			line_width := Vec3{ line_direction_orthogonal_ss.x * LINE_THICKNESS / aspect_ratio,
				            line_direction_orthogonal_ss.y * LINE_THICKNESS,
				            0 }
			line_length := Vec3{ line_direction_ss.x * LINE_LENGTH,
					     line_direction_ss.y * LINE_LENGTH,
					     0}

			p1 := line_start_ss.xyz + line_width
			p2 := line_start_ss.xyz - line_width
			p3 := line_end_ss.xyz + line_width
			p4 := line_end_ss.xyz - line_width

			append(&s_gizmo.triangles, Triangle{ { p1, p2, p3 }, axis })
			append(&s_gizmo.triangles, Triangle{ { p4, p3, p2 }, axis })
		}

		{
			// Arrow
			arrow_width := Vec3{ line_direction_orthogonal_ss.x * ARROW_WIDTH / aspect_ratio,
				             line_direction_orthogonal_ss.y * ARROW_WIDTH,
				             0 }
			line_length := Vec3{ line_direction_ss.x * LINE_LENGTH,
					     line_direction_ss.y * LINE_LENGTH,
					     0}

			p1 := line_end_ss.xyz + arrow_width
			p2 := line_end_ss.xyz - arrow_width
			p3 := arrow_tip_ss.xyz

			append(&s_gizmo.triangles, Triangle{ { p1, p2, p3 }, axis })
		}
	}

	switch mode {
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

	switch mode {
	case .Translate:
		if s_gizmo.dragging {
			if mouse_position != s_gizmo.prev_mouse_position {
				mouse_delta := mouse_position - s_gizmo.prev_mouse_position
				axis := s_gizmo.selected_axis.(Axis)

				axis_dir_ss := s_gizmo.axis_directions_ss[axis]
				axis_depth_vs := s_gizmo.axis_depths_vs[axis]

				movement := linalg.dot(linalg.normalize0(axis_dir_ss), linalg.normalize0(mouse_delta)) * linalg.length(mouse_delta)
				movement *= axis_depth_vs
				translation^ += axis_vectors[axis] * movement
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
