const std = @import("std");
const termios = @cImport({
    @cInclude("termios.h");
    @cInclude("unistd.h");
});

const Allocator = std.mem.Allocator;
const print = std.debug.print;

const ft = struct {
    path: []const u8,
    name: []const u8,
    point: u32,
    dis: usize,
};

const at = struct {
    path: []const u8,
    name: []const u8,
};

fn manualSort(array: anytype) void {
    for (array, 0..) |_, i| {
        var minIndex = i;
        for (array[i..], 0..) |b, j| {
            if (b.dis > array[minIndex].dis) {
                minIndex = i + j;
            }
        }
        if (minIndex != i) {
            const temp = array[i];
            array[i] = array[minIndex];
            array[minIndex] = temp;
        }
    }
}

const term_colors = enum {
    const red = "\x1B[31m";
    const green = "\x1B[92m";
    const yellow = "\x1B[33m";
    const blue = "\x1B[34m";
    const magenta = "\x1B[35m";
    const cyan = "\x1B[36m";
    const reset = "\x1B[0m";
    const white = "\x1b[37m";
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa_allocator = gpa.allocator();
    const path: []const u8 = ".";

    const cwd = std.fs.cwd();
    var dir = try cwd.openDir(path, .{ .iterate = true });
    defer dir.close();
    var walk = try dir.walk(allocator);
    defer walk.deinit();

    var filtered_arr = std.ArrayList(ft).init(gpa.allocator());
    defer filtered_arr.deinit();

    var arr = std.ArrayList(at).init(gpa_allocator);
    defer arr.deinit();

    while (try walk.next()) |val| {
        const basename = try gpa_allocator.dupe(u8, val.basename);
        const f_path = try gpa_allocator.dupe(u8, val.path);

        // if (val.path)
        try arr.append(.{ .name = basename, .path = f_path });

        // std.debug.print("reading -> {s}  {s}\n", .{ val.basename, @tagName(val.kind) });
    }

    // try arr.append(.{ .name = "basename", .path = "f_path" });

    var term = termios.termios{};

    // Get the current terminal attributes
    if (termios.tcgetattr(termios.STDIN_FILENO, &term) != 0) {
        std.debug.print("Failed to get terminal attributes.\n", .{});
        return;
    }

    // Set the terminal to raw mode
    var raw = term;
    raw.c_lflag &= ~(@as(c_uint, termios.ICANON) | @as(c_uint, termios.ECHO));

    if (termios.tcsetattr(termios.STDIN_FILENO, termios.TCSANOW, &raw) != 0) {
        std.debug.print("Failed to set terminal to raw mode.\n", .{});
        return;
    }

    defer {
        // Restore the terminal to the previous state
        _ = termios.tcsetattr(termios.STDIN_FILENO, termios.TCSANOW, &term);
    }

    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    var read_buffer: [1]u8 = undefined;
    var input_buffer: [256]u8 = undefined;
    var input_buffer_len: usize = 0;
    var escape = true;
    while (true) {
        escape = false;
        try stdout.print("{s}your command: {s}", .{ term_colors.green, input_buffer[0..input_buffer_len] });
        _ = try stdin.read(&read_buffer);

        if (input_buffer_len < input_buffer.len) {
            const ch = read_buffer[0];
            if (ch == 0x1b) {
                _ = try stdin.read(&read_buffer);
                _ = try stdin.read(&read_buffer);
                _ = try stdin.read(&read_buffer);
                input_buffer_len = 0;
                escape = true;
            } else if (ch == 0x7f) {
                if (input_buffer_len > 0) input_buffer_len -= 1;
                escape = true;
            }
            if (!escape) {
                input_buffer[input_buffer_len] = read_buffer[0];
                input_buffer_len += 1;
            }
        }
        if (std.mem.eql(u8, input_buffer[0..input_buffer_len], ":exit") or std.mem.eql(u8, input_buffer[0..input_buffer_len], ":q")) {
            try stdout.print("\x1B[2K\x1B[G", .{});
            try stdout.print("your command: {s}\n", .{input_buffer[0..input_buffer_len]});
            break;
        }
        try stdout.print("\n", .{});

        // if (std.mem.eql(u8, &input_buffer, ":exit") or std.mem.eql(u8, &input_buffer, ":e")) break;

        const match: []const u8 = input_buffer[0..input_buffer_len];

        for (arr.items) |val| {
            var point: u32 = 0;
            var dis: usize = 0;
            var ord: usize = undefined;
            var fm = false;

            for (match, 0..) |ci, i| {
                var df: usize = 0;
                for (val.name, 0..) |cj, j| {
                    df += 1;
                    if (ci == cj) {
                        if (!fm) {
                            ord = j;
                            fm = true;
                            dis += ord;
                        }

                        if (j < ord + i) {
                            continue;
                        }

                        dis += (j - ord - i);
                        point += 1;
                        break;
                    }
                }
                // else {
                //     dis += 1;
                // }
            }

            // try filtered_arr.append(.{ .path = val, .point = point });
            if (point == 0) continue;
            try filtered_arr.append(.{ .name = val.name, .path = val.path, .point = point, .dis = dis });
        }

        std.mem.sort(ft, filtered_arr.items, {}, ltf);
        std.mem.sort(ft, filtered_arr.items, {}, ltf2);

        for (filtered_arr.items) |val| {
            print("{s}{s} {d} {d} -> {s} \n", .{ term_colors.blue, val.name, val.point, val.dis, "!" });
        }

        filtered_arr.clearAndFree();
    }
}

fn ltf2(a: void, lhs: ft, rhs: ft) bool {
    _ = a;
    return lhs.point < rhs.point;
}

fn ltf(a: void, lhs: ft, rhs: ft) bool {
    _ = a;
    const lf = lhs.dis / lhs.point;
    const rf = rhs.dis / rhs.point;
    return lf > rf;
    // return lhs.dis > rhs.dis;
}

fn check_eqal(a: []const u8, b: []const u8) bool {
    for (b, 0..) |c, i| {
        if (a[i] == c) continue;
        return false;
    }
    return true;
}

fn concat(allocator: Allocator, a: []const u8, b: []const u8) []u8 {
    const result = allocator.alloc(u8, a.len + b.len) catch unreachable;
    @memcpy(result[0..a.len], a);
    @memcpy(result[a.len..], b);
    return result;
}

fn concat_path(allocator: Allocator, a: []const u8, b: []const u8) []u8 {
    const result = allocator.alloc(u8, a.len + b.len) catch unreachable;
    @memcpy(result[0..a.len], a);
    @memcpy(result[a.len..], b);
    return result;
}
