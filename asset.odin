package gl_renderer

import "glue"
import gl "vendor:OpenGL"

import "core:slice"

Material :: struct {
	shader: Shader_Id,
	texture_0: Texture_Id,
}

Shader  :: glue.Shader
Texture :: glue.Texture
Mesh    :: glue.Mesh

// Ids 0 - 1000 are reserved for builtin assets. 0 is an invalid id.
Material_Id :: distinct uint
Shader_Id   :: distinct uint
Mesh_Id     :: distinct uint
Texture_Id  :: distinct uint

ERROR_MATERIAL :: 0
LIT_MATERIAL   :: 1
UNLIT_MATERIAL :: 2

ERROR_SHADER :: 0
LIT_SHADER   :: 1
UNLIT_SHADER :: 2

ERROR_MESH   :: 0
CUBE_MESH    :: 1
SPHERE_MESH  :: 2
CAPSULE_MESH :: 3

ERROR_TEXTURE       :: 0
WHITE_TEXTURE       :: 1
BLACK_TEXTURE       :: 2
TRANSPARENT_TEXTURE :: 3

Asset_Cache :: struct {
	materials: map[Material_Id]Material,
	shaders: map[Shader_Id]Shader,
	meshes: map[Mesh_Id]Mesh,
	textures: map[Texture_Id]Texture,

	next_material_id: Material_Id,
	next_shader_id: Shader_Id,
	next_mesh_id: Mesh_Id,
	next_texture_id: Texture_Id,
}

asset_cache_init :: proc(cache: ^Asset_Cache) -> (ok := false) {
	cache.materials = make(map[Material_Id]Material, context.allocator)
	defer if !ok {
		asset_cache_destroy_materials(cache.materials)
		delete(cache.materials)
	}
	cache.shaders = make(map[Shader_Id]Shader, context.allocator)
	defer if !ok {
		asset_cache_destroy_shaders(cache.shaders)
		delete(cache.shaders)
	}
	cache.meshes = make(map[Mesh_Id]Mesh, context.allocator)
	defer if !ok {
		asset_cache_destroy_meshes(cache.meshes)
		delete(cache.meshes)
	}
	cache.textures = make(map[Texture_Id]Texture, context.allocator)
	defer if !ok {
		asset_cache_destroy_textures(cache.textures)
		delete(cache.textures)
	}

	{
		cache.materials[ERROR_MATERIAL] = Material {
			shader = ERROR_SHADER,
			texture_0 = ERROR_TEXTURE,
		}
		cache.materials[LIT_MATERIAL] = Material {
			shader = LIT_SHADER,
			texture_0 = WHITE_TEXTURE,
		}
		cache.materials[UNLIT_MATERIAL] = Material {
			shader = UNLIT_SHADER,
			texture_0 = WHITE_TEXTURE,
		}
	}

	{
		error_shader := glue.create_shader(#load("shaders/error.vert"), #load("shaders/error.frag")) or_return
		lit_shader := glue.create_shader(#load("shaders/lit.vert"), #load("shaders/lit.frag")) or_return
		unlit_shader := glue.create_shader(#load("shaders/unlit.vert"), #load("shaders/unlit.frag")) or_return
		cache.shaders[ERROR_SHADER] = error_shader
		cache.shaders[LIT_SHADER] = lit_shader
		cache.shaders[UNLIT_SHADER] = unlit_shader
	}

	{
		// TODO: Error mesh should be a 3D "ERROR" text.
		error_mesh := glue.create_mesh(vertices = slice.to_bytes(cube_vertices[:]),
									   vertex_stride = size_of(Vertex_3D),
									   vertex_format = vertex_3d_format[:],
									   indices = slice.to_bytes(cube_indices[:]),
									   index_type = glue.gl_index(Cube_Index))
		cube_mesh := glue.create_mesh(vertices = slice.to_bytes(cube_vertices[:]),
									  vertex_stride = size_of(Vertex_3D),
									  vertex_format = vertex_3d_format[:],
									  indices = slice.to_bytes(cube_indices[:]),
									  index_type = glue.gl_index(Cube_Index))
		sphere_mesh := glue.create_mesh_from_obj("models/sphere.obj") or_return
		capsule_mesh := glue.create_mesh_from_obj("models/capsule.obj") or_return
		cache.meshes[ERROR_MESH] = error_mesh
		cache.meshes[CUBE_MESH] = cube_mesh
		cache.meshes[SPHERE_MESH] = sphere_mesh
		cache.meshes[CAPSULE_MESH] = capsule_mesh
	}

	{
		texture_parameters := glue.Texture_Parameters {
			wrap_s = gl.REPEAT,
			wrap_t = gl.REPEAT,
			min_filter = gl.NEAREST,
			mag_filter = gl.NEAREST,
			internal_format = gl.RGBA8,
		}

		error_texture_pixels := []u8{ 255, 0, 255, 255 }
		white_texture_pixels := []u8{ 255, 255, 255, 255 }
		black_texture_pixels := []u8{ 0, 0, 0, 255 }
		transparent_texture_pixels := []u8{ 255, 255, 255, 0 }
		cache.textures[ERROR_TEXTURE] = glue.create_texture(1, 1, 4, error_texture_pixels, texture_parameters)
		cache.textures[WHITE_TEXTURE] = glue.create_texture(1, 1, 4, white_texture_pixels, texture_parameters)
		cache.textures[BLACK_TEXTURE] = glue.create_texture(1, 1, 4, black_texture_pixels, texture_parameters)
		cache.textures[TRANSPARENT_TEXTURE] = glue.create_texture(1, 1,
																  4,
																  transparent_texture_pixels,
																  texture_parameters)
	}

	cache.next_material_id = 1001
	cache.next_shader_id = 1001
	cache.next_mesh_id = 1001
	cache.next_texture_id = 1001

	ok = true
	return
}

asset_cache_deinit :: proc(cache: Asset_Cache) {
	asset_cache_destroy_materials(cache.materials)
	asset_cache_destroy_shaders(cache.shaders)
	asset_cache_destroy_meshes(cache.meshes)
	asset_cache_destroy_textures(cache.textures)
	delete(cache.materials)
	delete(cache.shaders)
	delete(cache.meshes)
	delete(cache.textures)
}

asset_cache_get_material :: proc(cache: Asset_Cache, id: Material_Id) -> (Material, bool) {
	return cache.materials[id]
}

asset_cache_get_shader :: proc(cache: Asset_Cache, id: Shader_Id) -> (Shader, bool) {
	return cache.shaders[id]
}

asset_cache_get_mesh :: proc(cache: Asset_Cache, id: Mesh_Id) -> (Mesh, bool) {
	return cache.meshes[id]
}

asset_cache_get_texture :: proc(cache: Asset_Cache, id: Texture_Id) -> (Texture, bool) {
	return cache.textures[id]
}

asset_cache_get_material_builtin :: proc(cache: Asset_Cache, id: Material_Id) -> Material {
	return cache.materials[id]
}

asset_cache_get_shader_builtin :: proc(cache: Asset_Cache, id: Shader_Id) -> Shader {
	return cache.shaders[id]
}

asset_cache_get_mesh_builtin :: proc(cache: Asset_Cache, id: Mesh_Id) -> Mesh {
	return cache.meshes[id]
}

asset_cache_get_texture_builtin :: proc(cache: Asset_Cache, id: Texture_Id) -> Texture {
	return cache.textures[id]
}

asset_cache_add_material :: proc(cache: ^Asset_Cache, material: Material) -> (id: Material_Id) {
	id = cache.next_material_id
	cache.next_material_id += 1
	cache.materials[id] = material
	return
}

asset_cache_add_shader :: proc(cache: ^Asset_Cache, shader: Shader) -> (id: Shader_Id) {
	id = cache.next_shader_id
	cache.next_shader_id += 1
	cache.shaders[id] = shader
	return
}

asset_cache_add_mesh :: proc(cache: ^Asset_Cache, mesh: Mesh) -> (id: Mesh_Id) {
	id = cache.next_mesh_id
	cache.next_mesh_id += 1
	cache.meshes[id] = mesh
	return
}

asset_cache_add_texture :: proc(cache: ^Asset_Cache, texture: Texture) -> (id: Texture_Id) {
	id = cache.next_texture_id
	cache.next_texture_id += 1
	cache.textures[id] = texture
	return
}

asset_cache_destroy_materials :: proc(materials: map[Material_Id]Material) {}

asset_cache_destroy_shaders :: proc(shaders: map[Shader_Id]Shader) {
	for _, shader in shaders do glue.destroy_shader(shader)
}

asset_cache_destroy_meshes :: proc(meshes: map[Mesh_Id]Mesh) {
	for _, &mesh in meshes do glue.destroy_mesh(&mesh)
}

asset_cache_destroy_textures :: proc(textures: map[Texture_Id]Texture) {
	for _, &texture in textures do glue.destroy_texture(&texture)
}

@(rodata)
cube_vertices := [24]Vertex_3D{
	// Front wall.
	{ position = { 0, 0, 1 }, normal = {  0,  0,  1 }, uv = { 0, 1 } },
	{ position = { 1, 0, 1 }, normal = {  0,  0,  1 }, uv = { 1, 1 } },
	{ position = { 1, 1, 1 }, normal = {  0,  0,  1 }, uv = { 1, 0 } },
	{ position = { 0, 1, 1 }, normal = {  0,  0,  1 }, uv = { 0, 0 } },

	// Back wall.
	{ position = { 0, 0, 0 }, normal = {  0,  0, -1 }, uv = { 0, 1 } },
	{ position = { 0, 1, 0 }, normal = {  0,  0, -1 }, uv = { 0, 0 } },
	{ position = { 1, 1, 0 }, normal = {  0,  0, -1 }, uv = { 1, 0 } },
	{ position = { 1, 0, 0 }, normal = {  0,  0, -1 }, uv = { 1, 1 } },

	// Left wall.
	{ position = { 0, 1, 1 }, normal = { -1,  0,  0 }, uv = { 1, 0 } },
	{ position = { 0, 1, 0 }, normal = { -1,  0,  0 }, uv = { 0, 0 } },
	{ position = { 0, 0, 0 }, normal = { -1,  0,  0 }, uv = { 0, 1 } },
	{ position = { 0, 0, 1 }, normal = { -1,  0,  0 }, uv = { 1, 1 } },

	// Right wall.
	{ position = { 1, 1, 1 }, normal = {  1,  0,  0 }, uv = { 0, 0 } },
	{ position = { 1, 0, 1 }, normal = {  1,  0,  0 }, uv = { 0, 1 } },
	{ position = { 1, 0, 0 }, normal = {  1,  0,  0 }, uv = { 1, 1 } },
	{ position = { 1, 1, 0 }, normal = {  1,  0,  0 }, uv = { 1, 0 } },

	// Bottom wall.
	{ position = { 0, 0, 0 }, normal = {  0, -1,  0 }, uv = { 0, 0 } },
	{ position = { 1, 0, 0 }, normal = {  0, -1,  0 }, uv = { 1, 0 } },
	{ position = { 1, 0, 1 }, normal = {  0, -1,  0 }, uv = { 1, 1 } },
	{ position = { 0, 0, 1 }, normal = {  0, -1,  0 }, uv = { 0, 1 } },

	// Top wall.
	{ position = { 0, 1, 0 }, normal = {  0,  1,  0 }, uv = { 0, 0 } },
	{ position = { 0, 1, 1 }, normal = {  0,  1,  0 }, uv = { 0, 1 } },
	{ position = { 1, 1, 1 }, normal = {  0,  1,  0 }, uv = { 1, 1 } },
	{ position = { 1, 1, 0 }, normal = {  0,  1,  0 }, uv = { 1, 0 } },
}

// @(rodata)
// cube_vertices := [24]Vertex_3D{
// 	// Front wall.
// 	{ position = { -0.5, -0.5, 0.5 }, normal = {  0,  0,  1 }, uv = { 0, 1 } },
// 	{ position = { 0.5, -0.5, 0.5 }, normal = {  0,  0,  1 }, uv = { 1, 1 } },
// 	{ position = { 0.5, 0.5, 0.5 }, normal = {  0,  0,  1 }, uv = { 1, 0 } },
// 	{ position = { -0.5, 0.5, 0.5 }, normal = {  0,  0,  1 }, uv = { 0, 0 } },
//
// 	// Back wall.
// 	{ position = { -0.5, -0.5, -0.5 }, normal = {  0,  0, -1 }, uv = { 0, 1 } },
// 	{ position = { -0.5, 0.5, -0.5 }, normal = {  0,  0, -1 }, uv = { 0, 0 } },
// 	{ position = { 0.5, 0.5, -0.5 }, normal = {  0,  0, -1 }, uv = { 1, 0 } },
// 	{ position = { 0.5, -0.5, -0.5 }, normal = {  0,  0, -1 }, uv = { 1, 1 } },
//
// 	// Left wall.
// 	{ position = { -0.5, 0.5, 0.5 }, normal = { -1,  0,  0 }, uv = { 1, 0 } },
// 	{ position = { -0.5, 0.5, -0.5 }, normal = { -1,  0,  0 }, uv = { 0, 0 } },
// 	{ position = { -0.5, -0.5, -0.5 }, normal = { -1,  0,  0 }, uv = { 0, 1 } },
// 	{ position = { -0.5, -0.5, 0.5 }, normal = { -1,  0,  0 }, uv = { 1, 1 } },
//
// 	// Right wall.
// 	{ position = { 0.5, 0.5, 0.5 }, normal = {  1,  0,  0 }, uv = { 0, 0 } },
// 	{ position = { 0.5, -0.5, 0.5 }, normal = {  1,  0,  0 }, uv = { 0, 1 } },
// 	{ position = { 0.5, -0.5, -0.5 }, normal = {  1,  0,  0 }, uv = { 1, 1 } },
// 	{ position = { 0.5, 0.5, -0.5 }, normal = {  1,  0,  0 }, uv = { 1, 0 } },
//
// 	// Bottom wall.
// 	{ position = { -0.5, -0.5, -0.5 }, normal = {  0, -1,  0 }, uv = { 0, 0 } },
// 	{ position = { 0.5, -0.5, -0.5 }, normal = {  0, -1,  0 }, uv = { 1, 0 } },
// 	{ position = { 0.5, -0.5, 0.5 }, normal = {  0, -1,  0 }, uv = { 1, 1 } },
// 	{ position = { -0.5, -0.5, 0.5 }, normal = {  0, -1,  0 }, uv = { 0, 1 } },
//
// 	// Top wall.
// 	{ position = { -0.5, 0.5, -0.5 }, normal = {  0,  1,  0 }, uv = { 0, 0 } },
// 	{ position = { -0.5, 0.5, 0.5 }, normal = {  0,  1,  0 }, uv = { 0, 1 } },
// 	{ position = { 0.5, 0.5, 0.5 }, normal = {  0,  1,  0 }, uv = { 1, 1 } },
// 	{ position = { 0.5, 0.5, -0.5 }, normal = {  0,  1,  0 }, uv = { 1, 0 } },
// }

Cube_Index :: u8

@(rodata)
cube_indices := [36]Cube_Index{
	// Front wall.
	0, 1, 2, 0, 2, 3,

	// Back wall.
	4, 5, 6, 4, 6, 7,

	// Left wall.
	8, 9, 10, 8, 10, 11,

	// Right wall.
	12, 13, 14, 12, 14, 15,

	// Bottom wall.
	16, 17, 18, 16, 18, 19,

	// Top wall.
	20, 21, 22, 20, 22, 23,
}
