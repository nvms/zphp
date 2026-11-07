// writes the module that names zphp's compile cache directory: a hash of the
// compiler's sources, so bytecode cached by one compiler is never read by
// another. the build runs it with the output path, then every source file
//
//   compiler_hash <out.zig> <file>...

const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) return error.MissingOutputPath;
    var hasher = std.hash.Wyhash.init(0);
    for (args[2..]) |path| {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, path, init.gpa, .limited(1 << 26));
        defer init.gpa.free(bytes);
        hasher.update(std.fs.path.basename(path));
        hasher.update(bytes);
    }
    const source = try std.fmt.allocPrint(init.gpa, "pub const compiler_hash = \"{x:0>16}\";\n", .{hasher.final()});
    defer init.gpa.free(source);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[1], .data = source });
}
