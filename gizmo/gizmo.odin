package gizmo

import "core:math/linalg"
import "core:log"

// TODO:
// - No dynamic allocations
// - contextless
// - Allow to rotate via either quaternions or euler angles
// - Mouse picking should pick the axis that is in front
// - Returned draw data should be z-sorted. Z component should probably not be returned.
// - Perform operations in screen space (e. g. translate an object parallel to the screen)
// - Scale (do circles at the ends of the lines instead of arrows)
// - Ellipse could be described by the foci.
// - Mouse picking with ellipse could be solved with the standard foci equation in screen space as well.
// - Ellipses could also be done with lines (composed of triangles like the same way translation arrows are composed).
// This would probably be the simplest way of doing rotation circles.

GIZMO_SIZE     :: 0.1
LINE_LENGTH    :: 0.2
LINE_THICKNESS :: 0.004
ARROW_WIDTH    :: 0.02
ARROW_HEIGHT   :: 0.02

X_COLOR :: Vec4{ 1, 0, 0, 0.7 }
Y_COLOR :: Vec4{ 0, 1, 0, 0.7 }
Z_COLOR :: Vec4{ 0, 0, 1, 0.7 }

HOVERED_HIGHLIGHT  :: 0.15
DRAGGING_HIGHLIGHT :: 0.3

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

X_AXIS_VEC :: Vec3{ 1, 0, 0 }
Y_AXIS_VEC :: Vec3{ 0, 1, 0 }
Z_AXIS_VEC :: Vec3{ 0, 0, 1 }

@(rodata)
axis_vectors := [Axis]Vec3{
	.X = X_AXIS_VEC,
	.Y = Y_AXIS_VEC,
	.Z = Z_AXIS_VEC,
}

@(rodata)
orthogonal_axis_vectors := [Axis][2]Vec3{
	.X = { Y_AXIS_VEC, Z_AXIS_VEC },
	.Y = { X_AXIS_VEC, Z_AXIS_VEC },
	.Z = { X_AXIS_VEC, Y_AXIS_VEC },
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

	// These are the final primitives in ndc which are going to be drawn on the screen.
	triangles: [dynamic]Triangle,
	ellipses: [dynamic]Ellipse,

	axis_directions_ss: [Axis]Vec2, // In screen space.
	axis_depths_vs: [Axis]f32, // In view space.
}

@(private="file")
s_gizmo: Gizmo

init :: proc() {
	s_gizmo.triangles = make([dynamic]Triangle)
	s_gizmo.ellipses = make([dynamic]Ellipse)
}

deinit :: proc() {
	delete(s_gizmo.triangles)
	delete(s_gizmo.ellipses)
}

manipulate :: proc(mode: Mode,
		   translation: ^Vec3,
		   rotation: ^Quat,
		   // scale: ^Vec3,
		   mouse_position: Vec2, // In NDC.
		   mouse_pressed: bool,
		   view: Mat4,
		   projection: Mat4) -> (value_changed := false) {
	clear(&s_gizmo.triangles)
	clear(&s_gizmo.ellipses)

	aspect_ratio := projection[1, 1] / projection[0, 0]

	// TODO: Delete, for debugging only.
	reference_line :: proc(translation: Vec3,
				  axis: Axis,
				  projection: Mat4,
				  view: Mat4) {
		aspect_ratio := projection[1, 1] / projection[0, 0]
		axis_vec := axis_vectors[axis]
		axis_vec_vs := linalg.matrix3_from_matrix4(view) * axis_vec

		line_start_vs := view * Vec4{ translation.x, translation.y, translation.z, 1 }
		line_end_vs := line_start_vs + Vec4{ axis_vec_vs.x, axis_vec_vs.y, axis_vec_vs.z, 0 } * (-line_start_vs.z * GIZMO_SIZE * 3)

		s_gizmo.axis_depths_vs[axis] = -line_end_vs.z

		line_start_cs := projection * line_start_vs
		line_end_cs := projection * line_end_vs

		line_start_ss := line_start_cs / line_start_cs.w
		line_end_ss := line_end_cs / line_end_cs.w

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

			p1 := line_start_ss.xyz + line_width
			p2 := line_start_ss.xyz - line_width
			p3 := line_end_ss.xyz + line_width
			p4 := line_end_ss.xyz - line_width

			append(&s_gizmo.triangles, Triangle{ { p1, p2, p3 }, axis })
			append(&s_gizmo.triangles, Triangle{ { p4, p3, p2 }, axis })
		}
	}

	translation_arrow :: proc(translation: Vec3,
				  axis: Axis,
				  projection: Mat4,
				  view: Mat4) {
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

			p1 := line_end_ss.xyz + arrow_width
			p2 := line_end_ss.xyz - arrow_width
			p3 := arrow_tip_ss.xyz

			append(&s_gizmo.triangles, Triangle{ { p1, p2, p3 }, axis })
		}
	}

	rotation_circle :: proc(translation: Vec3,
				rotation: Quat,
				axis: Axis,
				projection: Mat4,
				view: Mat4) {
		aspect_ratio := projection[1, 1] / projection[0, 0]
		axis_vec := axis_vectors[axis]
		orthogonal_axis_vecs := orthogonal_axis_vectors[axis]
		axis_vec_vs := linalg.matrix3_from_matrix4(view) * axis_vec
		orthogonal_axis_vecs_vs := [2]Vec3{
			linalg.matrix3_from_matrix4(view) * orthogonal_axis_vecs[0],
			linalg.matrix3_from_matrix4(view) * orthogonal_axis_vecs[1],
		}

		center_ws := Vec4{ translation.x, translation.y, translation.z, 1 }

		center_vs := view * center_ws
		vertices_vs: [4]Vec4
		vertices_vs[0].xyz = center_vs.xyz + ( orthogonal_axis_vecs_vs[0] +  orthogonal_axis_vecs_vs[1]) * -center_vs.z * GIZMO_SIZE
		vertices_vs[1].xyz = center_vs.xyz + ( orthogonal_axis_vecs_vs[0] + -orthogonal_axis_vecs_vs[1]) * -center_vs.z * GIZMO_SIZE
		vertices_vs[2].xyz = center_vs.xyz + (-orthogonal_axis_vecs_vs[0] +  orthogonal_axis_vecs_vs[1]) * -center_vs.z * GIZMO_SIZE
		vertices_vs[3].xyz = center_vs.xyz + (-orthogonal_axis_vecs_vs[0] + -orthogonal_axis_vecs_vs[1]) * -center_vs.z * GIZMO_SIZE
		for &v in vertices_vs do v.w = 1

		center_cs := projection * center_vs
		vertices_cs := vertices_vs
		for &v in vertices_cs do v = projection * v

		center_ss := center_cs / center_cs.w
		vertices_ss := vertices_cs
		for &v in vertices_ss do v = v / v.w

		radius_ss := Vec2{
			abs(vertices_ss[0].x - center_ss.x),
			abs(vertices_ss[0].y - center_ss.y),
		}

		append(&s_gizmo.ellipses, Ellipse{
			center = center_ss.xyz,
		 	radius = radius_ss,
			axis = axis})
	}

	switch mode {
	case .Translate:
		translation_arrow(translation^, .X, projection, view)
		translation_arrow(translation^, .Y, projection, view)
		translation_arrow(translation^, .Z, projection, view)
	case .Rotate:
		reference_line(translation^, .X, projection, view)
		reference_line(translation^, .Y, projection, view)
		reference_line(translation^, .Z, projection, view)
		rotation_circle(translation^, rotation^, .X, projection, view)
		// rotation_circle(translation^, rotation^, .Y, projection, view)
		// rotation_circle(translation^, rotation^, .Z, projection, view)
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
	draw_data.ellipse_vertices = make([dynamic]Ellipse_Vertex, allocator)

	highlight :: proc(color: Vec4, highlight: f32) -> Vec4 {
		return linalg.clamp(color + Vec4{ 1, 1, 1, 1 } * highlight, Vec4{ 0, 0, 0, 0 }, Vec4{ 1, 1, 1, 1 })
	}

	for triangle in s_gizmo.triangles {
		color := axis_colors[triangle.axis]
		if triangle.axis == s_gizmo.selected_axis {
			color = highlight(color, DRAGGING_HIGHLIGHT if s_gizmo.dragging else HOVERED_HIGHLIGHT)
		}

		v1 := Triangle_Vertex{ position = triangle.p[0], color = color }
		v2 := Triangle_Vertex{ position = triangle.p[1], color = color }
		v3 := Triangle_Vertex{ position = triangle.p[2], color = color }

		append(&draw_data.triangle_vertices, v1, v2, v3)
	}

	for ellipse in s_gizmo.ellipses {
		color := axis_colors[ellipse.axis]
		if ellipse.axis == s_gizmo.selected_axis {
			color = highlight(color, DRAGGING_HIGHLIGHT if s_gizmo.dragging else HOVERED_HIGHLIGHT)
		}

		radius_inner := ellipse.radius
		radius_outer := ellipse.radius + Vec2{ 0.01, 0.01 }

		v := [4]Ellipse_Vertex {
			{ position = ellipse.center.xy + {  radius_outer.x,  radius_outer.y } },
			{ position = ellipse.center.xy + { -radius_outer.x,  radius_outer.y } },
			{ position = ellipse.center.xy + {  radius_outer.x, -radius_outer.y } },
			{ position = ellipse.center.xy + { -radius_outer.x, -radius_outer.y } },
		}

		for &vertex in v {
			vertex.color = color
			vertex.center = ellipse.center.xy
			vertex.radius_inner = radius_inner
			vertex.radius_outer = radius_outer
		}

		append(&draw_data.ellipse_vertices, v[0], v[1], v[2])
		append(&draw_data.ellipse_vertices, v[3], v[2], v[1])
	}

	{
		// TEST ellipse vertices

		// RADIUS_INNER_OUTER :: Vec2{ 0.2, 0.205 }
		// CENTER :: Vec2{ -0.25, 0 }

		// v1 := Ellipse_Vertex{ position = Vec3{ -0.5,  0.5, 0 }, color = X_COLOR, center = CENTER, radius_inner_outer = RADIUS_INNER_OUTER }
		// v2 := Ellipse_Vertex{ position = Vec3{  0.0,  0.5, 0 }, color = X_COLOR, center = CENTER, radius_inner_outer = RADIUS_INNER_OUTER }
		// v3 := Ellipse_Vertex{ position = Vec3{  0.0, -0.5, 0 }, color = X_COLOR, center = CENTER, radius_inner_outer = RADIUS_INNER_OUTER }

		// v4 := Ellipse_Vertex{ position = Vec3{  0.0, -0.5, 0 }, color = X_COLOR, center = CENTER, radius_inner_outer = RADIUS_INNER_OUTER }
		// v5 := Ellipse_Vertex{ position = Vec3{ -0.5,  0.5, 0 }, color = X_COLOR, center = CENTER, radius_inner_outer = RADIUS_INNER_OUTER }
		// v6 := Ellipse_Vertex{ position = Vec3{ -0.5, -0.5, 0 }, color = X_COLOR, center = CENTER, radius_inner_outer = RADIUS_INNER_OUTER }

		// append(&draw_data.ellipse_vertices, v3, v2, v1)
		// append(&draw_data.ellipse_vertices, v4, v5, v6)
	}

	return
}

Triangle :: struct {
	p: [3]Vec3,
	axis: Axis,
}

Ellipse :: struct {
	center: Vec3,
	radius: Vec2,
	axis: Axis,
}

Triangle_Vertex :: struct {
	position: Vec3,
	color: Vec4,
}

Ellipse_Vertex :: struct {
	position: Vec2,
	color: Vec4,
	center: Vec2,
	radius_inner: Vec2,
	radius_outer: Vec2,
}

// We could probably have a static buffer for the draw data, since the data has a defined max size. Then we would not
// need to use dynamic arrays; we could use slices instead.
Draw_Data :: struct {
	triangle_vertices: [dynamic]Triangle_Vertex,
	ellipse_vertices: [dynamic]Ellipse_Vertex,
}

free_draw_data :: proc(draw_data: Draw_Data) {
	delete(draw_data.triangle_vertices)
	delete(draw_data.ellipse_vertices)
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

@(private="file")
ellipse_intersect :: proc(point: Vec2, ellipse: Ellipse) -> bool {
	return false
}
