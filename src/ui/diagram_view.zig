//! Draws a lesson diagram (`content/diagram.zig`) with DVUI: it scales to the width of the lesson, uses the
//! app's own fonts (so labels stay sharp) and takes its colours from the light or dark theme.
const std = @import("std");
const dvui = @import("dvui");
const diagram = @import("winlab").diagram;

/// The drawing is never enlarged beyond this, so a wide window does not give huge lettering.
const max_scale: f32 = 1.4;
const min_scale: f32 = 0.4;

const Paint = struct { fill: ?dvui.Color, line: dvui.Color };

fn paint(s: diagram.Style) Paint {
    const theme = dvui.themeGet();
    const dark = theme.dark;
    const orange: dvui.Color = if (dark) .{ .r = 0xe3, .g = 0x9b, .b = 0x4b } else .{ .r = 0xc9, .g = 0x73, .b = 0x1c };
    var out: Paint = .{ .fill = null, .line = theme.text.opacity(0.65) };
    if (s.zone_user) out = .{ .fill = theme.focus.opacity(0.12), .line = theme.focus };
    if (s.zone_kernel) out = .{ .fill = orange.opacity(0.14), .line = orange };
    if (s.hardware) out.fill = theme.text.opacity(0.10);
    if (s.accent) out.line = theme.focus;
    return out;
}

/// Draws `d` into the current parent, as wide as the parent allows.
pub fn draw(d: *const diagram.Diagram, id_extra: usize) void {
    var holder = dvui.box(@src(), .{}, .{ .expand = .horizontal, .id_extra = id_extra, .margin = .{ .h = 4 } });
    defer holder.deinit();
    const available = holder.data().contentRect().w; // zero on the very first frame
    const scale = if (available > 0) std.math.clamp(available / d.width, min_scale, max_scale) else 1;

    var canvas = dvui.box(@src(), .{}, .{ .min_size_content = .{ .w = d.width * scale, .h = d.height * scale }, .gravity_x = 0.5 });
    defer canvas.deinit();
    if (!canvas.data().visible()) return;
    const rs = canvas.data().contentRectScale();
    const k = scale * rs.s; // diagram units to screen pixels

    for (d.items) |item| switch (item) {
        .rect => |r| {
            const area: dvui.Rect.Physical = .{ .x = rs.r.x + r.x * k, .y = rs.r.y + r.y * k, .w = r.w * k, .h = r.h * k };
            const corners = dvui.CornerRect.Physical.all(r.radius * k);
            const c = paint(r.style);
            if (c.fill) |fill| area.fill(corners, .{ .color = .{ .color = fill }, .fade = 1.0 });
            area.stroke(corners, .{ .thickness = 1.5 * k, .color = .{ .color = c.line } });
        },
        .line => |l| {
            const a: dvui.Point.Physical = .{ .x = rs.r.x + l.x1 * k, .y = rs.r.y + l.y1 * k };
            const b: dvui.Point.Physical = .{ .x = rs.r.x + l.x2 * k, .y = rs.r.y + l.y2 * k };
            const color = paint(l.style).line;
            const thickness: f32 = (if (l.style.accent) @as(f32, 2.5) else 1.5) * k;
            stroke(&.{ a, b }, thickness, color, false);
            if (l.arrow) {
                const dx = b.x - a.x;
                const dy = b.y - a.y;
                const length = @sqrt(dx * dx + dy * dy);
                if (length > 0) {
                    const ux = dx / length;
                    const uy = dy / length;
                    const head = 9 * k;
                    const back: dvui.Point.Physical = .{ .x = b.x - ux * head, .y = b.y - uy * head };
                    stroke(&.{
                        .{ .x = back.x - uy * head * 0.55, .y = back.y + ux * head * 0.55 },
                        b,
                        .{ .x = back.x + uy * head * 0.55, .y = back.y - ux * head * 0.55 },
                    }, thickness, color, false);
                }
            }
        },
        .text => |t| {
            const base = if (t.style.mono) dvui.Font.theme(.mono) else dvui.Font.theme(.body);
            var font = if (t.style.bold) base.withWeight(.bold) else base;
            font = font.withSize(sizeFor(font, t.size * scale, t.style.mono));
            const size = font.textSize(t.text); // in window units, already scaled
            const left: f32 = t.x * k - switch (t.anchor) {
                .start => 0,
                .middle => size.w * rs.s / 2,
                .end => size.w * rs.s,
            };
            // SVG places text by its baseline; DVUI by its top. The baseline is about 0.8 of a line down.
            const top = t.y * k - size.h * rs.s * 0.78;
            const at: dvui.Point.Physical = .{ .x = rs.r.x + left, .y = rs.r.y + top };
            const color = if (t.style.accent) dvui.themeGet().focus else if (t.style.dim) dvui.themeGet().text.opacity(0.65) else dvui.themeGet().text;
            dvui.renderText(.{ .font = font, .text = t.text, .rs = .{ .r = rs.r, .s = rs.s }, .p = at, .color = color }) catch {};
        },
    };
}

/// The DVUI font size whose lettering matches an SVG `font-size` of `em`. DVUI sizes are not SVG's em
/// (taken as DVUI sizes, labels came out about 40% too wide), so measure a line: in Segoe UI, which the
/// SVG files name, a line is 1.33 em high. The fixed-width font (Consolas) has other line metrics, but each
/// of its characters is 0.55 em wide, so it is matched by width.
fn sizeFor(font: dvui.Font, em: f32, mono: bool) f32 {
    const probe: f32 = 100;
    const m = font.withSize(probe).textSize("M");
    const measured = if (mono) m.w else m.h;
    const wanted: f32 = em * (if (mono) @as(f32, 0.55) else 1.33);
    return if (measured > 0) probe * wanted / measured else em;
}

fn stroke(points: []const dvui.Point.Physical, thickness: f32, color: dvui.Color, closed: bool) void {
    var path: dvui.Path.Builder = .init(dvui.currentWindow().lifo());
    defer path.deinit();
    for (points) |p| path.addPoint(p);
    dvui.Path.stroke(&.{path.build()}, .{ .thickness = thickness, .color = .{ .color = color }, .closed = closed });
}
