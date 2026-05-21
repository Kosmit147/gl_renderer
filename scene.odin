package gl_renderer

import "core:slice"
import "core:fmt"
import "core:math"
import "core:math/linalg"

Scene :: struct {
	camera: Camera,
	entities: [dynamic]Entity,
	next_entity_id: uint,

	directional_light: Directional_Light,
}

scene_init :: proc(scene: ^Scene) {
	scene.entities = make([dynamic]Entity, context.allocator)
	scene.directional_light = {
		translation = 0,
		rotation = linalg.quaternion_angle_axis(math.to_radians_f32(-60), Vec3{ 1, 0, 0 }),
		ambient = 0.1,
		diffuse = 0.7,
	}
}

scene_destroy :: proc(scene: Scene) {
	delete(scene.entities)
}

scene_add_entity :: proc(scene: ^Scene, name: string) -> ^Entity {
	new_entity: Entity
	new_entity.id = scene.next_entity_id
	scene.next_entity_id += 1
	fmt.bprintf(new_entity.name[:], "%v%v", name, rune(0))
	slice.last_ptr(new_entity.name[:])^ = 0
	new_entity.rotation = 1
	new_entity.scale = 1
	append(&scene.entities, new_entity)
	return slice.last_ptr(scene.entities[:])
}

scene_remove_entity :: proc(scene: ^Scene, index: uint) {
	unordered_remove(&scene.entities, index)
}

Entity :: struct {
	id: uint,
	name: [64]byte, // cstring
	translation: Vec3,
	rotation: Quat,
	scale: Vec3,
	mesh: Mesh_Id,
	material: Material_Id,
}
