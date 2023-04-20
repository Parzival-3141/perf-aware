// + Instruction Decoding on the 8086
// + Decoding Multiple Instructions and Suffixes
// > Opcode Patterns in 8086 Arithmetic

const std = @import("std");
const builtin = @import("builtin");
const log = std.log;

const registers = [2][8][]const u8{
    // W = 0
    .{
        "al",
        "cl",
        "dl",
        "bl",
        "ah",
        "ch",
        "dh",
        "bh",
    },

    // W = 1
    .{
        "ax",
        "cx",
        "dx",
        "bx",
        "sp",
        "bp",
        "si",
        "di",
    },
};

const effective_addresses = [8][]const u8{
    "bx + si",
    "bx + di",
    "bp + si",
    "bp + di",
    "si",
    "di",
    "bp", // also DIRECT ADDRESS!
    "bx",
};

// Could potentially translate every instruction by doing a massive table
// lookup! I wonder how big the final binary would be?
// const OpcodeSpecific = enum(u8) {
//     // Register (to/from) Register/Memory
//     mov_rm8_reg8 = 0x88,
//     mov_rm16_reg16 = 0x89,
//     mov_reg8_rm8 = 0x8A,
//     mov_reg16_rm16 = 0x8B,

//     // Immediate to Register
//     mov_al_immed8 = 0xB0,
//     mov_cl_immed8 = 0xB1,
//     mov_dl_immed8 = 0xB2,
//     mov_bl_immed8 = 0xB3,

//     mov_ah_immed8 = 0xB4,
//     mov_ch_immed8 = 0xB5,
//     mov_dh_immed8 = 0xB6,
//     mov_bh_immed8 = 0xB7,

//     mov_ax_immed16 = 0xB8,
//     mov_cx_immed16 = 0xB9,
//     mov_dx_immed16 = 0xBA,
//     mov_bx_immed16 = 0xBB,

//     mov_sp_immed16 = 0xBC,
//     mov_bp_immed16 = 0xBD,
//     mov_si_immed16 = 0xBE,
//     mov_di_immed16 = 0xBF,

//     opcode_count,
//     _,
// };

const Opcode = enum {
    invalid,
    mov_reg_rm, // Register (to/from) Register/Memory
    mov_reg_immediate, // Immediate to Register

    fn from_byte(byte: u8) Opcode {
        return switch (byte) {
            0x88...0x8B => .mov_reg_rm,
            0xB0...0xBF => .mov_reg_immediate,
            else => .invalid,
        };
    }
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    if (args.len < 2) {
        log.err("sim8086 <filepath>", .{});
        return;
    }

    const file = std.fs.cwd().openFile(args[1], .{}) catch |err| {
        log.err("Unable to open '{s}': {s}", .{ args[1], @errorName(err) });
        return;
    };
    defer file.close();

    var br = FileBitReader.init(file.reader());

    try print("bits 16\n\n", .{});
    while (try read_byte(&br)) |op_byte| {
        switch (Opcode.from_byte(op_byte)) {
            .invalid => {
                log.err("Invalid opcode: '{X}'", .{op_byte});
                return;
            },

            .mov_reg_rm => {
                const d = op_byte & 0b10;
                const w = op_byte & 0b01;

                const byte2 = try read_byte_no_eof(&br);
                const mod = @truncate(u2, byte2 >> 6);
                const reg = @truncate(u3, byte2 >> 3);
                const rm = @truncate(u3, byte2 >> 0);

                if (mod == 0b11) { // register-to-register mode
                    const dst = if (d > 0) reg else rm;
                    const src = if (d > 0) rm else reg;

                    try print("mov {s}, {s}\n", .{ registers[w][dst], registers[w][src] });
                } else {
                    var buf = [_]u8{0} ** 17;
                    const addr_txt = try get_effective_address(&br, mod, rm, &buf);
                    const reg_txt = registers[w][reg];

                    const dst = if (d > 0) reg_txt else addr_txt;
                    const src = if (d > 0) addr_txt else reg_txt;

                    try print("mov {s}, {s}\n", .{ dst, src });
                }
            },

            .mov_reg_immediate => {
                const w = (op_byte >> 3) & 1;
                const reg = op_byte & 0b111;

                if (w > 0) {
                    const lo = try read_byte_no_eof(&br);
                    const hi = try read_byte_no_eof(&br);
                    const data = (@as(u16, hi) << 8) | lo;

                    try print("mov {s}, {d}\n", .{ registers[w][reg], data });
                } else {
                    try print("mov {s}, {d}\n", .{ registers[w][reg], try read_byte_no_eof(&br) });
                }
            },
        }
        // I like this else case
        // switch (@intToEnum(OpcodeSpecific, op_byte)) {
        //     else => |oc| {
        //         if (op_byte < @enumToInt(OpcodeSpecific.opcode_count))
        //             log.err("Unimplemented opcode: '{s}'", .{@tagName(oc)})
        //         else
        //             log.err("Unimplemented opcode: '{X}'\n(See https://edge.edx.org/c4x/BITSPilani/EEE231/asset/8086_family_Users_Manual_1_.pdf)", .{op_byte});
        //         return;
        //     },
        // }
    }
}

fn get_effective_address(br: *FileBitReader, mod: u2, rm: u3, buf: *[17]u8) ![]const u8 {
    const direct_addr = mod == 0b00 and rm == 0b110;
    const has_disp = direct_addr or mod == 0b01 or mod == 0b10;
    const disp_16bit = direct_addr or mod == 0b10;

    if (has_disp) {
        const data = if (disp_16bit)
            // lo | (hi << 8)
            try read_byte_no_eof(br) | (@as(u16, try read_byte_no_eof(br)) << 8)
        else
            try read_byte_no_eof(br);

        if (direct_addr) {
            return std.fmt.bufPrint(buf, "[{d}]", .{data}) catch unreachable;
        } else if (data == 0) {
            return std.fmt.bufPrint(buf, "[{s}]", .{effective_addresses[rm]}) catch unreachable;
        } else {
            return std.fmt.bufPrint(buf, "[{s} + {d}]", .{ effective_addresses[rm], data }) catch unreachable;
        }
    } else {
        return std.fmt.bufPrint(buf, "[{s}]", .{effective_addresses[rm]}) catch unreachable;
    }
}

// const FileBitReader = std.io.BitReader(builtin.cpu.arch.endian(), std.fs.File.Reader);
const FileBitReader = std.io.BitReader(.Big, std.fs.File.Reader);

fn read_byte(br: *FileBitReader) !?u8 {
    return readBits(br, u8);
}

fn read_byte_no_eof(br: *FileBitReader) !u8 {
    return try read_byte(br) orelse error.UnexpectedEndOfStream;
}

/// Reads Bits.size bits from reader, erroring if it reaches the end of file unexpectedly
/// or the reader throws an error.
fn readBits(br: *FileBitReader, comptime Bits: type) !?Bits {
    comptime std.debug.assert(std.meta.trait.isUnsignedInt(Bits));
    const num_bits = @typeInfo(Bits).Int.bits;

    var num_bits_read: usize = undefined;
    const result = try br.readBits(Bits, num_bits, &num_bits_read);

    if (num_bits_read == 0)
        return null
    else if (num_bits_read < num_bits)
        return error.UnexpectedEndOfStream;

    return result;
}

fn print(comptime fmt: []const u8, args: anytype) !void {
    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print(fmt, args);

    try bw.flush(); // don't forget to flush!
}
