//! Application and toolchain version constants.
const std = @import("std");

pub const app_name = "WinLab";
pub const app_version = "0.1.0-beta.2";
/// Zig compiler version this source tree is pinned to (see build.zig.zon).
pub const pinned_zig = "0.17.1";

test "built with the pinned Zig version" {
    const builtin = @import("builtin");
    try std.testing.expectEqualStrings(pinned_zig, builtin.zig_version_string);
}
