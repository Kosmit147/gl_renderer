package gl_renderer

import gl "vendor:OpenGL"
import "glue"

import "core:mem"
import "core:math/linalg"

@(export, rodata) NvOptimusEnablement: u32 = 1
@(export, rodata) AmdPowerXpressRequestHighPerformance: u32 = 1

MODEL_UNIFORM :: glue.Uniform(Mat4) { location = 0 }
COLOR_UNIFORM :: glue.Uniform(Vec4) { location = 5 }

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

Camera_Buffer_Data :: struct {
  view: Mat4,
  projection: Mat4,
}

Light_Buffer_Data :: struct {
  light_ambient: Vec3,
  _: [4]byte,
  light_direction: Vec3,
  _: [4]byte,
  light_diffuse: Vec3,
  _: [4]byte,
}

Renderer :: struct {
  // TODO: Resize the framebuffer on window resize.
  main_framebuffer: glue.Framebuffer,
  color_texture: glue.Texture,
  depth_renderbuffer: glue.Renderbuffer,

  camera_buffer: glue.Gl_Buffer,
  light_buffer: glue.Gl_Buffer,

  postprocess_va: glue.Vertex_Array,
  clear_color: Vec4,
}

renderer_init :: proc(renderer: ^Renderer) -> (ok := false) {
  renderer.clear_color = BLACK

  gl.CullFace(gl.BACK)
  gl.FrontFace(gl.CCW)
  gl.Enable(gl.CULL_FACE)

  gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
  gl.Enable(gl.BLEND)

  gl.Enable(gl.DEPTH_TEST)

  renderer_init_framebuffer(renderer)
  defer if !ok do renderer_deinit_framebuffer(renderer)

  glue.create_static_gl_buffer(&renderer.camera_buffer, size_of(Camera_Buffer_Data))
  defer if !ok do glue.destroy_gl_buffer(&renderer.camera_buffer)
  glue.bind_uniform_buffer(renderer.camera_buffer, 0)

  glue.create_static_gl_buffer(&renderer.light_buffer, size_of(Light_Buffer_Data))
  defer if !ok do glue.destroy_gl_buffer(&renderer.light_buffer)
  glue.bind_shader_storage_buffer(renderer.light_buffer, 1)

  glue.create_vertex_array(&renderer.postprocess_va)
  defer if !ok do glue.destroy_vertex_array(&renderer.postprocess_va)

  ok = true
  return
}

renderer_deinit :: proc(renderer: ^Renderer) {
  glue.destroy_vertex_array(&renderer.postprocess_va)
  glue.destroy_gl_buffer(&renderer.camera_buffer)
  glue.destroy_gl_buffer(&renderer.light_buffer)
  renderer_deinit_framebuffer(renderer)
}

renderer_init_framebuffer :: proc(renderer: ^Renderer) {
  glue.create_framebuffer(&renderer.main_framebuffer)
  framebuffer_size := glue.framebuffer_size()
  color_texture_parameters := glue.Texture_Parameters {
    wrap_s = gl.CLAMP_TO_BORDER,
    wrap_t = gl.CLAMP_TO_BORDER,
    min_filter = gl.NEAREST,
    mag_filter = gl.NEAREST,
    border_color = MAGENTA, // Should never see this color.
  }

  renderer.color_texture = glue.create_texture(width = cast(u32)framebuffer_size.x,
                                               height = cast(u32)framebuffer_size.y,
                                               internal_format = gl.RGBA8,
                                               texture_parameters = color_texture_parameters)
  glue.create_renderbuffer(renderbuffer = &renderer.depth_renderbuffer,
                           width = framebuffer_size.x,
                           height = framebuffer_size.y,
                           format = gl.DEPTH24_STENCIL8)

  glue.attach_texture(renderer.main_framebuffer, renderer.color_texture, gl.COLOR_ATTACHMENT0)
  glue.attach_renderbuffer(renderer.main_framebuffer, renderer.depth_renderbuffer, gl.DEPTH_STENCIL_ATTACHMENT)
  ensure(glue.framebuffer_is_complete(renderer.main_framebuffer))

  glue.bind_framebuffer(renderer.main_framebuffer)
  gl.Viewport(0, 0, framebuffer_size.x, framebuffer_size.y)
}

renderer_deinit_framebuffer :: proc(renderer: ^Renderer) {
  glue.destroy_renderbuffer(&renderer.depth_renderbuffer)
  glue.destroy_texture(&renderer.color_texture)
  glue.destroy_framebuffer(&renderer.main_framebuffer)
}

renderer_render_scene :: proc(renderer: Renderer, scene: Scene, asset_cache: Asset_Cache) {
  glue.bind_framebuffer(renderer.main_framebuffer)
  gl.ClearColor(expand_values(renderer.clear_color))
  gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT | gl.STENCIL_BUFFER_BIT)

  camera_buffer_data := Camera_Buffer_Data {
    view = camera_view(scene.camera),
    projection = camera_projection(scene.camera),
  }

  glue.upload_static_gl_buffer_data(renderer.camera_buffer, mem.ptr_to_bytes(&camera_buffer_data))

  light_buffer_data := Light_Buffer_Data {
    light_ambient = scene.directional_light.ambient,
    light_direction = linalg.matrix3_from_quaternion(scene.directional_light.rotation) * WORLD_FORWARD,
    light_diffuse = scene.directional_light.diffuse,
  }

  glue.upload_static_gl_buffer_data(renderer.light_buffer, mem.ptr_to_bytes(&light_buffer_data))

  gl.Enable(gl.CULL_FACE)
  gl.Enable(gl.DEPTH_TEST)
  gl.Enable(gl.BLEND)

  for entity in scene.entities do renderer_render_entity(entity, asset_cache)

  gl.Disable(gl.CULL_FACE)
  gl.Disable(gl.DEPTH_TEST)
  gl.Disable(gl.BLEND)
  glue.bind_default_framebuffer()
  gl.ClearColor(expand_values(renderer.clear_color))
  gl.Clear(gl.COLOR_BUFFER_BIT)
  glue.bind_vertex_array(renderer.postprocess_va)
  glue.use_shader(asset_cache_get_shader_builtin(asset_cache, POSTPROCESS_SHADER))
  glue.bind_texture(renderer.color_texture, 0)
  gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)
}

renderer_render_entity :: proc(entity: Entity, asset_cache: Asset_Cache) -> (ok := false) {
  material := asset_cache_get_material(asset_cache, entity.material) or_else asset_cache_get_material_builtin(asset_cache, ERROR_MATERIAL)
  shader := asset_cache_get_shader(asset_cache, material.shader) or_else asset_cache_get_shader_builtin(asset_cache, ERROR_SHADER)
  texture_0 := asset_cache_get_texture(asset_cache, material.texture_0) or_else asset_cache_get_texture_builtin(asset_cache, ERROR_TEXTURE)
  mesh := asset_cache_get_mesh(asset_cache, entity.mesh) or_else asset_cache_get_mesh_builtin(asset_cache, ERROR_MESH)

  glue.use_shader(shader)
  glue.bind_texture(texture_0, 0)

  translation := linalg.matrix4_translate(entity.translation)
  rotation := linalg.matrix4_from_quaternion(entity.rotation)
  scale := linalg.matrix4_scale(entity.scale)
  model := translation * rotation * scale
  glue.set_uniform(shader, MODEL_UNIFORM, model)

  glue.bind_mesh(mesh)
  gl.DrawElements(gl.TRIANGLES,
                  i32(mesh.vertex_count),
                  mesh.index_type,
                  rawptr(uintptr(mesh.index_data_offset)))

  ok = true
  return
}
