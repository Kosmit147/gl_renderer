package gl_renderer

import imgui "glue/vendor/imgui"

import "core:fmt"
import "core:math/linalg"

editor :: proc(scene: Scene) {
	if imgui.Begin("Entities") {
		for entity, i in scene.entities {
			if imgui.TreeNode(fmt.ctprintf("%v", i)) {
				edit_transform(&entity.translation, &entity.rotation, &entity.scale)
				imgui.TreePop()
			}
		}
		imgui.End()
	}
}

edit_transform :: proc(translation: ^Vec3, rotation: ^Quat, scale: ^Vec3) -> (value_changed := false) {
	if imgui.DragFloat3("Translation", translation, v_speed = 0.01) do value_changed = true
	rotation_v := Vec4{ rotation.x, rotation.y, rotation.z, rotation.w }
	if imgui.DragFloat4("Rotation", &rotation_v, v_speed = 0.01) {
		rotation^ = linalg.normalize(quaternion(x = rotation_v.x, y = rotation_v.y, z = rotation_v.z, w = rotation_v.w))
		value_changed = true
	}
	if imgui.DragFloat3("Scale", scale, v_speed = 0.01) do value_changed = true
	return
}
