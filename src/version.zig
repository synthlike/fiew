const std = @import("std");
const builtin = @import("builtin");

pub const semantic = "0.1.0";
pub const libvaxis_revision = "c060d314930c5552b99a89278a6a695baf0352da";
pub const tree_sitter_version = "0.26.13";
pub const tree_sitter_revision = "d97971e24500218865c05ed1febdee2acf41bae1";
pub const tree_sitter_zig_revision = "6479aa13f32f701c383083d8b28360ebd682fb7d";
pub const tree_sitter_markdown_revision = "a0a00f817d02412bd92c54d316f164d827b57b5c";

pub fn write(writer: *std.Io.Writer) !void {
    try writer.print(
        \\skaut {s}
        \\zig {s}
        \\libvaxis {s}
        \\tree-sitter {s} ({s})
        \\tree-sitter-zig {s}
        \\tree-sitter-markdown {s}
        \\
    , .{
        semantic,
        builtin.zig_version_string,
        libvaxis_revision,
        tree_sitter_version,
        tree_sitter_revision,
        tree_sitter_zig_revision,
        tree_sitter_markdown_revision,
    });
}

test "release version and dependency revisions are inspectable" {
    try std.testing.expectEqualStrings("0.1.0", semantic);
    try std.testing.expectEqual(@as(usize, 40), libvaxis_revision.len);
    try std.testing.expectEqual(@as(usize, 40), tree_sitter_revision.len);
    try std.testing.expectEqual(@as(usize, 40), tree_sitter_zig_revision.len);
    try std.testing.expectEqual(@as(usize, 40), tree_sitter_markdown_revision.len);
}
