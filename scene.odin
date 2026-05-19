package gl_renderer

Scene :: struct {
	camera: Camera,
	entities: [dynamic]^Entity,
}

scene_destroy :: proc(scene: Scene) {
	delete(scene.entities)
}

Entity :: struct {
	translation: Vec3,
	rotation: Quat,
	scale: Vec3,
	mesh: ^Mesh,
	material: ^Material,
}
