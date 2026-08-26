/// Fiew-owned boundary for Unicode grapheme segmentation and terminal-cell width.
pub const Segmenter = struct {
    context: ?*const anyopaque = null,
    next_fn: *const fn (?*const anyopaque, []const u8, usize) usize,
    width_fn: *const fn (?*const anyopaque, []const u8) u16,

    pub fn next(self: Segmenter, text: []const u8, start: usize) usize {
        return self.next_fn(self.context, text, start);
    }

    pub fn width(self: Segmenter, grapheme: []const u8) u16 {
        return self.width_fn(self.context, grapheme);
    }
};
