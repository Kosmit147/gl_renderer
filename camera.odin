package gl_renderer

import "glue"

import "core:math"
import "core:math/linalg"

Camera :: glue.Camera

@(require_results)
camera_view :: proc(camera: Camera) -> Mat4 {
  camera_vectors := glue.camera_vectors(camera)
  return linalg.matrix4_look_at_from_fru(camera.position,
                                         camera_vectors.forward,
                                         camera_vectors.right,
                                         camera_vectors.up)
}

@(require_results)
camera_projection :: proc(camera: Camera) -> Mat4 {
  return linalg.matrix4_perspective(fovy = math.to_radians(f32(45)),
                                    aspect = glue.window_aspect_ratio(),
                                    near = 0.1,
                                    far = 1000)
}
