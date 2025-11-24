const std = @import("std");

pub const Vec3 = struct { data: @Vector(3, f32) = @Vector(3, f32){ 0.0, 0.0, 0.0 } };

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

pub inline fn sdiv(a: anytype, b: anytype) @TypeOf(a, b) {
    return if (b == 0.0) 0.0 else (a / b);
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

pub const SinCos = struct {
    s: f32,
    c: f32,
};

pub inline fn sincos_exact(x: f32) SinCos {
    return .{.s = @sin(x), .c = @cos(x)};
}

pub inline fn sincos_approx(x: f32) SinCos {
    const twopi: f32 = comptime 2.0 * std.math.pi;
    const inv_twopi: f32 = comptime 1.0 / twopi;

    const table = comptime init_table: {
        var sincos_table: [1 << 9]SinCos = undefined;

        const dtheta: f32 = twopi / @as(f32, @floatFromInt(sincos_table.len));
        var theta: f32 = 0.0;
        for (&sincos_table) |*val| {
            val.s = @sin(theta);
            val.c = @cos(theta);
            theta += dtheta;
        }

        break :init_table sincos_table;
    };

    const table_index: usize = @intFromFloat(x * inv_twopi * @as(f32, @floatFromInt(table.len)));
    return table[table_index];
}

// TESTS -----

test "sincos --- sin cos quadrant 0" {
    const x: f32 = std.math.pi / 8.0;
    var s: f32 = undefined;
    var c: f32 = undefined;
    sincos_approx(x, &s, &c);
    std.debug.print("\n", .{});
    std.debug.print("{} {}\n", .{ s, @sin(x) });
    std.debug.print("{} {}\n", .{ c, @cos(x) });
}

test "sincos_approx --- sin cos quadrant 1" {
    const x: f32 = 3.0 * (std.math.pi / 8.0);
    var s: f32 = undefined;
    var c: f32 = undefined;
    sincos_approx(x, &s, &c);
    std.debug.print("\n", .{});
    std.debug.print("{} {}\n", .{ s, @sin(x) });
    std.debug.print("{} {}\n", .{ c, @cos(x) });
}

test "sincos_approx --- sin cos quadrant 2" {
    const x: f32 = 9.0 * (std.math.pi / 8.0);
    var s: f32 = undefined;
    var c: f32 = undefined;
    sincos_approx(x, &s, &c);
    std.debug.print("\n", .{});
    std.debug.print("{} {}\n", .{ s, @sin(x) });
    std.debug.print("{} {}\n", .{ c, @cos(x) });
}

test "sincos_approx --- sin cos quadrant 3" {
    const x: f32 = 11.0 * (std.math.pi / 8.0);
    var s: f32 = undefined;
    var c: f32 = undefined;
    sincos_approx(x, &s, &c);
    std.debug.print("\n", .{});
    std.debug.print("{} {}\n", .{ s, @sin(x) });
    std.debug.print("{} {}\n", .{ c, @cos(x) });
}

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
