package gl_renderer

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
