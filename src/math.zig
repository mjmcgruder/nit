const std = @import("std");

pub const Vec3 = @Vector(3, f32); // note this structure is probably 16 bytes
pub const Vec4 = @Vector(4, f32);
pub const Mat4 = [4]@Vector(4, f32);

pub fn makeVec3(src: [3]f32) Vec3 {
    return .{ src[0], src[1], src[2] };
}

pub fn toVec3(src: Vec4) Vec3 {
    return .{ src[0], src[1], src[2] };
}

pub fn toVec4(src: Vec3) Vec4 {
    return .{ src[0], src[1], src[2], 0.0 };
}

pub fn toHomogeneousPos(src: Vec3) Vec4 {
    return .{ src[0], src[1], src[2], 1.0 };
}

pub fn toHomogeneousDir(src: Vec3) Vec4 {
    return toVec4(src);
}

pub fn matvec4(mat: Mat4, vec: Vec4) Vec4 {
    var res: Vec4 = undefined;
    inline for (0..4) |r| {
        res[r] = @reduce(.Add, mat[r] * vec);
    }
    return res;
}

pub fn matmul4(a: Mat4, b: Mat4) Mat4 {
    var res: Mat4 = undefined;
    inline for (0..4) |c| {
        const col: Vec4 = .{ b[0][c], b[1][c], b[2][c], b[3][c] };
        inline for (0..4) |r| {
            res[r][c] = @reduce(.Add, a[r] * col);
        }
    }
    return res;
}

/// adapted from:
///   https://fgiesen.wordpress.com/2013/07/09/simd-transposes-1/
pub fn mattnp4(mat: Mat4) Mat4 {
    const a0 = @shuffle(f32, mat[0], mat[1], @Vector(4, i32){ 0, -1, 1, -2 });
    const a1 = @shuffle(f32, mat[0], mat[1], @Vector(4, i32){ 2, -3, 3, -4 });
    const a2 = @shuffle(f32, mat[2], mat[3], @Vector(4, i32){ 0, -1, 1, -2 });
    const a3 = @shuffle(f32, mat[2], mat[3], @Vector(4, i32){ 2, -3, 3, -4 });
    return .{
        @shuffle(f32, a0, a2, @Vector(4, i32){ 0, 1, -1, -2 }),
        @shuffle(f32, a0, a2, @Vector(4, i32){ 2, 3, -3, -4 }),
        @shuffle(f32, a1, a3, @Vector(4, i32){ 0, 1, -1, -2 }),
        @shuffle(f32, a1, a3, @Vector(4, i32){ 2, 3, -3, -4 }),
    };
}

/// adapted from:
///   https://lxjk.github.io/2017/09/03/Fast-4x4-Matrix-Inverse-with-SSE-SIMD-Explained.html
/// Translation may be arbitrary. Bottom row values must be zero, except the final value which
/// should be 1.
pub fn invertTransform(mat: Mat4) Mat4 {
    const tnp: Mat4 = mattnp4(mat);
    const ixsq: f32 = 1.0 / @reduce(.Add, tnp[0] * tnp[0]);
    const iysq: f32 = 1.0 / @reduce(.Add, tnp[1] * tnp[1]);
    const izsq: f32 = 1.0 / @reduce(.Add, tnp[2] * tnp[2]);
    var inv: Mat4 = tnp;
    const trs: @Vector(4, f32) = .{ tnp[3][0], tnp[3][1], tnp[3][2], 0.0 };
    inv[0] *= @as(@Vector(4, f32), @splat(ixsq));
    inv[1] *= @as(@Vector(4, f32), @splat(iysq));
    inv[2] *= @as(@Vector(4, f32), @splat(izsq));
    inv[0][3] = -ixsq * @reduce(.Add, tnp[0] * trs);
    inv[1][3] = -iysq * @reduce(.Add, tnp[1] * trs);
    inv[2][3] = -izsq * @reduce(.Add, tnp[2] * trs);
    inv[3][0] = 0.0;
    inv[3][1] = 0.0;
    inv[3][2] = 0.0;
    return inv;
}

pub fn translate(vec: Vec3) Mat4 { // TODO: this naming scheme is... bad?
    return .{
        .{ 1.0, 0.0, 0.0, vec[0] },
        .{ 0.0, 1.0, 0.0, vec[1] },
        .{ 0.0, 0.0, 1.0, vec[2] },
        .{ 0.0, 0.0, 0.0, 1.0 },
    };
}

pub fn scale(multiple: f32) Mat4 {
    return .{
        .{ multiple, 0.0, 0.0, 0.0 },
        .{ 0.0, multiple, 0.0, 0.0 },
        .{ 0.0, 0.0, multiple, 0.0 },
        .{ 0.0, 0.0, 0.0, 1.0 },
    };
}

pub fn rotateAboutAxis(axis: Vec3, angled: f32) Mat4 {
    const axis_normalized: Vec3 = normalize(axis);
    const c: f32 = @cos(angled * (std.math.pi / 180.0));
    const s: f32 = @sin(angled * (std.math.pi / 180.0));
    const x: f32 = axis_normalized[0];
    const y: f32 = axis_normalized[1];
    const z: f32 = axis_normalized[2];
    const omc: f32 = 1.0 - c;
    return .{
        .{ omc * x * x + c, omc * x * y - s * z, omc * x * z + s * y, 0.0 },
        .{ omc * x * y + s * z, omc * y * y + c, omc * y * z - s * x, 0.0 },
        .{ omc * x * z - s * y, omc * y * z + s * x, omc * z * z + c, 0.0 },
        .{ 0.0, 0.0, 0.0, 1.0 },
    };
}

pub fn identity() Mat4 {
    return .{
        .{ 1.0, 0.0, 0.0, 0.0 },
        .{ 0.0, 1.0, 0.0, 0.0 },
        .{ 0.0, 0.0, 1.0, 0.0 },
        .{ 0.0, 0.0, 0.0, 1.0 },
    };
}

pub const unit_x: Vec3 = .{ 1.0, 0.0, 0.0 };
pub const unit_y: Vec3 = .{ 0.0, 1.0, 0.0 };
pub const unit_z: Vec3 = .{ 0.0, 0.0, 1.0 };

pub const eps: comptime_float = std.math.floatEps(f32);

pub inline fn set3(val: f32) Vec3 {
    return .{ val, val, val };
}

pub inline fn set4(val: f32) Vec4 {
    return .{ val, val, val, val };
}

inline fn getVector(a: anytype) @Vector(3, f32) {
    return if (@TypeOf(a) == Vec3) a else @splat(a);
}

pub inline fn add(a: anytype, b: anytype) Vec3 {
    const av: @Vector(3, f32) = getVector(a);
    const bv: @Vector(3, f32) = getVector(b);
    return av + bv;
}

pub inline fn sub(a: anytype, b: anytype) Vec3 {
    const av: @Vector(3, f32) = getVector(a);
    const bv: @Vector(3, f32) = getVector(b);
    return av - bv;
}

pub inline fn mul(a: anytype, b: anytype) Vec3 {
    const av: @Vector(3, f32) = getVector(a);
    const bv: @Vector(3, f32) = getVector(b);
    return av * bv;
}

pub inline fn sdiv(a: anytype, b: anytype) @TypeOf(a, b) {
    return if (b == 0.0) (a / eps) else (a / b);
}

pub inline fn div(a: anytype, b: anytype) Vec3 {
    const av: @Vector(3, f32) = getVector(a);
    const bv: @Vector(3, f32) = getVector(b);
    var dv: @Vector(3, f32) = undefined;
    inline for (0..3) |i| {
        dv[i] = sdiv(av[i], bv[i]);
    }
    return dv;
}

pub inline fn step(edge: anytype, x: anytype) Vec3 {
    const ev: @Vector(3, f32) = getVector(edge);
    const xv: @Vector(3, f32) = getVector(x);
    var result: Vec3 = undefined;
    inline for (0..3) |i| {
        result[i] = if (xv[i] < ev[i]) 0.0 else 1.0;
    }
    return result;
}

pub inline fn sign(x: Vec3) Vec3 {
    var result: Vec3 = undefined;
    inline for (0..3) |i| {
        result[i] = if (x[i] < 0.0) -1.0 else 1.0;
    }
    return result;
}

pub inline fn abs(x: Vec3) Vec3 {
    return @abs(x);
}

pub inline fn dot(a: Vec3, b: Vec3) f32 {
    return @reduce(.Add, a * b);
}

pub inline fn cross(a: Vec3, b: Vec3) Vec3 {
    return .{
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    };
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
    return .{ .s = @sin(x), .c = @cos(x) };
}

pub inline fn sincos_approx(x: f32) SinCos {
    @setEvalBranchQuota(1 << 12);

    const twopi: f32 = comptime 2.0 * std.math.pi;
    const inv_twopi: f32 = comptime 1.0 / twopi;

    const table = comptime init_table: {
        var sincos_table: [1 << 11]SinCos = undefined;

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

test "add --- vector-vector" {
    const a: Vec3 = .{ 1.4, 0.2, 0.3 };
    const b: Vec3 = .{ 0.9, 0.8, 0.1 };
    const c = add(a, b);
    try std.testing.expectApproxEqRel(2.3, c[0], 4 * eps);
    try std.testing.expectApproxEqRel(1.0, c[1], 4 * eps);
    try std.testing.expectApproxEqRel(0.4, c[2], 4 * eps);
}

test "add --- vector-scalar" {
    const a: Vec3 = .{ 1.4, 0.2, 0.3 };
    const b = 0.3;
    const c = add(a, b);
    try std.testing.expectApproxEqRel(1.7, c[0], 4 * eps);
    try std.testing.expectApproxEqRel(0.5, c[1], 4 * eps);
    try std.testing.expectApproxEqRel(0.6, c[2], 4 * eps);
}

test "add --- scalar-vector" {
    const a = 0.7;
    const b: Vec3 = .{ 1.4, 0.2, 0.3 };
    const c = add(a, b);
    try std.testing.expectApproxEqRel(2.1, c[0], 4 * eps);
    try std.testing.expectApproxEqRel(0.9, c[1], 4 * eps);
    try std.testing.expectApproxEqRel(1.0, c[2], 4 * eps);
}

test "sub --- vector-vector" {
    const a: Vec3 = .{ 1.4, 0.2, 0.3 };
    const b: Vec3 = .{ 0.9, 0.8, 0.1 };
    const c = sub(a, b);
    try std.testing.expectApproxEqRel(0.5, c[0], 4 * eps);
    try std.testing.expectApproxEqRel(-0.6, c[1], 4 * eps);
    try std.testing.expectApproxEqRel(0.2, c[2], 4 * eps);
}

test "sub --- vector-scalar" {
    const a: Vec3 = .{ 1.4, 0.2, 0.3 };
    const b = 0.3;
    const c = sub(a, b);
    try std.testing.expectApproxEqRel(1.1, c[0], 4 * eps);
    try std.testing.expectApproxEqRel(-0.1, c[1], 4 * eps);
    try std.testing.expectApproxEqRel(0.0, c[2], 4 * eps);
}

test "sub --- scalar-vector" {
    const a = 0.7;
    const b: Vec3 = .{ 1.4, 0.2, 0.3 };
    const c = sub(a, b);
    try std.testing.expectApproxEqRel(-0.7, c[0], 4 * eps);
    try std.testing.expectApproxEqRel(0.5, c[1], 4 * eps);
    try std.testing.expectApproxEqRel(0.4, c[2], 4 * eps);
}

test "mul --- vector-vector" {
    const a: Vec3 = .{ 1.4, 0.2, 0.3 };
    const b: Vec3 = .{ 0.9, 0.8, 0.1 };
    const c = mul(a, b);
    try std.testing.expectApproxEqRel(1.4 * 0.9, c[0], 4 * eps);
    try std.testing.expectApproxEqRel(0.2 * 0.8, c[1], 4 * eps);
    try std.testing.expectApproxEqRel(0.3 * 0.1, c[2], 4 * eps);
}

test "mul --- vector-scalar" {
    const a: Vec3 = .{ 1.4, 0.2, 0.3 };
    const b = 1.2;
    const c = mul(a, b);
    try std.testing.expectApproxEqRel(1.4 * 1.2, c[0], 4 * eps);
    try std.testing.expectApproxEqRel(0.2 * 1.2, c[1], 4 * eps);
    try std.testing.expectApproxEqRel(0.3 * 1.2, c[2], 4 * eps);
}

test "mul --- scalar-vector" {
    const a = 1.6;
    const b: Vec3 = .{ 1.4, 0.2, 0.3 };
    const c = mul(a, b);
    try std.testing.expectApproxEqRel(1.4 * 1.6, c[0], 4 * eps);
    try std.testing.expectApproxEqRel(0.2 * 1.6, c[1], 4 * eps);
    try std.testing.expectApproxEqRel(0.3 * 1.6, c[2], 4 * eps);
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
    const a: Vec3 = .{ 0.0, 1.0, 0.0 };
    const b: Vec3 = .{
        std.math.cos(120.0 * (std.math.pi / 180.0)),
        std.math.sin(120.0 * (std.math.pi / 180.0)),
        0.0,
    };
    try std.testing.expectApproxEqRel(@sqrt(3.0) / 2.0, dot(a, b), 4 * eps);
}

test "dot --- unit circle x-z" {
    const a: Vec3 = .{ 0.0, 0.0, 1.0 };
    const b: Vec3 = .{
        std.math.cos(120.0 * (std.math.pi / 180.0)),
        0.0,
        std.math.sin(120.0 * (std.math.pi / 180.0)),
    };
    try std.testing.expectApproxEqRel(@sqrt(3.0) / 2.0, dot(a, b), 4 * eps);
}

test "dot --- orthogonal" {
    const a: Vec3 = .{
        std.math.cos(120.0 * (std.math.pi / 180.0)),
        std.math.sin(120.0 * (std.math.pi / 180.0)),
        0.0,
    };
    const b: Vec3 = .{
        0.0,
        0.0,
        1.0,
    };
    try std.testing.expectApproxEqRel(0.0, dot(a, b), 4 * eps);
}

test "cross --- make orthogonal axes" {
    const x: Vec3 = .{ 1.0, 0.0, 0.0 };
    const y: Vec3 = .{ 0.0, 1.0, 0.0 };
    const z: Vec3 = cross(x, y);
    try std.testing.expectApproxEqAbs(0.0, z[0], 4 * eps);
    try std.testing.expectApproxEqAbs(0.0, z[1], 4 * eps);
    try std.testing.expectApproxEqAbs(1.0, z[2], 4 * eps);
}

test "mag --- unit circle" {
    const a: Vec3 = .{ 1.0 / 2.0, @sqrt(3.0) / 2.0, 0.0 };
    try std.testing.expectApproxEqAbs(1.0, mag(a), 4 * eps);
}

test "normalize --- makes magnitude 1" {
    const a: Vec3 = .{ 1.0, 1.0, 1.0 };
    try std.testing.expectApproxEqAbs(1.0, mag(normalize(a)), 4 * eps);
}

test "sincos --- sin cos quadrant 0" {
    const x: f32 = std.math.pi / 8.0;
    const sincos = sincos_approx(x);
    try std.testing.expectApproxEqRel(@sin(x), sincos.s, 1.0e-2);
    try std.testing.expectApproxEqRel(@cos(x), sincos.c, 1.0e-2);
}

test "sincos_approx --- sin cos quadrant 1" {
    const x: f32 = 3.0 * (std.math.pi / 8.0);
    const sincos = sincos_approx(x);
    try std.testing.expectApproxEqRel(@sin(x), sincos.s, 1.0e-2);
    try std.testing.expectApproxEqRel(@cos(x), sincos.c, 1.0e-2);
}

test "sincos_approx --- sin cos quadrant 2" {
    const x: f32 = 9.0 * (std.math.pi / 8.0);
    const sincos = sincos_approx(x);
    try std.testing.expectApproxEqRel(@sin(x), sincos.s, 1.0e-2);
    try std.testing.expectApproxEqRel(@cos(x), sincos.c, 1.0e-2);
}

test "sincos_approx --- sin cos quadrant 3" {
    const x: f32 = 11.0 * (std.math.pi / 8.0);
    const sincos = sincos_approx(x);
    try std.testing.expectApproxEqRel(@sin(x), sincos.s, 1.0e-2);
    try std.testing.expectApproxEqRel(@cos(x), sincos.c, 1.0e-2);
}

test "Mat4 --- identity" {
    const mat: Mat4 = identity();
    inline for (0..4) |r| {
        inline for (0..4) |c| {
            if (r == c) {
                try std.testing.expectEqual(1.0, mat[r][c]);
            } else {
                try std.testing.expectEqual(0.0, mat[r][c]);
            }
        }
    }
}

test "matvec4 --- identity" {
    const mat: Mat4 = .{
        .{ 1.0, 0.0, 0.0, 0.0 },
        .{ 0.0, 1.0, 0.0, 0.0 },
        .{ 0.0, 0.0, 1.0, 0.0 },
        .{ 0.0, 0.0, 0.0, 1.0 },
    };
    const vec: Vec4 = .{ 1.4, 2.7, 3.1, 6.2 };

    const vec_new: Vec4 = matvec4(mat, vec);

    inline for (0..4) |i| {
        try std.testing.expectEqual(vec[i], vec_new[i]);
    }
}

test "matvec4 --- axis flip" {
    const mat: Mat4 = .{
        .{ 0.0, 1.0, 0.0, 0.0 },
        .{ 1.0, 0.0, 0.0, 0.0 },
        .{ 0.0, 0.0, 1.0, 0.0 },
        .{ 0.0, 0.0, 0.0, 1.0 },
    };
    const vec: Vec4 = .{ 1.0, 0.0, 0.0, 0.0 };

    const vec_new: Vec4 = matvec4(mat, vec);

    try std.testing.expectEqual(0.0, vec_new[0]);
    try std.testing.expectEqual(1.0, vec_new[1]);
    try std.testing.expectEqual(0.0, vec_new[2]);
    try std.testing.expectEqual(0.0, vec_new[3]);
}

test "mattnp4 --- integer matrix" {
    const mat: Mat4 = .{
        .{ 0, 9, 5, 3 },
        .{ 0, 1, 2, 2 },
        .{ 7, 1, 2, 3 },
        .{ 1, 8, 2, 4 },
    };

    const tnp: Mat4 = mattnp4(mat);

    inline for (0..4) |r| {
        inline for (0..4) |c| {
            try std.testing.expectEqual(mat[c][r], tnp[r][c]);
        }
    }
}

test "matvec4 --- orthonormal, transpose, identity" {
    const mat: Mat4 = .{
        .{ 0, 0, 1, 0 },
        .{ 0, 1, 0, 0 },
        .{ 1, 0, 0, 0 },
        .{ 0, 0, 0, 1 },
    };

    const inv: Mat4 = mattnp4(mat);

    const test_identity: Mat4 = matmul4(mat, inv);

    inline for (0..4) |r| {
        inline for (0..4) |c| {
            if (r == c) {
                try std.testing.expectApproxEqAbs(1.0, test_identity[r][c], eps);
            } else {
                try std.testing.expectApproxEqAbs(0.0, test_identity[r][c], eps);
            }
        }
    }
}

test "invertTransform --- recovers identity" {
    const mat: Mat4 = .{
        .{ 0.0, 7.0, 0.0, 0.2 },
        .{ 0.0, 0.0, 1.0, 7.0 },
        .{ 3.0, 0.0, 0.0, 2.7 },
        .{ 0.0, 0.0, 0.0, 1.0 },
    };

    const inv: Mat4 = invertTransform(mat);

    const test_identity: Mat4 = matmul4(mat, inv);

    inline for (0..4) |r| {
        inline for (0..4) |c| {
            if (r == c) {
                try std.testing.expectApproxEqAbs(1.0, test_identity[r][c], eps);
            } else {
                try std.testing.expectApproxEqAbs(0.0, test_identity[r][c], eps);
            }
        }
    }
}
