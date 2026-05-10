package gizmo

import "core:math"
import "core:math/linalg"

// TODO:
// - Scale (do circles or cubes at the ends of the lines instead of arrows).
// - Allow to rotate via either quaternions or euler angles.
// - Mouse picking should pick the axis that is in front.
// - Returned draw data should be z-sorted. Z component should probably not be returned.
// - Ability to perform operations in screen space (e. g. translate an object parallel to the screen).
// - Gizmo size should be a parameter.
// - Ability to perform operations in local space instead of world space.
// - Support generic types instead of just f32s.
// - Should work with any either left-handed or right-handed, y-down or y-up coordinate systems.
// - Should work with orthographic projection.
// - When performing an operation on one axis, visuals for other axes should disappear (e. g. when rotating along the X
// axis, the rotation circles for Y and Z axes should disappear)

GIZMO_SIZE               :: 0.06
LINE_LENGTH              :: 0.2
LINE_THICKNESS           :: 0.004
ARROW_WIDTH              :: 0.02
ARROW_HEIGHT             :: 0.02
ROTATION_CIRCLE_SEGMENTS :: 64

TRANSLATION_TRIANGLE_COUNT :: (2 + 1) * 3 // (Line + arrow) * 3 axes.
ROTATION_TRIANGLE_COUNT :: ROTATION_CIRCLE_SEGMENTS * 2 * 3 // 2 triangles per segment * 3 axes.
MAX_TRIANGLES :: max(TRANSLATION_TRIANGLE_COUNT, ROTATION_TRIANGLE_COUNT)
MAX_TRIANGLE_VERTICES :: MAX_TRIANGLES * 3

Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32
Mat3 :: matrix[3, 3]f32
Mat4 :: matrix[4, 4]f32
Quat :: quaternion128

Axis :: enum {
	X,
	Y,
	Z,
}

@(rodata)
axis_vectors := [Axis]Vec3{
	.X = { 1, 0, 0 },
	.Y = { 0, 1, 0 },
	.Z = { 0, 0, 1 },
}

@(rodata)
translation_plane_normals := [Axis]Vec3{
	.X = { 0, 1, 0 },
	.Y = { 0, 0, 1 },
	.Z = { 0, 1, 0 },
}

HOVER_HIGHLIGHT    :: 0.15
INTERACT_HIGHLIGHT :: 0.3
COLOR_ALPHA        :: 0.7

Mode :: enum {
	Translate,
	Rotate,
}

Gizmo :: struct {
	view: Mat4,
	projection: Mat4,
	aspect_ratio: f32,
	camera_forward: Vec3,
	camera_position: Vec3,
	mouse_ray: Ray,

	// Probably don't need to save all of these.
	origin_ws: Vec4,
	origin_vs: Vec4,
	origin_cs: Vec4,
	origin_ss: Vec4,

	selected_axis: Maybe(Axis),

	interacting: bool,
	original_translation: Maybe(Vec3),
	reference_translation_value: Maybe(f32),
	original_rotation: Maybe(Quat),
	reference_rotation_angle: Maybe(f32),

	prev_mouse_position: Vec2, // In NDC.
}

@(private="file")
s_gizmo: Gizmo

@(private="file")
s_triangle_vertices: [dynamic; MAX_TRIANGLE_VERTICES]Triangle_Vertex

manipulate :: proc "contextless" (mode: Mode,
				  translation: ^Vec3,
				  rotation: ^Quat,
				  mouse_position: Vec2, // In NDC.
				  mouse_pressed: bool,
				  view: Mat4,
				  projection: Mat4) -> (value_changed := false) {
	triangles: [dynamic; MAX_TRIANGLES]Triangle
	clear(&s_triangle_vertices)

	view_inverse := linalg.inverse(view)
	projection_inverse := linalg.inverse(projection)

	s_gizmo.view = view
	s_gizmo.projection = projection
	s_gizmo.aspect_ratio = projection[1, 1] / projection[0, 0]
	s_gizmo.camera_forward = -Vec3{ view[2, 0], view[2, 1], view[2, 2] }
	s_gizmo.camera_position = (view_inverse * Vec4{ 0, 0, 0, 1 }).xyz

	{
		ray_cs := Vec4{ expand_values(mouse_position), -1, 1 }
		ray_vs := projection_inverse * ray_cs
		ray_direction := linalg.normalize((view_inverse * Vec4{ expand_values(ray_vs.xyz), 0 }).xyz)
		s_gizmo.mouse_ray = Ray{ origin = s_gizmo.camera_position, direction = ray_direction }
	}

	s_gizmo.origin_ws = Vec4{ expand_values(translation^), 1 }
	s_gizmo.origin_vs = view * s_gizmo.origin_ws
	s_gizmo.origin_cs = projection * s_gizmo.origin_vs
	s_gizmo.origin_ss = s_gizmo.origin_cs / s_gizmo.origin_cs.w

	translation_arrow :: proc "contextless" (axis: Axis, triangles: ^[dynamic; MAX_TRIANGLES]Triangle) {
		line_end_ws := s_gizmo.origin_ws + Vec4{ expand_values(axis_vectors[axis]), 0 } * -s_gizmo.origin_vs.z * GIZMO_SIZE
		arrow_tip_ws := line_end_ws + Vec4{ expand_values(axis_vectors[axis]), 0 } * -s_gizmo.origin_vs.z * ARROW_HEIGHT

		line_end_vs := s_gizmo.view * line_end_ws
		arrow_tip_vs := s_gizmo.view * arrow_tip_ws

		line_end_cs := s_gizmo.projection * line_end_vs
		arrow_tip_cs := s_gizmo.projection * arrow_tip_vs

		line_end_ss := line_end_cs / line_end_cs.w
		arrow_tip_ss := arrow_tip_cs / arrow_tip_cs.w

		line_direction_ss := linalg.normalize0((line_end_ss - s_gizmo.origin_ss).xy)
		line_direction_orthogonal_ss := linalg.orthogonal(line_direction_ss)
		line_direction_orthogonal_ss.x /= s_gizmo.aspect_ratio
		line_direction_orthogonal_ss = linalg.normalize0(line_direction_orthogonal_ss)

		{
			line_width := Vec3{ line_direction_orthogonal_ss.x * LINE_THICKNESS / s_gizmo.aspect_ratio,
				            line_direction_orthogonal_ss.y * LINE_THICKNESS,
				            0 }

			p1 := s_gizmo.origin_ss.xyz + line_width
			p2 := s_gizmo.origin_ss.xyz - line_width
			p3 := line_end_ss.xyz + line_width
			p4 := line_end_ss.xyz - line_width

			t1 := Triangle{ { p1, p2, p3 }, axis }
			t2 := Triangle{ { p4, p3, p2 }, axis }

			append(triangles, t1, t2)
		}

		{
			arrow_width := Vec3{ line_direction_orthogonal_ss.x * ARROW_WIDTH / s_gizmo.aspect_ratio,
				             line_direction_orthogonal_ss.y * ARROW_WIDTH,
				             0 }

			p1 := line_end_ss.xyz + arrow_width
			p2 := line_end_ss.xyz - arrow_width
			p3 := arrow_tip_ss.xyz

			append(triangles, Triangle{ { p1, p2, p3 }, axis })
		}
	}

	rotation_circle :: proc "contextless" (axis: Axis, triangles: ^[dynamic; MAX_TRIANGLES]Triangle) {
		segment :: proc "contextless" (start_vs: Vec4,
					       end_vs: Vec4,
					       axis: Axis,
					       triangles: ^[dynamic; MAX_TRIANGLES]Triangle) {
			start_cs := s_gizmo.projection * start_vs
			end_cs := s_gizmo.projection * end_vs

			start_ss := start_cs / start_cs.w
			end_ss := end_cs / end_cs.w

			line_direction_ss := linalg.normalize0((end_ss - start_ss).xy)
			line_direction_orthogonal_ss := linalg.orthogonal(line_direction_ss)
			line_direction_orthogonal_ss.x /= s_gizmo.aspect_ratio
			line_direction_orthogonal_ss = linalg.normalize0(line_direction_orthogonal_ss)

			line_width := Vec3{ line_direction_orthogonal_ss.x * LINE_THICKNESS / s_gizmo.aspect_ratio,
				            line_direction_orthogonal_ss.y * LINE_THICKNESS,
				            0 }

			p1 := start_ss.xyz + line_width
			p2 := start_ss.xyz - line_width
			p3 := end_ss.xyz + line_width
			p4 := end_ss.xyz - line_width

			t1 := Triangle{ { p1, p2, p3 }, axis }
			t2 := Triangle{ { p4, p3, p2 }, axis }

			append(triangles, t1, t2)
		}

		for i in 0..<ROTATION_CIRCLE_SEGMENTS {
			ANGLE_STEP :: math.TAU / ROTATION_CIRCLE_SEGMENTS
			start_angle := f32(i) * ANGLE_STEP
			end_angle := f32(i + 1) * ANGLE_STEP
			start_point_ws: Vec4
			end_point_ws: Vec4
			switch axis {
			case .X:
				start_point_ws = s_gizmo.origin_ws + Vec4{ 0, math.sin(start_angle), math.cos(start_angle), 0 } * (-s_gizmo.origin_vs.z * GIZMO_SIZE)
				end_point_ws = s_gizmo.origin_ws + Vec4{ 0, math.sin(end_angle), math.cos(end_angle), 0 } * (-s_gizmo.origin_vs.z * GIZMO_SIZE)
			case .Y:
				start_point_ws = s_gizmo.origin_ws + Vec4{ math.sin(start_angle), 0, math.cos(start_angle), 0 } * (-s_gizmo.origin_vs.z * GIZMO_SIZE)
				end_point_ws = s_gizmo.origin_ws + Vec4{ math.sin(end_angle), 0, math.cos(end_angle), 0 } * (-s_gizmo.origin_vs.z * GIZMO_SIZE)
			case .Z:
				start_point_ws = s_gizmo.origin_ws + Vec4{ math.cos(start_angle), math.sin(start_angle), 0, 0 } * (-s_gizmo.origin_vs.z * GIZMO_SIZE)
				end_point_ws = s_gizmo.origin_ws + Vec4{ math.cos(end_angle), math.sin(end_angle), 0, 0 } * (-s_gizmo.origin_vs.z * GIZMO_SIZE)
			}
			segment(s_gizmo.view * start_point_ws, s_gizmo.view * end_point_ws, axis, triangles)
		}
	}

	switch mode {
	case .Translate:
		translation_arrow(.X, &triangles)
		translation_arrow(.Y, &triangles)
		translation_arrow(.Z, &triangles)
	case .Rotate:
		rotation_circle(.X, &triangles)
		rotation_circle(.Y, &triangles)
		rotation_circle(.Z, &triangles)
	}

	if !mouse_pressed {
		s_gizmo.selected_axis = nil
		s_gizmo.original_translation = nil
		s_gizmo.reference_translation_value = nil
		s_gizmo.original_rotation = nil
		s_gizmo.reference_rotation_angle = nil
		for triangle in triangles {
			if point_triangle_intersect(mouse_position, triangle) {
				s_gizmo.selected_axis = triangle.axis
			}
		}
	}
	s_gizmo.interacting = mouse_pressed && s_gizmo.selected_axis != nil

	switch mode {
	case .Translate:
		if s_gizmo.interacting {
			axis := s_gizmo.selected_axis.?

			translation_plane := Plane {
				normal = translation_plane_normals[axis],
				point = translation^,
			}

			hit_point, plane_hit := ray_plane_intersect(s_gizmo.mouse_ray, translation_plane)

			if plane_hit {
				if s_gizmo.original_translation == nil do s_gizmo.original_translation = translation^
				translation_change: Vec3
				switch axis {
				case .X:
					if s_gizmo.reference_translation_value == nil do s_gizmo.reference_translation_value = hit_point.x
					translation_change.x = hit_point.x - s_gizmo.reference_translation_value.?
				case .Y:
					if s_gizmo.reference_translation_value == nil do s_gizmo.reference_translation_value = hit_point.y
					translation_change.y = hit_point.y - s_gizmo.reference_translation_value.?
				case .Z:
					if s_gizmo.reference_translation_value == nil do s_gizmo.reference_translation_value = hit_point.z
					translation_change.z = hit_point.z - s_gizmo.reference_translation_value.?
				}

				translation^ = s_gizmo.original_translation.? + translation_change
				value_changed = true
			}
		}
	case .Rotate:
		if s_gizmo.interacting {
			axis := s_gizmo.selected_axis.?

			rotation_plane := Plane {
				normal = axis_vectors[axis],
				point = translation^,
			}

			hit_point, plane_hit := ray_plane_intersect(s_gizmo.mouse_ray, rotation_plane)

			if plane_hit {
				if s_gizmo.original_rotation == nil do s_gizmo.original_rotation = rotation^
				angle_vec: Vec2
				switch axis {
				case .X: angle_vec = linalg.normalize0(hit_point.yz - translation.yz)
				case .Y: angle_vec = linalg.normalize0(hit_point.zx - translation.zx)
				case .Z: angle_vec = linalg.normalize0(hit_point.xy - translation.xy)
				}

				angle: f32
				if angle_vec.y > 0 {
					angle = linalg.angle_between(Vec2{ 1, 0 }, angle_vec)
				} else {
					angle = linalg.angle_between(Vec2{ -1, 0 }, angle_vec) + math.to_radians(f32(180))
				}

				if s_gizmo.reference_rotation_angle == nil do s_gizmo.reference_rotation_angle = angle
				angle_change := angle - s_gizmo.reference_rotation_angle.?
				rotation_change := linalg.quaternion_angle_axis(angle_change, axis_vectors[axis])
				rotation^ = linalg.normalize(rotation_change * s_gizmo.original_rotation.?)
				value_changed = true
			}
		}
	}

	for triangle in triangles {
		color := Vec4{ expand_values(axis_vectors[triangle.axis]), COLOR_ALPHA }
		if triangle.axis == s_gizmo.selected_axis {
			highlight: f32 = INTERACT_HIGHLIGHT if s_gizmo.interacting else HOVER_HIGHLIGHT
			color = linalg.clamp(color + Vec4(1) * highlight, Vec4(0), Vec4(1))
		}

		v1 := Triangle_Vertex{ position = triangle.p[0], color = color }
		v2 := Triangle_Vertex{ position = triangle.p[1], color = color }
		v3 := Triangle_Vertex{ position = triangle.p[2], color = color }

		append(&s_triangle_vertices, v1, v2, v3)
	}

	s_gizmo.prev_mouse_position = mouse_position
	return
}

get_draw_data :: proc "contextless" () -> []Triangle_Vertex {
	return s_triangle_vertices[:]
}

Triangle_Vertex :: struct {
	position: Vec3,
	color: Vec4,
}

Triangle :: struct {
	p: [3]Vec3,
	axis: Axis,
}

Ray :: struct {
	origin: Vec3,
	direction: Vec3,
}

Plane :: struct {
	normal: Vec3,
	point: Vec3,
}

@(private="file")
point_triangle_intersect :: proc "contextless" (point: Vec2, triangle: Triangle) -> bool {
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
ray_plane_intersect :: proc "contextless" (ray: Ray, plane: Plane) -> (Vec3, bool) {
	num := linalg.dot(linalg.normalize0(plane.normal), plane.point - ray.origin)
	denom := linalg.dot(linalg.normalize0(plane.normal), linalg.normalize0(ray.direction))
	if num == 0 || denom == 0 do return {}, false
	t := num / denom
	return ray.origin + ray.direction * t, t > 0
}
