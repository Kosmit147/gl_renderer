package gl_renderer

import "core:slice"
import "core:fmt"

Scene :: struct {
	camera: Camera,
	entities: [dynamic]Entity,
	next_entity_id: uint,
}

scene_init :: proc(scene: ^Scene) {
	scene.entities = make([dynamic]Entity, context.allocator)
}

scene_destroy :: proc(scene: Scene) {
	delete(scene.entities)
}

scene_add_entity :: proc(scene: ^Scene, name: string) -> ^Entity {
	new_entity: Entity
	new_entity.id = scene.next_entity_id
	fmt.bprintf(new_entity.name[:], "%v%v", name, rune(0))
	scene.next_entity_id += 1
	append(&scene.entities, new_entity)
	return slice.last_ptr(scene.entities[:])
}

scene_remove_entity :: proc(scene: ^Scene, index: uint) {
	unordered_remove(&scene.entities, index)
}

Entity :: struct {
	id: uint,
	name: [64]byte,
	translation: Vec3,
	rotation: Quat,
	scale: Vec3,
	mesh: ^Mesh,
	material: ^Material,
}
