const std = @import("std");

const io = @import("io.zig");
const math = @import("math.zig");
const prim = @import("geometry_primitives.zig");

const add = math.add;
const sub = math.sub;
const mul = math.mul;
const Vec3 = math.Vec3;
const Allocator = std.mem.Allocator;

var stdout_writer = std.fs.File.stdout().writer(&.{});
var stderr_writer = std.fs.File.stderr().writer(&.{});
const stdout = &stdout_writer.interface;
const stderr = &stderr_writer.interface;

pub const Mesh = struct {
    vrt: []Vec3 = &.{},
    ind: []u32 = &.{},
    bvh: BoundingVolumeHierarchy = .{},
};

const bvh_max_depth = 32; // BVH will admit 2^max_depth partitions

pub const BoundingVolumeHierarchy = struct {
    pub const Node = struct {
        center: [3]f32,
        extent: [3]f32,
        offset: u32, // primitive offset if leaf, first child offset if interior
        count: u32, // 0 if interior, positive otherwise
    };
    nodes: []Node = &.{},
    indices: []u32 = &.{},
};

fn findNodeBBOX(mesh: *Mesh, tri_indices: []u32, node: *BoundingVolumeHierarchy.Node) void {
    var min: Vec3 = math.set3(std.math.floatMax(f32));
    var max: Vec3 = math.set3(-std.math.floatMax(f32));

    for (tri_indices) |tri_index| {
        const vertices: [3]Vec3 = .{
            mesh.vrt[mesh.ind[3 * tri_index + 0]],
            mesh.vrt[mesh.ind[3 * tri_index + 1]],
            mesh.vrt[mesh.ind[3 * tri_index + 2]],
        };
        for (vertices) |vertex| {
            for (0..3) |dim| {
                if (vertex[dim] < min[dim]) min[dim] = vertex[dim];
                if (vertex[dim] > max[dim]) max[dim] = vertex[dim];
            }
        }
    }

    const center: Vec3 = mul(add(max, min), 0.5);
    const extent: Vec3 = mul(sub(max, min), 0.5);

    node.center = .{ center[0], center[1], center[2] };
    node.extent = .{ extent[0], extent[1], extent[2] };
}

pub fn buildBVH(mesh: *Mesh, allocator: std.mem.Allocator) !BVHStats {
    const ntri: usize = mesh.ind.len / 3;
    const max_nodes: usize = 2 * ntri - 1;
    std.debug.assert(mesh.ind.len % 3 == 0);
    std.debug.assert(max_nodes < std.math.maxInt(u32)); // note this ensures ntri is also in bounds

    var stats: BVHStats = .{};
    stats.mesh_ntri = ntri;

    mesh.bvh.nodes = try allocator.alloc(BoundingVolumeHierarchy.Node, max_nodes);
    mesh.bvh.indices = try allocator.alloc(u32, ntri);
    for (0..ntri) |ti| mesh.bvh.indices[ti] = @intCast(ti);

    var centroids: []Vec3 = try allocator.alloc(Vec3, ntri);
    defer allocator.free(centroids);
    for (0..ntri) |ti| {
        const v0: Vec3 = mesh.vrt[mesh.ind[ti * 3 + 0]];
        const v1: Vec3 = mesh.vrt[mesh.ind[ti * 3 + 1]];
        const v2: Vec3 = mesh.vrt[mesh.ind[ti * 3 + 2]];
        centroids[ti] = mul(add(add(v0, v1), v2), 1.0 / 3.0);
    }

    findNodeBBOX(mesh, mesh.bvh.indices, &mesh.bvh.nodes[0]);
    mesh.bvh.nodes[0].count = @intCast(ntri);
    mesh.bvh.nodes[0].offset = 0;

    const BVHBuildNode = struct {
        node_index: u32,
        depth: u32,
    };

    var node_stack: [bvh_max_depth + 1]BVHBuildNode = undefined;
    node_stack[0] = .{ .node_index = 0, .depth = 0 };
    var node_stack_head: u32 = 1;

    var next_node: u32 = 1;
    while (node_stack_head > 0) {
        std.debug.assert(node_stack_head - 1 <= bvh_max_depth);

        const stack_node: BVHBuildNode = node_stack[node_stack_head - 1];
        const node: *BoundingVolumeHierarchy.Node = &mesh.bvh.nodes[stack_node.node_index];
        node_stack_head -= 1;

        defer { // each iteration "retires" one node, it is logged here
            if (node.count == 0) {
                stats.nodes_interior += 1;
            } else {
                stats.nodes_leaf += 1;
                stats.depth_average += @as(f32, @floatFromInt(stack_node.depth));
                stats.depth_min = @min(stats.depth_min, stack_node.depth);
                stats.depth_max = @max(stats.depth_max, stack_node.depth);
                stats.tris_min = @min(stats.tris_min, node.count);
                stats.tris_max = @max(stats.tris_max, node.count);
                stats.tris_average += @as(f32, @floatFromInt(node.count));
            }
        }

        if ((node.count <= 4) or (stack_node.depth + 1 > bvh_max_depth)) continue;

        const split_dim: usize = blk: {
            var max_extent: f32 = -std.math.floatMax(f32);
            var max_dim: usize = 0;
            for (0..3) |dim| {
                if (node.extent[dim] > max_extent) {
                    max_extent = node.extent[dim];
                    max_dim = dim;
                }
            }
            break :blk max_dim;
        };

        const min: u32 = node.offset;
        const max: u32 = node.offset + node.count;

        var lo_max: u32 = min;
        var hi_min: u32 = max;
        while (lo_max < hi_min) {
            if (centroids[mesh.bvh.indices[lo_max]][split_dim] > node.center[split_dim]) {
                hi_min -= 1;
                std.mem.swap(u32, &mesh.bvh.indices[lo_max], &mesh.bvh.indices[hi_min]);
            } else {
                lo_max += 1;
            }
        }
        std.debug.assert(lo_max == hi_min);
        // Note that lo_max should always be equal to hi_min at this point. So the area above really
        // returns a "split coorindate" and the list section sorted at the boundary.

        // NOTE: We must always ensure each newly created leaf has at least one triangle, otherwise
        // the node structure doesn't work since we assume all interior nodes have count 0.
        if ((lo_max - min > 0) and (max - hi_min > 0)) {
            node.count = 0; // set interior
            node.offset = next_node;

            findNodeBBOX(mesh, mesh.bvh.indices[min..lo_max], &mesh.bvh.nodes[next_node]);
            std.debug.assert(next_node < mesh.bvh.nodes.len);
            mesh.bvh.nodes[next_node].count = lo_max - min;
            mesh.bvh.nodes[next_node].offset = min;
            node_stack[node_stack_head] = .{ .node_index = next_node, .depth = stack_node.depth + 1 };
            node_stack_head += 1;
            next_node += 1;

            findNodeBBOX(mesh, mesh.bvh.indices[hi_min..max], &mesh.bvh.nodes[next_node]);
            std.debug.assert(next_node < mesh.bvh.nodes.len);
            mesh.bvh.nodes[next_node].count = max - hi_min;
            mesh.bvh.nodes[next_node].offset = hi_min;
            node_stack[node_stack_head] = .{ .node_index = next_node, .depth = stack_node.depth + 1 };
            node_stack_head += 1;
            next_node += 1;
        }
    }

    stats.nodes_total = next_node;
    stats.depth_average /= @as(f32, @floatFromInt(stats.nodes_leaf));
    stats.tris_average /= @as(f32, @floatFromInt(stats.nodes_leaf));

    return stats;
}

pub fn intersectRayMesh(ray: prim.Ray, mesh: Mesh) ?prim.IntersectResult {
    var result: prim.IntersectResult = .{ .dist = std.math.floatMax(f32), .norm = undefined };

    const RayMeshStackNode = struct {
        indx: u32,
        dist: f32,
    };

    var traversal_stack: [bvh_max_depth + 1]RayMeshStackNode = undefined;

    const root_center: Vec3 = math.makeVec3(mesh.bvh.nodes[0].center);
    const root_extent: Vec3 = math.makeVec3(mesh.bvh.nodes[0].extent);
    if (prim.intersectRayBoxDist(
        .{ .d = ray.d, .o = sub(ray.o, root_center) },
        .{ .size = root_extent },
    )) |root_dist| {
        traversal_stack[0].indx = 0;
        traversal_stack[0].dist = root_dist;
    } else {
        return null;
    }
    var traversal_stack_head: usize = 1;

    while (traversal_stack_head > 0) {
        std.debug.assert(traversal_stack_head - 1 <= bvh_max_depth);

        const stack_node: RayMeshStackNode = traversal_stack[traversal_stack_head - 1];
        traversal_stack_head -= 1;
        const node: *BoundingVolumeHierarchy.Node = &mesh.bvh.nodes[stack_node.indx];

        if (result.dist <= stack_node.dist) continue;

        if (node.count == 0) {
            const child0: *BoundingVolumeHierarchy.Node = &mesh.bvh.nodes[node.offset];
            const child1: *BoundingVolumeHierarchy.Node = &mesh.bvh.nodes[node.offset + 1];

            const dist0: f32 = prim.intersectRayBoxDist(
                .{ .d = ray.d, .o = sub(ray.o, math.makeVec3(child0.center)) },
                .{ .size = math.makeVec3(child0.extent) },
            ) orelse std.math.floatMax(f32);
            const dist1: f32 = prim.intersectRayBoxDist(
                .{ .d = ray.d, .o = sub(ray.o, math.makeVec3(child1.center)) },
                .{ .size = math.makeVec3(child1.extent) },
            ) orelse std.math.floatMax(f32);

            var new_node0: RayMeshStackNode = .{ .indx = node.offset, .dist = dist0 };
            var new_node1: RayMeshStackNode = .{ .indx = node.offset + 1, .dist = dist1 };

            if (new_node0.dist < new_node1.dist) {
                std.mem.swap(RayMeshStackNode, &new_node0, &new_node1);
            }

            if (new_node0.dist < std.math.floatMax(f32)) {
                traversal_stack[traversal_stack_head] = new_node0;
                traversal_stack_head += 1;
            }

            if (new_node1.dist < std.math.floatMax(f32)) {
                traversal_stack[traversal_stack_head] = new_node1;
                traversal_stack_head += 1;
            }
        } else {
            for (node.offset..(node.offset + node.count)) |ii| {
                const ti: u32 = mesh.bvh.indices[ii];
                const triangle: prim.Triangle = .{ .vertices = .{
                    mesh.vrt[mesh.ind[3 * ti + 0]],
                    mesh.vrt[mesh.ind[3 * ti + 1]],
                    mesh.vrt[mesh.ind[3 * ti + 2]],
                } };
                if (prim.intersectRayTriangle(ray, triangle)) |intersect| {
                    if (intersect.dist < result.dist) {
                        result = intersect;
                    }
                }
            }
        }
    }

    return if (result.dist == std.math.floatMax(f32)) null else result;
}

/// Mesh de-duplication adapted from Arseny Kapoulkine's meshoptimizer. It's just slower and less
/// correct, written for my own educational purposes.
///
/// A poor approach may be to loop over all vertices, dump them in a hash table, and iterate over
/// the hash table for the new vertex list. This would result in a random (in so far as the hash is
/// random) vertex order without pruning unused vertices. Instead, this implementation finds unique
/// (bitwise) vertices by looping over primitives. This has a couple nice properties:
/// - The vertex order resulting from the de-duplication process roughly corresponds to primitive
///   order. If mesh primitives are ordered in a roughly spatially local way, vertices will be
///   ordered in the same manner.
/// - Unused vertices are automatically pruned.
pub fn deDupeMesh(mesh: Mesh, alloc_main: Allocator, alloc_work: Allocator) !Mesh {
    std.debug.assert(mesh.ind.len % 3 == 0);
    const ntri: usize = mesh.ind.len / 3;

    var map: std.HashMapUnmanaged(
        Vec3,
        u32,
        struct {
            pub fn hash(_: @This(), v: Vec3) u64 {
                const data: [3]f32 = .{ v[0], v[1], v[2] };
                return std.hash.Wyhash.hash(0, std.mem.asBytes(&data));
            }
            pub fn eql(_: @This(), a: Vec3, b: Vec3) bool {
                const data_a: [3]f32 = .{ a[0], a[1], a[2] };
                const data_b: [3]f32 = .{ b[0], b[1], b[2] };
                return std.mem.eql(u8, std.mem.asBytes(&data_a), std.mem.asBytes(&data_b));
            }
        },
        std.hash_map.default_max_load_percentage,
    ) = .{};

    defer map.deinit(alloc_work);

    // Table mapping each vertex in the old list to its position in the new list.
    var remap_table: []u32 = try alloc_work.alloc(u32, mesh.vrt.len);
    defer alloc_work.free(remap_table);
    @memset(remap_table, std.math.maxInt(std.meta.Elem(@TypeOf(remap_table))));

    var next_index: u32 = 0;
    for (0..ntri) |ti| {
        for (0..3) |vi| {
            const vertex_index = mesh.ind[3 * ti + vi];
            const key = mesh.vrt[vertex_index];
            if (map.get(key)) |val| {
                remap_table[vertex_index] = val;
            } else {
                remap_table[vertex_index] = next_index;
                try map.put(alloc_work, key, next_index);
                next_index += 1;
            }
        }
    }

    var result: Mesh = .{};
    result.vrt = try alloc_main.alloc(Vec3, next_index);
    result.ind = try alloc_main.alloc(u32, mesh.ind.len);

    for (0..mesh.vrt.len) |vi| {
        const dst: u32 = remap_table[vi];
        std.debug.assert(dst < next_index);
        if (dst != std.math.maxInt(@TypeOf(remap_table[0]))) {
            result.vrt[dst] = mesh.vrt[vi];
        }
    }

    for (0..mesh.ind.len) |ii| {
        result.ind[ii] = remap_table[mesh.ind[ii]];
    }

    return result;
}

test "deDupeMesh --- cube" {
    var arena_main = std.heap.ArenaAllocator.init(std.testing.allocator);
    var arena_work = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_main.deinit();
    defer arena_work.deinit();

    const v0: Vec3 = .{ 0.0, 0.0, 0.0 };
    const v1: Vec3 = .{ 1.0, 0.0, 0.0 };
    const v2: Vec3 = .{ 1.0, 1.0, 0.0 };
    const v3: Vec3 = .{ 0.0, 1.0, 0.0 };
    const v4: Vec3 = .{ 0.0, 0.0, 1.0 };
    const v5: Vec3 = .{ 1.0, 0.0, 1.0 };
    const v6: Vec3 = .{ 1.0, 1.0, 1.0 };
    const v7: Vec3 = .{ 0.0, 1.0, 1.0 };

    var vertices = [_]Vec3{
        v0, v1, v2, v0, v2, v3, v4, v6, v5, v4, v7, v6, v0, v5, v1, v0, v4, v5,
        v3, v2, v6, v3, v6, v7, v0, v3, v7, v0, v7, v4, v1, v5, v6, v1, v6, v2,
    };
    var indices = [_]u32{
        0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15, 16, 17,
        18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35,
    };
    const mesh: Mesh = .{ .vrt = &vertices, .ind = &indices };

    const result = try deDupeMesh(mesh, arena_main.allocator(), arena_work.allocator());
    try std.testing.expectEqual(@as(usize, 8), result.vrt.len);
}

pub const BVHStats = struct {
    mesh_ntri: usize = 0,
    depth_min: u32 = std.math.maxInt(u32),
    depth_max: u32 = 0,
    depth_average: f32 = 0.0,
    nodes_total: u32 = 0,
    nodes_interior: u32 = 0,
    nodes_leaf: u32 = 0,
    tris_min: u32 = std.math.maxInt(u32),
    tris_max: u32 = 0,
    tris_average: f32 = 0.0,
};

pub fn printBVHStats(stats: BVHStats) !void {
    try stdout.print("  mesh triangles:    {f}\n", .{io.fmtComma(stats.mesh_ntri)});
    try stdout.print("  average depth:     {d:.1}\n", .{stats.depth_average});
    try stdout.print("  min depth:         {}\n", .{stats.depth_min});
    try stdout.print("  max depth:         {}\n", .{stats.depth_max});
    try stdout.print("  total nodes:       {f}\n", .{io.fmtComma(stats.nodes_total)});
    try stdout.print("  interior nodes:    {f}\n", .{io.fmtComma(stats.nodes_interior)});
    try stdout.print("  leaf nodes:        {f}\n", .{io.fmtComma(stats.nodes_leaf)});
    try stdout.print("  min triangles:     {f}\n", .{io.fmtComma(stats.tris_min)});
    try stdout.print("  max triangles:     {f}\n", .{io.fmtComma(stats.tris_max)});
    try stdout.print("  average triangles: {d:.2}\n", .{stats.tris_average});
}

test "BVH --- builds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator: std.mem.Allocator = arena.allocator();

    var vertices = [_]Vec3{
        .{ 0.0, 0.0, 0.0 },
        .{ 1.0, 0.0, 0.0 },
        .{ 1.0, 1.0, 0.0 },
        .{ 0.0, 1.0, 0.0 },
        .{ 0.0, 0.0, 1.0 },
        .{ 1.0, 0.0, 1.0 },
        .{ 1.0, 1.0, 1.0 },
        .{ 0.0, 1.0, 1.0 },
    };
    var indices = [_]u32{
        0, 1, 2,
        0, 2, 3,
        4, 6, 5,
        4, 7, 6,
        0, 5, 1,
        0, 4, 5,
        3, 2, 6,
        3, 6, 7,
        0, 3, 7,
        0, 7, 4,
        1, 5, 6,
        1, 6, 2,
    };

    var mesh: Mesh = .{};
    mesh.vrt = &vertices;
    mesh.ind = &indices;

    _ = try buildBVH(&mesh, allocator);

    const ray: prim.Ray = .{ .o = .{ -2.0, 0.2, 0.2 }, .d = .{ 1.0, 0.0, 0.0 } };
    if (intersectRayMesh(ray, mesh)) |result| {
        try std.testing.expectEqual(2, result.dist);
        try std.testing.expectEqual(@as(Vec3, .{ -1.0, 0.0, 0.0 }), result.norm);
    } else {
        try std.testing.expect(false);
    }
}
