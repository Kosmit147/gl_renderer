package gl_renderer

import "base:intrinsics"

import imgui "glue/vendor/imgui"

import "core:fmt"

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
