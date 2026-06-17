const std = @import("std");

const io = @import("io.zig");
const math = @import("math.zig");
const prim = @import("geometry_primitives.zig");

const add = math.add;
const sub = math.sub;
const mul = math.mul;
const Vec3 = math.Vec3;
const Vec3c = math.Vec3c;
const Allocator = std.mem.Allocator;

pub const Mesh = struct {
    vrt: []Vec3c = &.{},
    ind: []u32 = &.{},
    bvh: BoundingVolumeHierarchy = .{},
};

pub const BoundingVolumeHierarchy = struct {
    pub const Node = struct {
        bbox: BoxCenterExtent,
        offset: u32, // primitive offset if leaf, first child offset if interior
        count: u32, // 0 if interior, positive otherwise
    };
    nodes: []Node = &.{},
    indices: []u32 = &.{},
};

const BoxCenterExtent = struct {
    center: Vec3c,
    extent: Vec3c, // this is a "half extent"
};

const Box = struct {
    min: Vec3c = @splat(std.math.floatMax(f32)),
    max: Vec3c = @splat(-std.math.floatMax(f32)),
    fn grow(self: *Box, point: Vec3c) void {
        inline for (0..3) |dim| {
            if (point[dim] < self.min[dim]) self.min[dim] = point[dim];
            if (point[dim] > self.max[dim]) self.max[dim] = point[dim];
        }
    }
    fn getCenter(self: Box) Vec3 {
        return .{
            0.5 * (self.max[0] + self.min[0]),
            0.5 * (self.max[1] + self.min[1]),
            0.5 * (self.max[2] + self.min[2]),
        };
    }
    fn getExtent(self: Box) Vec3 {
        return .{
            self.max[0] - self.min[0],
            self.max[1] - self.min[1],
            self.max[2] - self.min[2],
        };
    }
};

fn toCenterExtent(box: Box) BoxCenterExtent {
    var boxCenterExtent: BoxCenterExtent = undefined;
    inline for (0..3) |di| {
        boxCenterExtent.center[di] = 0.5 * (box.max[di] + box.min[di]);
        boxCenterExtent.extent[di] = 0.5 * (box.max[di] - box.min[di]);
    }
    return boxCenterExtent;
}

fn findBoundingVolume(mesh: *Mesh, tri_indices: []u32) Box {
    var box = Box{};
    for (tri_indices) |ti| {
        const index_offset = 3 * ti;
        for (0..3) |vi| {
            box.grow(mesh.vrt[mesh.ind[index_offset + vi]]);
        }
    }
    return box;
}

fn findSurfaceArea(box: Box) f32 {
    const dx = box.max[0] - box.min[0];
    const dy = box.max[1] - box.min[1];
    const dz = box.max[2] - box.min[2];
    return 2.0 * ((dy * dz) + (dx * dz) + (dx * dy));
}

fn costSAH(nL: u32, nR: u32, aL: f32, aR: f32) f32 {
    return @as(f32, @floatFromInt(nL)) * aL + @as(f32, @floatFromInt(nR)) * aR;
}

fn select(min: u32, max: u32, dim: usize, pos: f32, centroids: []Vec3c, indices: []u32) u32 {
    var lo_max: u32 = min;
    var hi_min: u32 = max;
    while (lo_max < hi_min) {
        if (centroids[indices[lo_max]][dim] > pos) {
            hi_min -= 1;
            std.mem.swap(u32, &indices[lo_max], &indices[hi_min]);
        } else {
            lo_max += 1;
        }
    }
    // Note that lo_max should always be equal to hi_min at this point. So the area above really
    // returns a "split coorindate" and the list section sorted at the boundary.
    std.debug.assert(lo_max == hi_min);
    return hi_min;
}

const bvh_max_depth = 32; // BVH will admit 2^max_depth partitions

pub fn buildBVH(
    mesh: *Mesh,
    allocator: std.mem.Allocator,
    comptime max_leaf_nodes: usize,
    comptime num_bins: usize,
) !BVHStats {
    const ntri: usize = mesh.ind.len / 3;
    const max_nodes: usize = 2 * ntri - 1;
    std.debug.assert(mesh.ind.len % 3 == 0);
    std.debug.assert(max_nodes < std.math.maxInt(u32)); // note this ensures ntri is also in bounds

    var stats: BVHStats = .{};
    stats.mesh_ntri = ntri;

    mesh.bvh.nodes = try allocator.alloc(BoundingVolumeHierarchy.Node, max_nodes);
    mesh.bvh.indices = try allocator.alloc(u32, ntri);

    var centroids: []Vec3c = try allocator.alloc(Vec3c, ntri);
    defer allocator.free(centroids);
    for (0..ntri) |ti| {
        const v0 = mesh.vrt[mesh.ind[ti * 3 + 0]];
        const v1 = mesh.vrt[mesh.ind[ti * 3 + 1]];
        const v2 = mesh.vrt[mesh.ind[ti * 3 + 2]];
        inline for (0..3) |dim|
            centroids[ti][dim] = (v0[dim] + v1[dim] + v2[dim]) / 3.0;
    }

    for (0..ntri) |ti| mesh.bvh.indices[ti] = @intCast(ti);
    mesh.bvh.nodes[0].bbox = toCenterExtent(findBoundingVolume(mesh, mesh.bvh.indices));
    mesh.bvh.nodes[0].count = @intCast(ntri);
    mesh.bvh.nodes[0].offset = 0;

    const BVHBuildNode = struct {
        node_index: u32,
        depth: u32,
    };

    var build_stack: [bvh_max_depth + 1]BVHBuildNode = undefined;
    build_stack[0] = .{ .node_index = 0, .depth = 0 };
    var build_stack_head: u32 = 1;

    var next_node: u32 = 1;
    while (build_stack_head > 0) {
        std.debug.assert(build_stack_head - 1 <= bvh_max_depth);

        const stack_node: BVHBuildNode = build_stack[build_stack_head - 1];
        const node: *BoundingVolumeHierarchy.Node = &mesh.bvh.nodes[stack_node.node_index];
        build_stack_head -= 1;

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

        if ((node.count <= max_leaf_nodes) or (stack_node.depth + 1 > bvh_max_depth)) continue;

        const min: u32 = node.offset;
        const max: u32 = node.offset + node.count;

        var split_dim: usize = 0;
        var split_pos: f32 = node.bbox.center[split_dim];
        var split_countL: u32 = 0;
        var split_countR: u32 = 0;
        var split_boxL: Box = .{};
        var split_boxR: Box = .{};

        const Bin = struct {
            box: Box = .{},
            ntri: u32 = 0,
        };

        const max_bin_flt: f32 = comptime @floatFromInt(num_bins - 1);
        var min_cost: f32 = std.math.floatMax(f32);
        inline for (0..3) |di| {
            const interval: f32 = (2.0 * node.bbox.extent[di]) / @as(f32, @floatFromInt(num_bins));
            const corner: f32 = node.bbox.center[di] - node.bbox.extent[di];

            // find bin contents
            var bins: [num_bins]Bin = @splat(Bin{});
            {
                for (min..max) |ii| {
                    const ti: u32 = mesh.bvh.indices[ii];
                    const bi: usize = @intFromFloat(
                        @min(@max((centroids[ti][di] - corner) / interval, 0.0), max_bin_flt),
                    );
                    bins[bi].ntri += 1;
                    for (0..3) |vi| {
                        bins[bi].box.grow(mesh.vrt[mesh.ind[3 * ti + vi]]);
                    }
                }
            }

            // find split contents
            var countsL: [num_bins - 1]u32 = @splat(0);
            var countsR: [num_bins - 1]u32 = @splat(0);
            var boxesL: [num_bins - 1]Box = @splat(Box{});
            var boxesR: [num_bins - 1]Box = @splat(Box{});
            {
                var countL: u32 = 0;
                var countR: u32 = 0;
                var boxL: Box = .{};
                var boxR: Box = .{};
                for (0..(num_bins - 1)) |fsi| { // forward split iterator
                    if (bins[fsi].ntri > 0) {
                        countL += bins[fsi].ntri;
                        boxL.grow(bins[fsi].box.min);
                        boxL.grow(bins[fsi].box.max);
                    }
                    countsL[fsi] = countL;
                    boxesL[fsi] = boxL;
                    const rsi: usize = (num_bins - 2) - fsi; // reverse split iterator
                    if (bins[rsi + 1].ntri > 0) {
                        countR += bins[rsi + 1].ntri;
                        boxR.grow(bins[rsi + 1].box.min);
                        boxR.grow(bins[rsi + 1].box.max);
                    }
                    countsR[rsi] = countR;
                    boxesR[rsi] = boxR;
                }
            }

            // find minimum cost split
            for (0..(num_bins - 1)) |si| {
                const cost = costSAH(
                    countsL[si],
                    countsR[si],
                    findSurfaceArea(boxesL[si]),
                    findSurfaceArea(boxesR[si]),
                );
                if (cost < min_cost) {
                    split_dim = di;
                    split_pos = corner + interval * @as(f32, @floatFromInt(si + 1));
                    split_countL = countsL[si];
                    split_countR = countsR[si];
                    split_boxL = boxesL[si];
                    split_boxR = boxesR[si];
                    min_cost = cost;
                }
            }
        }

        _ = select(min, max, split_dim, split_pos, centroids, mesh.bvh.indices);

        // NOTE: We must always ensure each newly created leaf has at least one triangle, otherwise
        // the node structure doesn't work since we assume all interior nodes have count 0.
        if ((split_countL > 0) and (split_countR > 0)) {
            node.count = 0; // set interior
            node.offset = next_node;

            std.debug.assert(next_node < mesh.bvh.nodes.len);
            mesh.bvh.nodes[next_node].bbox = toCenterExtent(split_boxL);
            mesh.bvh.nodes[next_node].count = split_countL;
            mesh.bvh.nodes[next_node].offset = min;
            build_stack[build_stack_head] = .{ .node_index = next_node, .depth = stack_node.depth + 1 };
            build_stack_head += 1;
            next_node += 1;

            std.debug.assert(next_node < mesh.bvh.nodes.len);
            mesh.bvh.nodes[next_node].bbox = toCenterExtent(split_boxR);
            mesh.bvh.nodes[next_node].count = split_countR;
            mesh.bvh.nodes[next_node].offset = min + split_countL;
            build_stack[build_stack_head] = .{ .node_index = next_node, .depth = stack_node.depth + 1 };
            build_stack_head += 1;
            next_node += 1;
        }
    }

    stats.nodes_total = next_node;
    stats.depth_average /= @as(f32, @floatFromInt(stats.nodes_leaf));
    stats.tris_average /= @as(f32, @floatFromInt(stats.nodes_leaf));

    return stats;
}

test "BVH --- splits planes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator: std.mem.Allocator = arena.allocator();

    var vrt = [_]Vec3c{ // initialized such that the first swap yields two x-normal planes
        .{ 0.0, 0.0, 0.25 }, .{ 1.0, 0.0, 0.25 }, .{ 0.0, 1.0, 0.25 }, .{ 1.0, 1.0, 0.25 },
        .{ 0.0, 0.0, 0.75 }, .{ 1.0, 0.0, 0.75 }, .{ 0.0, 1.0, 0.75 }, .{ 1.0, 1.0, 0.75 },
    };
    var ind = [_]u32{
        0, 1, 2, 1, 3, 2, 4, 5, 6, 5, 7, 6,
    };

    const vol = struct {
        fn f(box: BoxCenterExtent) f32 {
            return (2.0 * box.extent[0]) * (2.0 * box.extent[1]) * (2.0 * box.extent[2]);
        }
    }.f;

    for (0..3) |di| {
        for (&vrt) |*vertex| {
            std.mem.swap(f32, &vertex[di], &vertex[(di + 2) % 3]);
        }

        var mesh = Mesh{ .vrt = &vrt, .ind = &ind };
        const stats = try buildBVH(&mesh, allocator, 2, 4);

        try std.testing.expectEqual(3, stats.nodes_total);
        try std.testing.expectApproxEqAbs(0.5, vol(mesh.bvh.nodes[0].bbox), 4.0 * math.eps);
        try std.testing.expectApproxEqAbs(0.0, vol(mesh.bvh.nodes[1].bbox), 4.0 * math.eps);
        try std.testing.expectApproxEqAbs(0.0, vol(mesh.bvh.nodes[2].bbox), 4.0 * math.eps);
    }
}

pub fn intersectRayMesh(ray: prim.Ray, mesh: Mesh) ?prim.IntersectResult {
    var result: prim.IntersectResult = .{ .dist = std.math.floatMax(f32), .norm = undefined };

    const RayMeshStackNode = struct {
        indx: u32,
        dist: f32,
    };

    var traversal_stack: [bvh_max_depth + 1]RayMeshStackNode = undefined;

    if (prim.intersectRayBoxDist(
        .{ .d = ray.d, .o = sub(ray.o, math.makeVec3(mesh.bvh.nodes[0].bbox.center)) },
        .{ .size = math.makeVec3(mesh.bvh.nodes[0].bbox.extent) },
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
                .{ .d = ray.d, .o = sub(ray.o, math.makeVec3(child0.bbox.center)) },
                .{ .size = child0.bbox.extent },
            ) orelse std.math.floatMax(f32);
            const dist1: f32 = prim.intersectRayBoxDist(
                .{ .d = ray.d, .o = sub(ray.o, math.makeVec3(child1.bbox.center)) },
                .{ .size = child1.bbox.extent },
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
                    math.makeVec3(mesh.vrt[mesh.ind[3 * ti + 0]]),
                    math.makeVec3(mesh.vrt[mesh.ind[3 * ti + 1]]),
                    math.makeVec3(mesh.vrt[mesh.ind[3 * ti + 2]]),
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

test "BVH --- intersects" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator: std.mem.Allocator = arena.allocator();

    var vertices = [_]Vec3c{
        .{ 0.0, 0.0, 0.0 }, .{ 1.0, 0.0, 0.0 }, .{ 1.0, 1.0, 0.0 }, .{ 0.0, 1.0, 0.0 },
        .{ 0.0, 0.0, 1.0 }, .{ 1.0, 0.0, 1.0 }, .{ 1.0, 1.0, 1.0 }, .{ 0.0, 1.0, 1.0 },
    };
    var indices = [_]u32{
        0, 1, 2, 0, 2, 3, 4, 6, 5, 4, 7, 6,
        0, 5, 1, 0, 4, 5, 3, 2, 6, 3, 6, 7,
        0, 3, 7, 0, 7, 4, 1, 5, 6, 1, 6, 2,
    };

    var mesh: Mesh = .{ .vrt = &vertices, .ind = &indices };
    _ = try buildBVH(&mesh, allocator, 4, 16);

    const ray: prim.Ray = .{ .o = .{ -2.0, 0.2, 0.2 }, .d = .{ 1.0, 0.0, 0.0 } };

    if (intersectRayMesh(ray, mesh)) |result| {
        try std.testing.expectEqual(2.0, result.dist);
        try std.testing.expectEqual(@as(Vec3, .{ -1.0, 0.0, 0.0 }), result.norm);
    } else {
        try std.testing.expect(false);
    }
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
        Vec3c,
        u32,
        struct {
            pub fn hash(_: @This(), v: Vec3c) u64 {
                return std.hash.Wyhash.hash(0, std.mem.asBytes(&v));
            }
            pub fn eql(_: @This(), a: Vec3c, b: Vec3c) bool {
                return std.mem.eql(u8, std.mem.asBytes(&a), std.mem.asBytes(&b));
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
    result.vrt = try alloc_main.alloc(Vec3c, next_index);
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

    const v0: Vec3c = .{ 0.0, 0.0, 0.0 };
    const v1: Vec3c = .{ 1.0, 0.0, 0.0 };
    const v2: Vec3c = .{ 1.0, 1.0, 0.0 };
    const v3: Vec3c = .{ 0.0, 1.0, 0.0 };
    const v4: Vec3c = .{ 0.0, 0.0, 1.0 };
    const v5: Vec3c = .{ 1.0, 0.0, 1.0 };
    const v6: Vec3c = .{ 1.0, 1.0, 1.0 };
    const v7: Vec3c = .{ 0.0, 1.0, 1.0 };

    var vertices = [_]Vec3c{
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

pub fn printBVHStats(stats: BVHStats, stdio: std.Io) !void {
    var stdout_buffer: [1 << 10]u8 = undefined;
    var stdout_w = std.Io.File.stdout().writer(stdio, &stdout_buffer);
    const stdout = &stdout_w.interface;
    defer stdout.flush() catch {};

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
