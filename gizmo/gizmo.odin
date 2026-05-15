package gizmo

import "base:runtime"

import "core:math"
import "core:math/linalg"
import "core:slice"

// TODO:
// - Allow to rotate via either quaternions or euler angles.
// - Ability to perform operations in screen space (e. g. translate an object parallel to the screen).
// - Ability to perform operations in local space.
// - Gizmo size should be a parameter.
// - Support generic types instead of just f32s.
// - Should work with any either left-handed or right-handed, y-down or y-up coordinate systems.
// - Should work with orthographic projection.
// - Make sure it's not too slow.
// - Visuals for rotation circles should be nicer. This could be done by only drawing half-circles on a closer
// hemisphere of the rotation sphere.
// - Fix gizmo still rendering when it's behind the camera.

GIZMO_SIZE               :: 0.06
LINE_THICKNESS           :: 0.004
ARROW_WIDTH              :: 0.02
ARROW_HEIGHT             :: 0.02
SCALE_CIRCLE_SIZE        :: 0.013
ROTATION_CIRCLE_SEGMENTS :: 64
SCALE_CIRCLE_TRIANGLES   :: 16

SCALING_SPEED :: 0.5

HOVER_HIGHLIGHT    :: 0.15
INTERACT_HIGHLIGHT :: 0.3

TRANSLATION_TRIANGLE_COUNT :: (2 + 1) * 3                       // (Line + arrow) * 3 axes.
ROTATION_TRIANGLE_COUNT    :: ROTATION_CIRCLE_SEGMENTS * 2 * 3  // 2 triangles per segment * 3 axes.
SCALE_TRIANGLE_COUNT       :: 2 + SCALE_CIRCLE_TRIANGLES        // Line + circle
MAX_TRIANGLES              :: max(TRANSLATION_TRIANGLE_COUNT, ROTATION_TRIANGLE_COUNT, SCALE_TRIANGLE_COUNT)
MAX_TRIANGLE_VERTICES      :: MAX_TRIANGLES * 3

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
axis_colors := [Axis]Vec4{
	.X = { 0.8,   0,   0, 1 },
	.Y = {   0, 0.8,   0, 1 },
	.Z = {   0,   0, 0.8, 1 },
}

Mode :: enum {
	Translate,
	Rotate,
	Scale,
}

Gizmo :: struct {
	view: Mat4,
	projection: Mat4,
	aspect_ratio: f32,
	camera_forward_ws: Vec3,
	mouse_ray_ws: Ray,

	origin_ws: Vec4,
	origin_vs: Vec4,
	origin_cs: Vec4,
	origin_ss: Vec4,

	selected_axis: Maybe(Axis),

	original_translation: Maybe(Vec3),
	reference_translation_value: Maybe(f32),
	original_rotation: Maybe(Quat),
	reference_rotation_angle: Maybe(f32),
	original_scale: Maybe(Vec3),
	reference_scale_value: Maybe(f32),
}

@(private="file")
s_gizmo: Gizmo

@(private="file")
s_triangle_vertices: [dynamic; MAX_TRIANGLE_VERTICES]Triangle_Vertex

manipulate :: proc "contextless" (mode: Mode,
				  translation: ^Vec3,
				  rotation: ^Quat,
				  scale: ^Vec3,
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
	s_gizmo.camera_forward_ws = Vec3{ view[2, 0], view[2, 1], view[2, 2] }
	s_gizmo.origin_ws = Vec4{ expand_values(translation^), 1 }
	s_gizmo.origin_vs = view * s_gizmo.origin_ws
	s_gizmo.origin_cs = projection * s_gizmo.origin_vs
	s_gizmo.origin_ss = s_gizmo.origin_cs / s_gizmo.origin_cs.w

	{
		camera_position_ws := (view_inverse * Vec4{ 0, 0, 0, 1 }).xyz
		ray_cs := Vec4{ expand_values(mouse_position), -1, 1 }
		ray_vs := projection_inverse * ray_cs
		ray_direction_ws := linalg.normalize((view_inverse * Vec4{ expand_values(ray_vs.xyz), 0 }).xyz)
		s_gizmo.mouse_ray_ws = Ray{ origin = camera_position_ws, direction = ray_direction_ws }
	}

	ws_to_ss :: proc "contextless" (ws: Vec4) -> Vec4 {
		vs := s_gizmo.view * ws
		cs := s_gizmo.projection * vs
		ss := cs / cs.w
		return ss
	}

	add_triangle :: proc "contextless" (p1, p2, p3: Vec3,
					    axis: Axis,
					    triangles: ^[dynamic; MAX_TRIANGLES]Triangle) {
		append(triangles, Triangle {
			points = { p1.xy, p2.xy, p3.xy },
			depth = (p1.z + p2.z + p3.z) / 3,
			axis = axis,
		})
	}

	translation_gizmo :: proc "contextless" (axis: Axis, triangles: ^[dynamic; MAX_TRIANGLES]Triangle) {
		line_end_ws := s_gizmo.origin_ws + Vec4{ expand_values(axis_vectors[axis]), 0 } * -s_gizmo.origin_vs.z * GIZMO_SIZE
		arrow_tip_ws := line_end_ws + Vec4{ expand_values(axis_vectors[axis]), 0 } * -s_gizmo.origin_vs.z * ARROW_HEIGHT

		line_end_ss := ws_to_ss(line_end_ws)
		arrow_tip_ss := ws_to_ss(arrow_tip_ws)

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

			add_triangle(p1, p2, p3, axis, triangles)
			add_triangle(p4, p3, p2, axis, triangles)
		}

		{
			arrow_width := Vec3{ line_direction_orthogonal_ss.x * ARROW_WIDTH / s_gizmo.aspect_ratio,
				             line_direction_orthogonal_ss.y * ARROW_WIDTH,
				             0 }

			p1 := line_end_ss.xyz + arrow_width
			p2 := line_end_ss.xyz - arrow_width
			p3 := arrow_tip_ss.xyz

			add_triangle(p1, p2, p3, axis, triangles)
		}
	}

	rotation_gizmo :: proc "contextless" (axis: Axis, triangles: ^[dynamic; MAX_TRIANGLES]Triangle) {
		segment :: proc "contextless" (start_ws: Vec4,
					       end_ws: Vec4,
					       axis: Axis,
					       triangles: ^[dynamic; MAX_TRIANGLES]Triangle) {
			start_ss := ws_to_ss(start_ws)
			end_ss := ws_to_ss(end_ws)

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

			add_triangle(p1, p2, p3, axis, triangles)
			add_triangle(p4, p3, p2, axis, triangles)
		}

		for i in 0..<ROTATION_CIRCLE_SEGMENTS {
			ANGLE_STEP :: math.TAU / ROTATION_CIRCLE_SEGMENTS
			start_angle := f32(i) * ANGLE_STEP
			end_angle := f32(i + 1) * ANGLE_STEP
			start_offset_ws: Vec4
			end_offset_ws: Vec4
			switch axis {
			case .X:
				start_offset_ws = Vec4{ 0, math.sin(start_angle), math.cos(start_angle), 0 }
				end_offset_ws = Vec4{ 0, math.sin(end_angle), math.cos(end_angle), 0 }
			case .Y:
				start_offset_ws = Vec4{ math.sin(start_angle), 0, math.cos(start_angle), 0 }
				end_offset_ws = Vec4{ math.sin(end_angle), 0, math.cos(end_angle), 0 }
			case .Z:
				start_offset_ws = Vec4{ math.cos(start_angle), math.sin(start_angle), 0, 0 }
				end_offset_ws = Vec4{ math.cos(end_angle), math.sin(end_angle), 0, 0 }
			}
			start_point_ws := s_gizmo.origin_ws + start_offset_ws * -s_gizmo.origin_vs.z * GIZMO_SIZE
			end_point_ws := s_gizmo.origin_ws + end_offset_ws * -s_gizmo.origin_vs.z * GIZMO_SIZE
			segment(start_point_ws, end_point_ws, axis, triangles)
		}
	}

	scale_gizmo :: proc "contextless" (axis: Axis, triangles: ^[dynamic; MAX_TRIANGLES]Triangle) {
		line_end_ws := s_gizmo.origin_ws + Vec4{ expand_values(axis_vectors[axis]), 0 } * -s_gizmo.origin_vs.z * GIZMO_SIZE
		line_end_ss := ws_to_ss(line_end_ws)

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

			add_triangle(p1, p2, p3, axis, triangles)
			add_triangle(p4, p3, p2, axis, triangles)
		}

		for i in 0..<SCALE_CIRCLE_TRIANGLES {
			ANGLE_STEP :: math.TAU / SCALE_CIRCLE_TRIANGLES
			start_angle := f32(i) * ANGLE_STEP
			end_angle := f32(i + 1) * ANGLE_STEP

			start_offset_ss := Vec4{ math.sin(start_angle), math.cos(start_angle), 0, 0 }
			end_offset_ss := Vec4{ math.sin(end_angle), math.cos(end_angle), 0, 0 }

			start_offset_ss *= SCALE_CIRCLE_SIZE
			end_offset_ss *= SCALE_CIRCLE_SIZE

			start_offset_ss.x /= s_gizmo.aspect_ratio
			end_offset_ss.x /= s_gizmo.aspect_ratio

			p1 := line_end_ss.xyz
			p2 := line_end_ss.xyz + start_offset_ss.xyz
			p3 := line_end_ss.xyz + end_offset_ss.xyz

			add_triangle(p3, p2, p1, axis, triangles)
		}
	}

	switch mode {
	case .Translate:
		translation_gizmo(.X, &triangles)
		translation_gizmo(.Y, &triangles)
		translation_gizmo(.Z, &triangles)
	case .Rotate:
		rotation_gizmo(.X, &triangles)
		rotation_gizmo(.Y, &triangles)
		rotation_gizmo(.Z, &triangles)
	case .Scale:
		scale_gizmo(.X, &triangles)
		scale_gizmo(.Y, &triangles)
		scale_gizmo(.Z, &triangles)
	}

	{
		context = runtime.Context{}
		slice.sort_by(triangles[:], proc(i, j: Triangle) -> bool { return i.depth > j.depth })
	}

	if !mouse_pressed {
		s_gizmo.selected_axis = nil
		s_gizmo.original_translation = nil
		s_gizmo.reference_translation_value = nil
		s_gizmo.original_rotation = nil
		s_gizmo.reference_rotation_angle = nil
		s_gizmo.original_scale = nil
		s_gizmo.reference_scale_value = nil
		for triangle in triangles {
			if point_triangle_intersect(mouse_position, triangle) {
				s_gizmo.selected_axis = triangle.axis
			}
		}
	}
	interacting := mouse_pressed && s_gizmo.selected_axis != nil

	if interacting {
		switch mode {
		case .Translate:
			axis := s_gizmo.selected_axis.?

			plane_normal := s_gizmo.camera_forward_ws

			switch axis {
			case .X: plane_normal.x = 0
			case .Y: plane_normal.y = 0
			case .Z: plane_normal.z = 0
			}

			plane_normal = linalg.normalize0(plane_normal)

			if plane_normal != Vec3(0) {
				plane := Plane {
					normal = plane_normal,
					point = translation^,
				}
				hit_point, plane_hit := ray_plane_intersect(s_gizmo.mouse_ray_ws, plane)
				if plane_hit {
					if s_gizmo.original_translation == nil do s_gizmo.original_translation = translation^
					translation_change: Vec3
					switch axis {
					case .X:
						if s_gizmo.reference_translation_value == nil {
							s_gizmo.reference_translation_value = hit_point.x
						}
						translation_change.x = hit_point.x - s_gizmo.reference_translation_value.?
					case .Y:
						if s_gizmo.reference_translation_value == nil {
							s_gizmo.reference_translation_value = hit_point.y
						}
						translation_change.y = hit_point.y - s_gizmo.reference_translation_value.?
					case .Z:
						if s_gizmo.reference_translation_value == nil {
							s_gizmo.reference_translation_value = hit_point.z
						}
						translation_change.z = hit_point.z - s_gizmo.reference_translation_value.?
					}
					translation^ = s_gizmo.original_translation.? + translation_change
					value_changed = true
				}
			}
		case .Rotate:
			axis := s_gizmo.selected_axis.?

			rotation_plane := Plane {
				normal = axis_vectors[axis],
				point = translation^,
			}

			hit_point, plane_hit := ray_plane_intersect(s_gizmo.mouse_ray_ws, rotation_plane)

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
		case .Scale:
			axis := s_gizmo.selected_axis.?

			plane_normal := s_gizmo.camera_forward_ws

			switch axis {
			case .X: plane_normal.x = 0
			case .Y: plane_normal.y = 0
			case .Z: plane_normal.z = 0
			}

			plane_normal = linalg.normalize0(plane_normal)

			if plane_normal != Vec3(0) {
				plane := Plane {
					normal = plane_normal,
					point = translation^,
				}
				hit_point, plane_hit := ray_plane_intersect(s_gizmo.mouse_ray_ws, plane)
				if plane_hit {
					if s_gizmo.original_scale == nil do s_gizmo.original_scale = scale^
					scale_change: Vec3
					switch axis {
					case .X:
						if s_gizmo.reference_scale_value == nil {
							s_gizmo.reference_scale_value = hit_point.x
						}
						scale_change.x = hit_point.x - s_gizmo.reference_scale_value.?
					case .Y:
						if s_gizmo.reference_scale_value == nil {
							s_gizmo.reference_scale_value = hit_point.y
						}
						scale_change.y = hit_point.y - s_gizmo.reference_scale_value.?
					case .Z:
						if s_gizmo.reference_scale_value == nil {
							s_gizmo.reference_scale_value = hit_point.z
						}
						scale_change.z = hit_point.z - s_gizmo.reference_scale_value.?
					}
					scale^ = s_gizmo.original_scale.? + scale_change * SCALING_SPEED
					value_changed = true
				}
			}
		}
	}

	for triangle in triangles {
		if interacting && triangle.axis != s_gizmo.selected_axis do continue

		color := axis_colors[triangle.axis]
		if triangle.axis == s_gizmo.selected_axis {
			highlight: f32 = INTERACT_HIGHLIGHT if interacting else HOVER_HIGHLIGHT
			color = linalg.clamp(color + Vec4(1) * highlight, Vec4(0), Vec4(1))
		}

		v1 := Triangle_Vertex{ position = triangle.points[0], color = color }
		v2 := Triangle_Vertex{ position = triangle.points[1], color = color }
		v3 := Triangle_Vertex{ position = triangle.points[2], color = color }
		append(&s_triangle_vertices, v1, v2, v3)
	}

	return
}

get_draw_data :: proc "contextless" () -> []Triangle_Vertex {
	return s_triangle_vertices[:]
}

Triangle_Vertex :: struct {
	position: Vec2,
	color: Vec4,
}

Triangle :: struct {
	points: [3]Vec2,
	depth: f32,
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
	v := triangle.points

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
