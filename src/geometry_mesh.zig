const std = @import("std");

const io = @import("io.zig");
const math = @import("math.zig");
const prim = @import("geometry_primitives.zig");

const add = math.add;
const sub = math.sub;
const mul = math.mul;
const Vec3 = math.Vec3;

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

pub const BVHStats = struct {
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

pub fn buildBVH(mesh: *Mesh, allocator: std.mem.Allocator) !BVHStats {
    const ntri: usize = mesh.ind.len / 3;
    std.debug.assert(mesh.ind.len % 3 == 0);
    std.debug.assert(ntri < std.math.maxInt(u32));

    var stats: BVHStats = .{};

    mesh.bvh.nodes = try allocator.alloc(BoundingVolumeHierarchy.Node, 2 * ntri - 1);
    mesh.bvh.indices = try allocator.alloc(u32, ntri);
    for (0..ntri) |ti| {
        mesh.bvh.indices[ti] = @intCast(ti);
    }

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
        index: u32,
        depth: u32,
    };

    var node_stack: [bvh_max_depth + 1]BVHBuildNode = undefined;
    node_stack[0] = .{ .index = 0, .depth = 0 };
    var node_stack_head: u32 = 1;

    var next_node: u32 = 1;
    while (node_stack_head > 0) {
        std.debug.assert(node_stack_head - 1 <= bvh_max_depth);

        const stack_node: BVHBuildNode = node_stack[node_stack_head - 1];
        const node: *BoundingVolumeHierarchy.Node = &mesh.bvh.nodes[stack_node.index];
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

        if ((node.count <= 1) or (stack_node.depth + 1 > bvh_max_depth)) continue;

        var split_dim: usize = 0;
        {
            var max_extent: f32 = -std.math.floatMax(f32);
            for (0..3) |dim| {
                if (node.extent[dim] > max_extent) {
                    max_extent = node.extent[dim];
                    split_dim = dim;
                }
            }
        }

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

        // NOTE: We must always ensure each newly created leaf has at least one triangle, otherwise
        // the node structure doesn't work since we assume all interior nodes have count 0.
        if ((lo_max - min > 0) and (max - hi_min > 0)) {
            node.count = 0; // set interior
            node.offset = next_node;

            findNodeBBOX(mesh, mesh.bvh.indices[min..lo_max], &mesh.bvh.nodes[next_node]);
            std.debug.assert(next_node < mesh.bvh.nodes.len);
            mesh.bvh.nodes[next_node].count = lo_max - min;
            mesh.bvh.nodes[next_node].offset = min;
            node_stack[node_stack_head] = .{ .index = next_node, .depth = stack_node.depth + 1 };
            node_stack_head += 1;
            next_node += 1;

            findNodeBBOX(mesh, mesh.bvh.indices[hi_min..max], &mesh.bvh.nodes[next_node]);
            std.debug.assert(next_node < mesh.bvh.nodes.len);
            mesh.bvh.nodes[next_node].count = max - hi_min;
            mesh.bvh.nodes[next_node].offset = hi_min;
            node_stack[node_stack_head] = .{ .index = next_node, .depth = stack_node.depth + 1 };
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
