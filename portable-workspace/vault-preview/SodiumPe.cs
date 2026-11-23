using System;
using System.Collections.Generic;
using System.Text;
namespace VicAReview {
    // Bounded, non-executing PE32+ import inspection. No LoadLibrary is used.
    public static class SodiumPe {
        private static void Need(byte[] b, long at, long count) {
            if (at < 0 || count < 0 || at > b.LongLength - count) throw new FormatException("PE range outside file.");
        }
        private static uint U32(byte[] b, long at) { Need(b, at, 4); return BitConverter.ToUInt32(b, (int)at); }
        private static ushort U16(byte[] b, long at) { Need(b, at, 2); return BitConverter.ToUInt16(b, (int)at); }
        private static long Map(byte[] b, uint rva, long table, int count, uint headers) {
            if (rva < headers) { Need(b, rva, 1); return rva; }
            for (int i = 0; i < count; i++) {
                long s = table + i * 40L;
                uint start = U32(b, s + 12), rawSize = U32(b, s + 16), raw = U32(b, s + 20);
                if ((ulong)rva >= start && (ulong)rva - start < rawSize) {
                    long offset = raw + ((long)rva - start); Need(b, offset, 1); return offset;
                }
            }
            throw new FormatException("Unmapped import RVA.");
        }
        public static string[] Imports(byte[] b) {
            if (b == null || b.Length < 256 || b.Length > 16777216 || U16(b, 0) != 0x5a4d) throw new FormatException("Invalid PE size/magic.");
            long pe = U32(b, 60); Need(b, pe, 24);
            if (U32(b, pe) != 0x4550 || U16(b, pe + 4) != 0x8664) throw new FormatException("AMD64 PE required.");
            int sections = U16(b, pe + 6), optionalSize = U16(b, pe + 20);
            long optional = pe + 24, table = optional + optionalSize;
            Need(b, optional, optionalSize); Need(b, table, sections * 40L);
            if (sections < 1 || sections > 96 || optionalSize < 240 || U16(b, optional) != 0x20b || U32(b, optional + 108) < 16)
                throw new FormatException("Unsupported PE32+ layout.");
            // Refuse delay imports rather than silently skipping a dependency category.
            if (U32(b, optional + 112 + 13 * 8) != 0 || U32(b, optional + 116 + 13 * 8) != 0)
                throw new FormatException("Delay imports need separate review.");
            uint headers = U32(b, optional + 60), rva = U32(b, optional + 120), size = U32(b, optional + 124);
            if (rva == 0 || size < 20 || size > 65536) throw new FormatException("Invalid import directory.");
            var names = new List<string>();
            for (uint index = 0; index + 20 <= size; index += 20) {
                ulong descriptor = (ulong)rva + index;
                if (descriptor > UInt32.MaxValue) throw new FormatException("Import overflow.");
                long at = Map(b, (uint)descriptor, table, sections, headers); Need(b, at, 20);
                bool zero = true;
                for (int i = 0; i < 20; i++) if (b[at + i] != 0) { zero = false; break; }
                if (zero) {
                    if (names.Count == 0) throw new FormatException("Empty imports.");
                    return names.ToArray();
                }
                uint nameRva = U32(b, at + 12);
                var name = new StringBuilder();
                bool ended = false;
                for (uint n = 0; n < 128; n++) {
                    if ((ulong)nameRva + n > UInt32.MaxValue) throw new FormatException("Name overflow.");
                    byte c = b[Map(b, nameRva + n, table, sections, headers)];
                    if (c == 0) { ended = true; break; }
                    if (c < 33 || c > 126) throw new FormatException("Invalid import name.");
                    name.Append((char)c);
                }
                if (!ended || name.Length == 0) throw new FormatException("Unterminated import name.");
                names.Add(name.ToString().ToLowerInvariant());
                if (names.Count > 128) throw new FormatException("Too many imports.");
            }
            throw new FormatException("Import table lacks terminator.");
        }
    }
}
