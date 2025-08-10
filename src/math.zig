const std = @import("std");

pub const unit_x: Vec3 = Vec3{ .x = 1.0, .y = 0.0, .z = 0.0 };
pub const unit_y: Vec3 = Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 };
pub const unit_z: Vec3 = Vec3{ .x = 0.0, .y = 0.0, .z = 1.0 };

pub const eps: comptime_float = std.math.floatEps(f32);

pub const Vec3 = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,
};

pub inline fn broadcast(a: anytype) Vec3 {
    var result: Vec3 = undefined;
    inline for (@typeInfo(Vec3).@"struct".fields) |field| {
        @field(result, field.name) = switch (@TypeOf(a)) {
            Vec3 => @field(a, field.name),
            comptime_float => a,
            f32 => a,
            else => comptime unreachable,
        };
    }
    return result;
}

pub inline fn add(a_in: anytype, b_in: anytype) Vec3 {
    const a: Vec3 = broadcast(a_in);
    const b: Vec3 = broadcast(b_in);
    return Vec3{
        .x = a.x + b.x,
        .y = a.y + b.y,
        .z = a.z + b.z,
    };
}

pub inline fn sub(a_in: anytype, b_in: anytype) Vec3 {
    const a: Vec3 = broadcast(a_in);
    const b: Vec3 = broadcast(b_in);
    return Vec3{
        .x = a.x - b.x,
        .y = a.y - b.y,
        .z = a.z - b.z,
    };
}

pub inline fn mul(a_in: anytype, b_in: anytype) Vec3 {
    const a: Vec3 = broadcast(a_in);
    const b: Vec3 = broadcast(b_in);
    return Vec3{
        .x = a.x * b.x,
        .y = a.y * b.y,
        .z = a.z * b.z,
    };
}

pub inline fn div(a_in: anytype, b_in: anytype) @TypeOf(a_in, b_in) {
    return a_in / (b_in + eps);
}

pub inline fn dot(a: Vec3, b: Vec3) f32 {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

pub inline fn cross(a: Vec3, b: Vec3) Vec3 {
    return Vec3{
        .x = a.y * b.z - a.z * b.y,
        .y = a.z * b.x - a.x * b.z,
        .z = a.x * b.y - a.y * b.x,
    };
}

pub inline fn mag(a: Vec3) f32 {
    return @sqrt(dot(a, a));
}

pub inline fn normalize(a: Vec3) Vec3 {
    return mul(a, div(1.0, mag(a)));
}

pub inline fn clamp(a: f32, comptime min: f32, comptime max: f32) f32 {
    return if (a < min) min else if (a > max) max else a;
}

pub inline fn sanitizeNan(a: f32) f32 {
    return if (std.math.isNan(a)) 0.0 else a;
}

// TESTS -----

test "add --- vector add" {
    const a = Vec3{ .x = 1.4, .y = 0.2, .z = 0.3 };
    const b = Vec3{ .x = 0.9, .y = 0.8, .z = 0.1 };
    const c = add(a, b);
    try std.testing.expectApproxEqRel(2.3, c.x, 4 * eps);
    try std.testing.expectApproxEqRel(1.0, c.y, 4 * eps);
    try std.testing.expectApproxEqRel(0.4, c.z, 4 * eps);
}

test "sub --- vector sub" {
    const a = Vec3{ .x = 1.4, .y = 0.2, .z = 0.3 };
    const b = Vec3{ .x = 0.9, .y = 0.8, .z = 0.1 };
    const c = sub(a, b);
    try std.testing.expectApproxEqRel(0.5, c.x, 4 * eps);
    try std.testing.expectApproxEqRel(-0.6, c.y, 4 * eps);
    try std.testing.expectApproxEqRel(0.2, c.z, 4 * eps);
}

test "mul --- vector mul" {
    const a = Vec3{ .x = 1.4, .y = 0.2, .z = 0.3 };
    const b = Vec3{ .x = 0.9, .y = 0.8, .z = 0.1 };
    const c = mul(a, b);
    try std.testing.expectApproxEqRel(1.4 * 0.9, c.x, 4 * eps);
    try std.testing.expectApproxEqRel(0.2 * 0.8, c.y, 4 * eps);
    try std.testing.expectApproxEqRel(0.3 * 0.1, c.z, 4 * eps);
}

test "div --- comptime_float" {
    const a: comptime_float = 4.2;
    const b: f32 = 6.3;
    const c: f32 = div(a, b);
    try std.testing.expectApproxEqRel(4.2 / 6.3, c, 4 * eps);
}

test "div --- zero by zero" {
    const a: f32 = 0.0;
    const b: f32 = 0.0;
    const c: f32 = div(a, b);
    try std.testing.expectEqual(0.0, c);
}

test "dot --- unit circle check" {
    const a = Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 };
    const b = Vec3{
        .x = std.math.cos(120.0 * (std.math.pi / 180.0)),
        .y = std.math.sin(120.0 * (std.math.pi / 180.0)),
        .z = 0.0,
    };
    try std.testing.expectApproxEqRel(@sqrt(3.0) / 2.0, dot(a, b), 4 * eps);
}

test "cross --- make orthogonal axes" {
    const x = Vec3{ .x = 1.0, .y = 0.0, .z = 0.0 };
    const y = Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 };
    const z: Vec3 = cross(x, y);
    try std.testing.expectApproxEqAbs(0.0, z.x, 4 * eps);
    try std.testing.expectApproxEqAbs(0.0, z.y, 4 * eps);
    try std.testing.expectApproxEqAbs(1.0, z.z, 4 * eps);
}

test "mag --- unit circle" {
    const a = Vec3{ .x = 1.0 / 2.0, .y = @sqrt(3.0) / 2.0, .z = 0.0 };
    try std.testing.expectApproxEqRel(1.0, mag(a), 4 * eps);
}

test "normalize --- makes magnitude 1" {
    const a = Vec3{ .x = 1.0, .y = 1.0, .z = 1.0 };
    try std.testing.expectApproxEqRel(1.0, mag(normalize(a)), 4 * eps);
}
