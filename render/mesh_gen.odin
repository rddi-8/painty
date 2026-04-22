package render

import "core:fmt"
import "core:math"
import "../math2"
import "../colors"

UI_Mesh :: struct {
    vertices: []Vertex_Data,
    indices: []u32
}

UI_Mesh_Builder :: struct {
    vertices: [dynamic]Vertex_Data,
    indices: [dynamic]u32,
    vert_idx: map[Vertex_Data]u32
}

mb: ^UI_Mesh_Builder

mesh_append_quad :: proc(mesh: ^UI_Mesh_Builder, vertices: [4]Vertex_Data, shared: [4]bool = {true, true, true, true}) {
    vert_indices: [4]u32
    for i in 0..<4 {
        if shared[i] && vertices[i] in mesh.vert_idx {
            vert_indices[i] = mesh.vert_idx[vertices[i]]
        }
        else {
            append(&mesh.vertices, vertices[i])
            idx := len(mesh.vertices) - 1
            mesh.vert_idx[vertices[i]] = u32(idx)
            vert_indices[i] = u32(idx)
        }
    }

    indicesss := mesh.indices


    append(&mesh.indices, vert_indices[0])
    append(&mesh.indices, vert_indices[1])
    append(&mesh.indices, vert_indices[2])

    append(&mesh.indices, vert_indices[0])
    append(&mesh.indices, vert_indices[2])
    append(&mesh.indices, vert_indices[3])
}

mesh_builder_clear :: proc(mb: ^UI_Mesh_Builder) {
    clear(&mb.indices)
    clear(&mb.vertices)
    clear(&mb.vert_idx)
}

mesh_get :: proc(mesh_b: ^UI_Mesh_Builder) -> UI_Mesh {
    return {vertices = mesh_b.vertices[:], indices = mesh_b.indices[:]}
}

mesh_fill_uv :: proc(mesh: ^UI_Mesh, uv: [2]f32) {
    for &v in mesh.vertices {
        v.uv = uv
    }
}

gen_color_map :: proc(in_coord: [2]f32) -> [4]f32

@(private="file")
_default_color_map :: proc(in_coord: [2]f32) -> [4]f32 {
    return {in_coord.x, in_coord.y, 0, 1}
}

gen_circle :: proc(rad_segments: uint, sections: uint, color_map: gen_color_map = _default_color_map) -> UI_Mesh {
    segment_angle: f32 = f32(math.PI*2) / f32(rad_segments)
    section_width: f32 = 1.0 / f32(sections)

    if mb == nil {
        mb = new(UI_Mesh_Builder)
    }
    defer mesh_builder_clear(mb)
    // defer delete(mb.indices)
    // defer delete(mb.vertices)
    // defer delete(mb.vert_idx)
    // defer free(mb)

    for s in 1..<sections {
        for r in 0..<rad_segments {
            verts: [4]Vertex_Data
            verts[0].pos = math2.polar_to_cart(f32(r)*segment_angle, f32(s)*section_width)
            verts[1].pos = math2.polar_to_cart(f32(r+1)*segment_angle, f32(s)*section_width)
            verts[2].pos = math2.polar_to_cart(f32(r+1)*segment_angle, f32(s+1)*section_width)
            verts[3].pos = math2.polar_to_cart(f32(r)*segment_angle, f32(s+1)*section_width)
            for i in 0..<4 {
                verts[i].color = colors.to_col8(color_map(verts[i].pos))
            }
            verts[0].pos = verts[0].pos*0.5 + 0.5
            verts[1].pos = verts[1].pos*0.5 + 0.5
            verts[2].pos = verts[2].pos*0.5 + 0.5
            verts[3].pos = verts[3].pos*0.5 + 0.5
            mesh_append_quad(mb,verts)
        }
    }
    
    return mesh_get(mb)
}