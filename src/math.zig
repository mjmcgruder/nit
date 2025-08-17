const std = @import("std");

pub const Vec3 = struct { data: @Vector(3, f32) = @Vector(3, f32){0.0, 0.0, 0.0} };

pub const unit_x: Vec3 = Vec3{ .data = .{ 1.0, 0.0, 0.0 } };
pub const unit_y: Vec3 = Vec3{ .data = .{ 0.0, 1.0, 0.0 } };
pub const unit_z: Vec3 = Vec3{ .data = .{ 0.0, 0.0, 1.0 } };

pub const eps: comptime_float = std.math.floatEps(f32);

inline fn getVector(a: anytype) @Vector(3, f32) {
    return if (@TypeOf(a) == Vec3) a.data else @splat(a);
}

pub inline fn add(a: anytype, b: anytype) Vec3 {
    const av: @Vector(3, f32) = getVector(a);
    const bv: @Vector(3, f32) = getVector(b);
    return Vec3{ .data = av + bv };
}

pub inline fn sub(a: anytype, b: anytype) Vec3 {
    const av: @Vector(3, f32) = getVector(a);
    const bv: @Vector(3, f32) = getVector(b);
    return Vec3{ .data = av - bv };
}

pub inline fn mul(a: anytype, b: anytype) Vec3 {
    const av: @Vector(3, f32) = getVector(a);
    const bv: @Vector(3, f32) = getVector(b);
    return Vec3{ .data = av * bv };
}

pub inline fn sdiv(a_in: anytype, b_in: anytype) @TypeOf(a_in, b_in) {
    return a_in / (b_in + eps);
}

pub inline fn dot(a: Vec3, b: Vec3) f32 {
    return @reduce(.Add, a.data * b.data);
}

pub inline fn cross(a: Vec3, b: Vec3) Vec3 {
    return Vec3{ .data = .{
        a.data[1] * b.data[2] - a.data[2] * b.data[1],
        a.data[2] * b.data[0] - a.data[0] * b.data[2],
        a.data[0] * b.data[1] - a.data[1] * b.data[0],
    } };
}

pub inline fn mag(a: Vec3) f32 {
    return @sqrt(dot(a, a));
}

pub inline fn normalize(a: Vec3) Vec3 {
    return mul(a, sdiv(1.0, mag(a)));
}

pub inline fn clamp(a: f32, comptime min: f32, comptime max: f32) f32 {
    return if (a < min) min else if (a > max) max else a;
}

pub inline fn sanitizeNan(a: f32) f32 {
    return if (std.math.isNan(a)) 0.0 else a;
}

// TESTS -----

test "add --- vector-vector" {
    const a = Vec3{ .data = .{ 1.4, 0.2, 0.3 } };
    const b = Vec3{ .data = .{ 0.9, 0.8, 0.1 } };
    const c = add(a, b);
    try std.testing.expectApproxEqRel(2.3, c.data[0], 4 * eps);
    try std.testing.expectApproxEqRel(1.0, c.data[1], 4 * eps);
    try std.testing.expectApproxEqRel(0.4, c.data[2], 4 * eps);
}

test "add --- vector-scalar" {
    const a = Vec3{ .data = .{ 1.4, 0.2, 0.3 } };
    const b = 0.3;
    const c = add(a, b);
    try std.testing.expectApproxEqRel(1.7, c.data[0], 4 * eps);
    try std.testing.expectApproxEqRel(0.5, c.data[1], 4 * eps);
    try std.testing.expectApproxEqRel(0.6, c.data[2], 4 * eps);
}

test "add --- scalar-vector" {
    const a = 0.7;
    const b = Vec3{ .data = .{ 1.4, 0.2, 0.3 } };
    const c = add(a, b);
    try std.testing.expectApproxEqRel(2.1, c.data[0], 4 * eps);
    try std.testing.expectApproxEqRel(0.9, c.data[1], 4 * eps);
    try std.testing.expectApproxEqRel(1.0, c.data[2], 4 * eps);
}

test "sub --- vector-vector" {
    const a = Vec3{ .data = .{ 1.4, 0.2, 0.3 } };
    const b = Vec3{ .data = .{ 0.9, 0.8, 0.1 } };
    const c = sub(a, b);
    try std.testing.expectApproxEqRel(0.5, c.data[0], 4 * eps);
    try std.testing.expectApproxEqRel(-0.6, c.data[1], 4 * eps);
    try std.testing.expectApproxEqRel(0.2, c.data[2], 4 * eps);
}

test "sub --- vector-scalar" {
    const a = Vec3{ .data = .{ 1.4, 0.2, 0.3 } };
    const b = 0.3;
    const c = sub(a, b);
    try std.testing.expectApproxEqRel(1.1, c.data[0], 4 * eps);
    try std.testing.expectApproxEqRel(-0.1, c.data[1], 4 * eps);
    try std.testing.expectApproxEqRel(0.0, c.data[2], 4 * eps);
}

test "sub --- scalar-vector" {
    const a = 0.7;
    const b = Vec3{ .data = .{ 1.4, 0.2, 0.3 } };
    const c = sub(a, b);
    try std.testing.expectApproxEqRel(-0.7, c.data[0], 4 * eps);
    try std.testing.expectApproxEqRel(0.5, c.data[1], 4 * eps);
    try std.testing.expectApproxEqRel(0.4, c.data[2], 4 * eps);
}

test "mul --- vector-vector" {
    const a = Vec3{ .data = .{ 1.4, 0.2, 0.3 } };
    const b = Vec3{ .data = .{ 0.9, 0.8, 0.1 } };
    const c = mul(a, b);
    try std.testing.expectApproxEqRel(1.4 * 0.9, c.data[0], 4 * eps);
    try std.testing.expectApproxEqRel(0.2 * 0.8, c.data[1], 4 * eps);
    try std.testing.expectApproxEqRel(0.3 * 0.1, c.data[2], 4 * eps);
}

test "mul --- vector-scalar" {
    const a = Vec3{ .data = .{ 1.4, 0.2, 0.3 } };
    const b = 1.2;
    const c = mul(a, b);
    try std.testing.expectApproxEqRel(1.4 * 1.2, c.data[0], 4 * eps);
    try std.testing.expectApproxEqRel(0.2 * 1.2, c.data[1], 4 * eps);
    try std.testing.expectApproxEqRel(0.3 * 1.2, c.data[2], 4 * eps);
}

test "mul --- scalar-vector" {
    const a = 1.6;
    const b = Vec3{ .data = .{ 1.4, 0.2, 0.3 } };
    const c = mul(a, b);
    try std.testing.expectApproxEqRel(1.4 * 1.6, c.data[0], 4 * eps);
    try std.testing.expectApproxEqRel(0.2 * 1.6, c.data[1], 4 * eps);
    try std.testing.expectApproxEqRel(0.3 * 1.6, c.data[2], 4 * eps);
}

test "sdiv --- comptime_float" {
    const a: comptime_float = 4.2;
    const b: f32 = 6.3;
    const c: f32 = sdiv(a, b);
    try std.testing.expectApproxEqRel(4.2 / 6.3, c, 4 * eps);
}

test "sdiv --- zero by zero" {
    const a: f32 = 0.0;
    const b: f32 = 0.0;
    const c: f32 = sdiv(a, b);
    try std.testing.expectEqual(0.0, c);
}

test "dot --- unit circle x-y" {
    const a = Vec3{ .data = .{ 0.0, 1.0, 0.0 } };
    const b = Vec3{ .data = .{
        std.math.cos(120.0 * (std.math.pi / 180.0)),
        std.math.sin(120.0 * (std.math.pi / 180.0)),
        0.0,
    } };
    try std.testing.expectApproxEqRel(@sqrt(3.0) / 2.0, dot(a, b), 4 * eps);
}

test "dot --- unit circle x-z" {
    const a = Vec3{ .data = .{ 0.0, 0.0, 1.0 } };
    const b = Vec3{ .data = .{
        std.math.cos(120.0 * (std.math.pi / 180.0)),
        0.0,
        std.math.sin(120.0 * (std.math.pi / 180.0)),
    } };
    try std.testing.expectApproxEqRel(@sqrt(3.0) / 2.0, dot(a, b), 4 * eps);
}

test "dot --- orthogonal" {
    const a = Vec3{ .data = .{
        std.math.cos(120.0 * (std.math.pi / 180.0)),
        std.math.sin(120.0 * (std.math.pi / 180.0)),
        0.0,
    } };
    const b = Vec3{ .data = .{
        0.0,
        0.0,
        1.0,
    } };
    try std.testing.expectApproxEqRel(0.0, dot(a, b), 4 * eps);
}

test "cross --- make orthogonal axes" {
    const x = Vec3{ .data = .{ 1.0, 0.0, 0.0 } };
    const y = Vec3{ .data = .{ 0.0, 1.0, 0.0 } };
    const z: Vec3 = cross(x, y);
    try std.testing.expectApproxEqAbs(0.0, z.data[0], 4 * eps);
    try std.testing.expectApproxEqAbs(0.0, z.data[1], 4 * eps);
    try std.testing.expectApproxEqAbs(1.0, z.data[2], 4 * eps);
}

test "mag --- unit circle" {
    const a = Vec3{ .data = .{ 1.0 / 2.0, @sqrt(3.0) / 2.0, 0.0 } };
    try std.testing.expectApproxEqRel(1.0, mag(a), 4 * eps);
}

test "normalize --- makes magnitude 1" {
    const a = Vec3{ .data = .{ 1.0, 1.0, 1.0 } };
    try std.testing.expectApproxEqRel(1.0, mag(normalize(a)), 4 * eps);
}
