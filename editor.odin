package gl_renderer

import "gizmo"
import "glue"
import imgui "glue/vendor/imgui"
import gl "vendor:OpenGL"

import "core:fmt"
import "core:math/linalg"
import "core:slice"

GIZMO_TRANSLATE_KEY :: glue.Key.Q
GIZMO_ROTATE_KEY    :: glue.Key.E
GIZMO_SCALE_KEY     :: glue.Key.R

Editor :: struct {
  selected_entity_index: Maybe(uint),

  gizmo_operation: gizmo.Operation,
  gizmo_mode: gizmo.Mode,

  gizmo_shader: Shader,
  gizmo_va: glue.Vertex_Array,
  gizmo_vb: glue.Gl_Buffer,
}

editor_init :: proc(editor: ^Editor) -> (ok := false) {
  vertex_format := []glue.Vertex_Attribute{ .Float_2, .Float_4 }

  glue.create_vertex_array(&editor.gizmo_va)
  defer if !ok do glue.destroy_vertex_array(&editor.gizmo_va)
  glue.create_dynamic_gl_buffer(&editor.gizmo_vb)
  defer if !ok do glue.destroy_gl_buffer(&editor.gizmo_vb)
  glue.set_vertex_array_format(editor.gizmo_va, vertex_format)
  glue.bind_vertex_buffer(editor.gizmo_va, editor.gizmo_vb, size_of(gizmo.Triangle_Vertex))

  editor.gizmo_shader = glue.create_shader(#load("shaders/gizmo_triangle.vert"),
                                           #load("shaders/gizmo_triangle.frag")) or_return

  ok = true
  return
}

editor_deinit :: proc(editor: ^Editor) {
  glue.destroy_shader(editor.gizmo_shader)
  glue.destroy_gl_buffer(&editor.gizmo_vb)
  glue.destroy_vertex_array(&editor.gizmo_va)
}

editor_on_event :: proc(editor: ^Editor, event: glue.Event) {
  #partial switch event in event {
  case glue.Key_Pressed_Event:
    #partial switch event.key {
    case GIZMO_TRANSLATE_KEY:
      editor.gizmo_operation = .Translate
      editor.gizmo_mode = .World
    case GIZMO_ROTATE_KEY:
      editor.gizmo_operation = .Rotate
      editor.gizmo_mode = .Local
    case GIZMO_SCALE_KEY:
      editor.gizmo_operation = .Scale
      editor.gizmo_mode = .Local
    }
  }
}

editor_ui :: proc(editor: ^Editor, scene: ^Scene) {
  if editor.selected_entity_index != nil && editor.selected_entity_index.? >= len(scene.entities) {
    editor.selected_entity_index = nil
  }

  if imgui.Begin("Objects") {
    if imgui.BeginTabBar("Objects Tab Bar") {
      if imgui.BeginTabItem("Entities") {
        for &entity, i in scene.entities {
          entity_label := fmt.ctprintf("%v##%v", cstring(raw_data(&entity.name)), entity.id)
          is_selected := editor.selected_entity_index != nil && editor.selected_entity_index.? == uint(i)
          if imgui.Selectable(entity_label, is_selected) do editor.selected_entity_index = uint(i)
        }
        imgui.EndTabItem()
      } else {
        editor.selected_entity_index = nil
      }
      if imgui.BeginTabItem("Light") {
        edit_directional_light(editor^, scene^, &scene.directional_light)
        imgui.EndTabItem()
      }
      imgui.EndTabBar()
    }
    imgui.End()
  }

  remove_selected := false

  if imgui.Begin("Inspector") {
    imgui_enum_select("Gizmo Operation", &editor.gizmo_operation)
    imgui_enum_select("Gizmo Mode", &editor.gizmo_mode)
    if editor.selected_entity_index != nil {
      entity := &scene.entities[editor.selected_entity_index.?]
      imgui.TextUnformatted(fmt.ctprintf("id: %v", entity.id))
      if imgui.Button("Delete") do remove_selected = true
      edit_transform(&entity.translation, &entity.rotation, &entity.scale)
      gizmo.manipulate(operation = editor.gizmo_operation,
                       mode = editor.gizmo_mode,
                       translation = &entity.translation,
                       rotation = &entity.rotation,
                       scale = &entity.scale,
                       mouse_position = cast(Vec2)get_normalized_cursor_position(),
                       mouse_pressed = glue.mouse_button_pressed(.Left),
                       view = camera_view(scene.camera),
                       projection = camera_projection(scene.camera))
    }
    imgui.End()
  }

  if remove_selected do scene_remove_entity(scene, editor.selected_entity_index.?)
}

editor_render :: proc(editor: ^Editor) {
  gizmo_vertices := gizmo.get_draw_data()
  if len(gizmo_vertices) == 0 do return

  gl.Disable(gl.DEPTH_TEST)
  defer gl.Enable(gl.DEPTH_TEST)

  glue.upload_dynamic_gl_buffer_data(&editor.gizmo_vb, slice.to_bytes(gizmo_vertices[:]))
  glue.use_shader(editor.gizmo_shader)
  glue.bind_vertex_array(editor.gizmo_va)
  gl.DrawArrays(gl.TRIANGLES,
                0,
                cast(i32)len(gizmo_vertices))
}

edit_transform :: proc(translation: ^Vec3, rotation: ^Quat, scale: ^Vec3) -> (value_changed := false) {
  value_changed ||= edit_translation(translation)
  value_changed ||= edit_rotation(rotation)
  value_changed ||= edit_scale(scale)
  return
}

edit_translation :: proc(translation: ^Vec3) -> (value_changed := false) {
  value_changed ||= imgui.DragFloat3("Translation", translation, v_speed = 0.01)
  return
}

edit_rotation :: proc(rotation: ^Quat) -> (value_changed := false) {
  rotation_v := Vec4{ rotation.x, rotation.y, rotation.z, rotation.w }
  if imgui.DragFloat4("Rotation", &rotation_v, v_speed = 0.01) {
    rotation^ = linalg.normalize(quaternion(x = rotation_v.x, y = rotation_v.y, z = rotation_v.z, w = rotation_v.w))
    value_changed = true
  }
  return
}

edit_scale :: proc(scale: ^Vec3) -> (value_changed := false) {
  value_changed ||= imgui.DragFloat3("Scale", scale, v_speed = 0.01)
  return
}

edit_directional_light :: proc(editor: Editor, scene: Scene, light: ^Directional_Light) {
  imgui.ColorEdit3("Ambient", &light.ambient)
  imgui.ColorEdit3("Diffuse", &light.diffuse)
  edit_translation(&light.translation)
  edit_rotation(&light.rotation)
  unused_scale := Vec3(1)
  gizmo.manipulate(operation = editor.gizmo_operation,
                   mode = editor.gizmo_mode,
                   translation = &light.translation,
                   rotation = &light.rotation,
                   scale = &unused_scale,
                   mouse_position = cast(Vec2)get_normalized_cursor_position(),
                   mouse_pressed = glue.mouse_button_pressed(.Left),
                   view = camera_view(scene.camera),
                   projection = camera_projection(scene.camera))
}

get_normalized_cursor_position :: proc() -> [2]f64 {
  pos := glue.cursor_position()
  window_size := cast([2]f64)glue.window_size()
  pos = pos / window_size * 2 - 1
  pos.y = -pos.y
  return pos
}
