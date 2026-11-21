//! WinLab core library. UI-independent; see docs/architecture.md.
pub const version = @import("app/version.zig");
pub const shell_discovery = @import("windows/shell_discovery.zig");
pub const conpty = @import("terminal/conpty.zig");
pub const vm_provider = @import("vm/provider.zig");
pub const vm_mock = @import("vm/mock.zig");
pub const vm_qemu = @import("vm/qemu.zig");
pub const vm_images = @import("vm/images.zig");
pub const vm_unattend = @import("vm/unattend.zig");
pub const vm_guest = @import("vm/guest.zig");
pub const vm_iso9660 = @import("vm/iso9660.zig");
pub const vm_cloud_init = @import("vm/cloud_init.zig");
pub const vm_registry = @import("vm/registry.zig");
pub const lab = @import("labs/lab.zig");
pub const script_lab = @import("labs/script_lab.zig");
pub const terminal_screen = @import("terminal/screen.zig");
pub const links = @import("content/links.zig");
pub const settings = @import("storage/settings.zig");
pub const settings_file = @import("storage/settings_file.zig");
pub const progress = @import("storage/progress.zig");
pub const progress_file = @import("storage/progress_file.zig");
pub const manifest = @import("content/manifest.zig");
pub const catalog = @import("content/catalog.zig");
pub const search = @import("content/search.zig");
pub const lesson_view = @import("content/lesson_view.zig");
pub const certs = @import("content/certs.zig");
pub const quiz = @import("content/quiz.zig");
pub const paths = @import("content/paths.zig");
pub const md = @import("md");

test {
    @import("std").testing.refAllDecls(@This());
}
