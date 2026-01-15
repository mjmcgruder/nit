const std = @import("std");

const m = @import("math.zig");

pub const Ray = struct {
    o: m.Vec3,
    d: m.Vec3,
};

pub const Sphere = struct {
    r: f32 = 1.0,
};

pub const Box = struct {
    size: m.Vec3 = .{ .data = .{ 1.0, 1.0, 1.0 } },
};

pub const AxisAlignedBoundingBox = struct {
    center: m.Vec3 = .{},
    size: m.Vec3 = .{}, // note this is max dist from center in each direction (half of net length)
};

pub const Triangle = struct {
    vertices: [3]m.Vec3,
};

pub const Mesh = struct {
    vrt: std.ArrayList(m.Vec3) = .empty, // TODO: switch to slices b/c arena
    ind: std.ArrayList(u32) = .empty,
    bvh: BoundingVolumeHierarchy = .{},
};

pub const BoundingVolumeHierarchyNode = struct {
    center: [3]f32,
    extent: [3]f32,
    offset: u32, // primitive offset if leaf, first child offset if interior
    count: u32, // 0 if interior, positive otherwise
};

pub const BoundingVolumeHierarchy = struct {
    nodes: []BoundingVolumeHierarchyNode = &.{},
    indices: []u32 = &.{},
};

pub fn setBoundingBox(mesh: *Mesh, tri_indices: []u32, node: *BoundingVolumeHierarchyNode) void {
    var min: m.Vec3 = m.set3(std.math.floatMax(f32));
    var max: m.Vec3 = m.set3(-std.math.floatMax(f32));

    for (tri_indices) |tri_index| {
        const vertices: [3]m.Vec3 = .{
            mesh.vrt.items[mesh.ind.items[3 * tri_index + 0]],
            mesh.vrt.items[mesh.ind.items[3 * tri_index + 1]],
            mesh.vrt.items[mesh.ind.items[3 * tri_index + 2]],
        };
        for (vertices) |vertex| {
            for (0..3) |dim| {
                if (vertex.data[dim] < min.data[dim]) min.data[dim] = vertex.data[dim];
                if (vertex.data[dim] > max.data[dim]) max.data[dim] = vertex.data[dim];
            }
        }
    }

    const center: m.Vec3 = m.mul(m.add(max, min), 0.5);
    const extent: m.Vec3 = m.mul(m.sub(max, min), 0.5);

    node.center = .{ center.data[0], center.data[1], center.data[2] };
    node.extent = .{ extent.data[0], extent.data[1], extent.data[2] };
}

pub fn buildBVH(mesh: *Mesh, allocator: std.mem.Allocator) !void {
    const ntri: usize = mesh.ind.items.len / 3;
    std.debug.assert(mesh.ind.items.len % 3 == 0);
    std.debug.assert(ntri < std.math.maxInt(u32));

    mesh.bvh.nodes = try allocator.alloc(BoundingVolumeHierarchyNode, 2 * (2 * ntri - 1));
    mesh.bvh.indices = try allocator.alloc(u32, ntri);
    for (0..ntri) |ti| {
        mesh.bvh.indices[ti] = @intCast(ti);
    }

    var centroids: []m.Vec3 = try allocator.alloc(m.Vec3, ntri);
    for (0..ntri) |ti| {
        const v0: m.Vec3 = mesh.vrt.items[mesh.ind.items[ti * 3 + 0]];
        const v1: m.Vec3 = mesh.vrt.items[mesh.ind.items[ti * 3 + 1]];
        const v2: m.Vec3 = mesh.vrt.items[mesh.ind.items[ti * 3 + 2]];
        centroids[ti] = m.mul(m.add(m.add(v0, v1), v2), 1.0 / 3.0);
    }

    setBoundingBox(mesh, mesh.bvh.indices, &mesh.bvh.nodes[0]);
    mesh.bvh.nodes[0].count = @intCast(ntri);
    mesh.bvh.nodes[0].offset = 0;

    const max_depth: usize = 1 << 5;
    var node_stack: [max_depth]u32 = undefined;
    node_stack[0] = 0;
    var node_stack_head: u32 = 1;

    var next_node: u32 = 1;
    while (node_stack_head > 0) {
        const node: *BoundingVolumeHierarchyNode = &mesh.bvh.nodes[node_stack[node_stack_head - 1]];
        node_stack_head -= 1;

        // TODO: we need to limit (and track through the stack) depth in case of insanity
        if (node.count <= 1) continue;

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
            if (centroids[mesh.bvh.indices[lo_max]].data[split_dim] > node.center[split_dim]) {
                hi_min -= 1;
                std.mem.swap(u32, &mesh.bvh.indices[lo_max], &mesh.bvh.indices[hi_min]);
            } else {
                lo_max += 1;
            }
        }

        if ((lo_max - min > 0) and (max - hi_min > 0)) {
            node.count = 0; // set interior
            node.offset = next_node;

            setBoundingBox(mesh, mesh.bvh.indices[min..lo_max], &mesh.bvh.nodes[next_node]);
            mesh.bvh.nodes[next_node].count = lo_max - min;
            mesh.bvh.nodes[next_node].offset = min;
            node_stack[node_stack_head] = next_node;
            node_stack_head += 1;
            next_node += 1;

            setBoundingBox(mesh, mesh.bvh.indices[hi_min..max], &mesh.bvh.nodes[next_node]);
            mesh.bvh.nodes[next_node].count = max - hi_min;
            mesh.bvh.nodes[next_node].offset = hi_min;
            node_stack[node_stack_head] = next_node;
            node_stack_head += 1;
            next_node += 1;
        }
    }
}

const IntersectResultRayGeom = struct {
    dist: f32 = 0.0,
    norm: m.Vec3 = .{},
};

fn intersectRaySphere(ray: Ray, sphere: Sphere) ?IntersectResultRayGeom {
    const roh: f32 = m.dot(ray.o, ray.d); // ray origin to half-chord dist
    const woc: m.Vec3 = m.sub(ray.o, m.mul(roh, ray.d)); // world origin to chord vec
    const hsq: f32 = sphere.r * sphere.r - m.dot(woc, woc);
    // closest ray point is outside sphere
    if (hsq < 0.0) return null;
    const seh: f32 = @sqrt(hsq); // sphere edge to half-chord distance
    const tn: f32 = -roh - seh; // near
    const tf: f32 = -roh + seh; // far
    // sphere is behind ray origin
    if (tf < 0.0) return null;
    // ray origin is inside sphere
    if (tn < 0.0) {
        return IntersectResultRayGeom{
            .dist = tf,
            .norm = m.mul(m.mul(-1.0, m.add(ray.o, m.mul(ray.d, tf))), m.sdiv(1.0, sphere.r)),
        };
    }
    // sphere is ahead of ray origin
    return IntersectResultRayGeom{
        .dist = tn, // note normalization below is simple since the vector has magnitude radius
        .norm = m.mul(m.add(ray.o, m.mul(ray.d, tn)), m.sdiv(1.0, sphere.r)),
    };
}

fn intersectRayBox(ray: Ray, box: Box) ?IntersectResultRayGeom {
    const ird: m.Vec3 = m.div(1.0, ray.d); // invserse ray direction
    const dt0: m.Vec3 = m.mul(ird, ray.o); // parametric distance to axis-orthogonal plane at 0
    const bdc: m.Vec3 = m.mul(m.abs(ird), box.size); // box distance correction
    const atn: m.Vec3 = m.sub(m.mul(-1.0, dt0), bdc);
    const atf: m.Vec3 = m.add(m.mul(-1.0, dt0), bdc);
    const tn: f32 = @max(atn.data[0], atn.data[1], atn.data[2]);
    const tf: f32 = @min(atf.data[0], atf.data[1], atf.data[2]);
    // miss or box behind ray origin
    if (tn > tf or tf < 0.0) return null;
    // hit with box ahead of ray origin
    if (tn > 0.0) {
        return .{
            .dist = tn,
            .norm = m.mul(m.step(tn, atn), m.mul(-1.0, m.sign(ray.d))), // TODO: normalization occasionally slightly incorrect due to FP
        };
    }
    // hit with box ahead of ray origin
    else {
        return .{
            .dist = tf,
            .norm = m.mul(m.step(atf, tf), m.mul(-1.0, m.sign(ray.d))),
        };
    }
}

fn intersectRayTriangle(ray: Ray, tri: Triangle) ?IntersectResultRayGeom {
    const v0v1: m.Vec3 = m.sub(tri.vertices[1], tri.vertices[0]);
    const v0v2: m.Vec3 = m.sub(tri.vertices[2], tri.vertices[0]);
    const v0ro: m.Vec3 = m.sub(ray.o, tri.vertices[0]);
    const n: m.Vec3 = m.cross(v0v1, v0v2);
    const q: m.Vec3 = m.cross(v0ro, ray.d);
    const d: f32 = 1.0 / m.dot(ray.d, n);
    const u: f32 = d * m.dot(m.mul(-1.0, q), v0v2);
    const v: f32 = d * m.dot(q, v0v1);
    const t: f32 = d * m.dot(m.mul(-1.0, n), v0ro);
    if (u < 0.0 or v < 0.0 or (u + v) > 1.0 or t < 0.0) return null;
    const nn: m.Vec3 = m.normalize(n);
    return .{ .dist = t, .norm = if (m.dot(n, ray.d) < 0.0) nn else m.mul(-1.0, nn) };
}

fn intersectRayMesh(ray: Ray, mesh: Mesh) ?IntersectResultRayGeom {
    var result: IntersectResultRayGeom = .{ .dist = std.math.floatMax(f32), .norm = undefined };

    const RayMeshStackNode = struct {
        indx: u32,
        dist: f32,
    };

    var traversal_stack: [1 << 7]RayMeshStackNode = undefined; // TODO: set max depth properly

    const root_center: m.Vec3 = m.makeVec3(mesh.bvh.nodes[0].center);
    const root_extent: m.Vec3 = m.makeVec3(mesh.bvh.nodes[0].extent);
    if (intersectRayBox(
        .{ .d = ray.d, .o = m.sub(ray.o, root_center) },
        .{ .size = root_extent },
    )) |root_intersect| {
        traversal_stack[0].indx = 0;
        traversal_stack[0].dist = root_intersect.dist;
    } else {
        return null;
    }
    var traversal_stack_head: usize = 1;

    while (traversal_stack_head > 0) {
        const node_stack: RayMeshStackNode = traversal_stack[traversal_stack_head - 1];
        traversal_stack_head -= 1;
        const node: *BoundingVolumeHierarchyNode = &mesh.bvh.nodes[node_stack.indx];

        if (result.dist <= node_stack.dist) continue;

        if (node.count == 0) {
            const child0: *BoundingVolumeHierarchyNode = &mesh.bvh.nodes[node.offset];
            const child1: *BoundingVolumeHierarchyNode = &mesh.bvh.nodes[node.offset + 1];

            const intersect0: IntersectResultRayGeom = intersectRayBox(
                .{ .d = ray.d, .o = m.sub(ray.o, m.makeVec3(child0.center)) },
                .{ .size = m.makeVec3(child0.extent) },
            ) orelse .{ .dist = std.math.floatMax(f32) };
            const intersect1: IntersectResultRayGeom = intersectRayBox(
                .{ .d = ray.d, .o = m.sub(ray.o, m.makeVec3(child1.center)) },
                .{ .size = m.makeVec3(child1.extent) },
            ) orelse .{ .dist = std.math.floatMax(f32) };

            var new_node0: RayMeshStackNode = .{ .indx = node.offset, .dist = intersect0.dist };
            var new_node1: RayMeshStackNode = .{ .indx = node.offset + 1, .dist = intersect1.dist };

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
                const triangle: Triangle = .{ .vertices = .{
                    mesh.vrt.items[mesh.ind.items[3 * ti + 0]],
                    mesh.vrt.items[mesh.ind.items[3 * ti + 1]],
                    mesh.vrt.items[mesh.ind.items[3 * ti + 2]],
                } };
                if (intersectRayTriangle(ray, triangle)) |intersect| {
                    if (intersect.dist < result.dist) {
                        result = intersect;
                    }
                }
            }
        }
    }

    return if (result.dist == std.math.floatMax(f32)) null else result;
}

pub const GeometryType = union(enum) {
    sphere: Sphere,
    box: Box,
    mesh: Mesh,
};

pub const Material = enum { diffuse, specular };

pub const Object = struct {
    geom: GeometryType = undefined,
    trfm: m.Mat4 = .{ .data = .{
        .{ 1.0, 0.0, 0.0, 0.0 },
        .{ 0.0, 1.0, 0.0, 0.0 },
        .{ 0.0, 0.0, 1.0, 0.0 },
        .{ 0.0, 0.0, 0.0, 1.0 },
    } },
    refl: m.Vec3 = m.Vec3{ .data = .{ 1.0, 1.0, 1.0 } },
    emit: m.Vec3 = m.Vec3{ .data = .{ 0.0, 0.0, 0.0 } },
    mtrl: Material = Material.diffuse,
};

pub const IntersectResult = struct {
    geom: IntersectResultRayGeom = .{},
    refl: m.Vec3 = .{},
    emit: m.Vec3 = .{},
    mtrl: Material = Material.diffuse,
};

pub fn intersectRayObject(wray: Ray, obj: Object) ?IntersectResult {
    const itfm: m.Mat4 = m.invertTransform(obj.trfm);

    const mrayd = m.toVec3(m.matvec4(itfm, m.toHomogeneousDir(wray.d)));
    const mray: Ray = .{
        .o = m.toVec3(m.matvec4(itfm, m.toHomogeneousPos(wray.o))),
        .d = m.normalize(mrayd),
    };

    var intersect_geom: ?IntersectResultRayGeom = switch (obj.geom) {
        .sphere => |geom_sphere| intersectRaySphere(mray, geom_sphere),
        .box => |geom_box| intersectRayBox(mray, geom_box),
        .mesh => |geom_mesh| intersectRayMesh(mray, geom_mesh),
    };

    if (intersect_geom) |*geom_result| {
        geom_result.dist *= m.mag(wray.d) / m.mag(mrayd); // TODO: could this be achieved by not normalizing mrayd?
        geom_result.norm = m.normalize(m.toVec3( // TODO: with this normalize, you could avoid normalizing in any individual intersection function?
            m.matvec4(obj.trfm, m.toHomogeneousDir(geom_result.norm)),
        ));
        return IntersectResult{
            .geom = geom_result.*,
            .refl = obj.refl,
            .emit = obj.emit,
            .mtrl = obj.mtrl,
        };
    } else {
        return null;
    }
}

// TESTS -----

test "intersectRaySphere --- sphere ahead" {
    const ray: Ray = .{ .o = .{ .data = .{ -2.0, 0.0, 0.0 } }, .d = .{ .data = .{ 1.0, 0.0, 0.0 } } };
    const sphere: Sphere = .{ .r = 1.0 };
    if (intersectRaySphere(ray, sphere)) |result| {
        try std.testing.expectApproxEqAbs(1.0, result.dist, 4 * m.eps);
        try std.testing.expectApproxEqAbs(-1.0, result.norm.data[0], 4 * m.eps);
        try std.testing.expectApproxEqAbs(0.0, result.norm.data[1], 4 * m.eps);
        try std.testing.expectApproxEqAbs(0.0, result.norm.data[2], 4 * m.eps);
    } else {
        try std.testing.expect(false);
    }
}

test "intersectRaySphere --- ray origin inside sphere" {
    const ray: Ray = .{ .o = .{ .data = .{ -0.5, 0.0, 0.0 } }, .d = .{ .data = .{ 1.0, 0.0, 0.0 } } };
    const sphere: Sphere = .{ .r = 1.0 };
    if (intersectRaySphere(ray, sphere)) |result| {
        try std.testing.expectApproxEqAbs(1.5, result.dist, 4 * m.eps);
        try std.testing.expectApproxEqAbs(-1.0, result.norm.data[0], 4 * m.eps);
        try std.testing.expectApproxEqAbs(0.0, result.norm.data[1], 4 * m.eps);
        try std.testing.expectApproxEqAbs(0.0, result.norm.data[2], 4 * m.eps);
    } else {
        try std.testing.expect(false);
    }
}

test "intersectRaySphere --- sphere behind ray origin" {
    const ray: Ray = .{ .o = .{ .data = .{ 1.5, 0.0, 0.0 } }, .d = .{ .data = .{ 1.0, 0.0, 0.0 } } };
    const sphere: Sphere = .{ .r = 1.0 };
    if (intersectRaySphere(ray, sphere)) |_| {
        try std.testing.expect(false);
    } else {
        try std.testing.expect(true);
    }
}

test "intersectRayBox --- box ahead" {
    const ray: Ray = .{ .o = .{ .data = .{ -2.0, 0.0, 0.0 } }, .d = .{ .data = .{ 1.0, 0.0, 0.0 } } };
    const box: Box = .{ .size = .{ .data = .{ 0.5, 0.5, 0.5 } } };
    if (intersectRayBox(ray, box)) |result| {
        try std.testing.expectApproxEqAbs(1.5, result.dist, 4 * m.eps);
        try std.testing.expectApproxEqAbs(-1.0, result.norm.data[0], 4 * m.eps);
        try std.testing.expectApproxEqAbs(0.0, result.norm.data[1], 4 * m.eps);
        try std.testing.expectApproxEqAbs(0.0, result.norm.data[2], 4 * m.eps);
    } else {
        try std.testing.expect(false);
    }
}

test "intersectRayBox --- ray origin inside box" {
    const ray: Ray = .{ .o = .{ .data = .{ 0.25, 0.0, 0.0 } }, .d = .{ .data = .{ 1.0, 0.0, 0.0 } } };
    const box: Box = .{ .size = .{ .data = .{ 0.5, 0.5, 0.5 } } };
    if (intersectRayBox(ray, box)) |result| {
        try std.testing.expectApproxEqAbs(0.25, result.dist, 4 * m.eps);
        try std.testing.expectApproxEqAbs(-1.0, result.norm.data[0], 4 * m.eps);
        try std.testing.expectApproxEqAbs(0.0, result.norm.data[1], 4 * m.eps);
        try std.testing.expectApproxEqAbs(0.0, result.norm.data[2], 4 * m.eps);
    } else {
        try std.testing.expect(false);
    }
}

test "intersectRayBox --- box behind ray origin" {
    const ray: Ray = .{ .o = .{ .data = .{ 0.75, 0.0, 0.0 } }, .d = .{ .data = .{ 1.0, 0.0, 0.0 } } };
    const box: Box = .{ .size = .{ .data = .{ 0.5, 0.5, 0.5 } } };
    if (intersectRayBox(ray, box)) |_| {
        try std.testing.expect(false);
    } else {
        try std.testing.expect(true);
    }
}

test "intersectRayTriangle --- glance" {
    const tri: Triangle = .{ .vertices = .{
        .{ .data = .{ 0.0, 0.0, 0.0 } },
        .{ .data = .{ 1.0, 0.0, 0.0 } },
        .{ .data = .{ 0.0, 1.0, 0.0 } },
    } };
    const ray: Ray = .{
        .o = .{ .data = .{ 1.0 + 0.1, 1.0 + 0.2, -1.0 } },
        .d = m.normalize(.{ .data = .{ -1.0, -1.0, 1.0 } }),
    };
    const result = intersectRayTriangle(ray, tri) orelse unreachable;
    try std.testing.expectApproxEqRel(@sqrt(3.0), result.dist, 1e-5);
    try std.testing.expectEqual(m.Vec3{ .data = .{ 0.0, 0.0, -1.0 } }, result.norm);
}

test "BVH --- builds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator: std.mem.Allocator = arena.allocator();

    const vertices = [_]m.Vec3{
        .{ .data = .{ 0.0, 0.0, 0.0 } },
        .{ .data = .{ 1.0, 0.0, 0.0 } },
        .{ .data = .{ 1.0, 1.0, 0.0 } },
        .{ .data = .{ 0.0, 1.0, 0.0 } },
        .{ .data = .{ 0.0, 0.0, 1.0 } },
        .{ .data = .{ 1.0, 0.0, 1.0 } },
        .{ .data = .{ 1.0, 1.0, 1.0 } },
        .{ .data = .{ 0.0, 1.0, 1.0 } },
    };
    const indices = [_]u32{
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
    try mesh.vrt.appendSlice(allocator, &vertices);
    try mesh.ind.appendSlice(allocator, &indices);

    try buildBVH(&mesh, allocator);

    const ray: Ray = .{ .o = .{ .data = .{ -2.0, 0.2, 0.2 } }, .d = .{ .data = .{ 1.0, 0.0, 0.0 } } };
    if (intersectRayMesh(ray, mesh)) |result| {
        std.debug.print("{}\n", .{result.dist});
        std.debug.print("{}\n", .{result.norm});
    } else {
        std.debug.print("miss!\n", .{});
    }
}
