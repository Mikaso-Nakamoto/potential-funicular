#requires -Version 5.1
# Local procedural intro. No file, credential, process or network access from the renderer.
function Show-VicAIntro {
    param([ValidateSet('eye','archive')][string]$Style = 'eye', [ValidateSet('ru','en')][string]$Language = 'ru')
    if (-not ('VicAAscii.Intro' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
namespace VicAAscii {
    public static class Intro {
        [StructLayout(LayoutKind.Explicit, CharSet = CharSet.Unicode, Size = 4)]
        private struct Cell {
            [FieldOffset(0)] public char Character;
            [FieldOffset(2)] public ushort Attributes;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct Coord {
            public short X, Y;
            public Coord(short x, short y) { X = x; Y = y; }
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct Rect { public short Left, Top, Right, Bottom; }
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr GetStdHandle(int kind);
        [DllImport("kernel32.dll", EntryPoint = "WriteConsoleOutputW", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool WriteCells(IntPtr handle, [In] Cell[] cells, Coord size, Coord start, ref Rect region);
        private static double Clamp(double v) { return Math.Max(0, Math.Min(1, v)); }
        private static double Smooth(double v) { v = Clamp(v); return v * v * (3 - 2 * v); }
        private static double Hash(int x, int y) {
            unchecked {
                uint n = (uint)(x * 374761393 + y * 668265263 + 911);
                n = (n ^ (n >> 13)) * 1274126177u;
                return (n ^ (n >> 16)) / (double)UInt32.MaxValue;
            }
        }
        private static void Text(Cell[] cells, int w, int h, int row, string text, ushort color) {
            if (row < 0 || row >= h) return;
            int left = Math.Max(0, (w - text.Length) / 2);
            for (int k = 0; k < text.Length && left + k < w; k++) {
                cells[row * w + left + k].Character = text[k];
                cells[row * w + left + k].Attributes = color;
            }
        }
        private static void Archive(Cell[] cells, int w, int h, double t, bool russian) {
            for (int k = 0; k < cells.Length; k++) { cells[k].Character = ' '; cells[k].Attributes = 0; }
            string[] emblem = h >= 29 ? new string[] {
                @"               +               ",
                @"              /A\              ",
                @"          ___/===\___          ",
                @"       .-'  VIC-A    '-.       ",
                @"    ( /   .---------.   \ )    ",
                @"   ((|   /  \   /  \   |))   ",
                @"  (((|  |    \ /    |  |)))  ",
                @"   ((|  |     V     |  |))   ",
                @"    (|   \   /A\   /   |)    ",
                @"     \    '-------'    /     ",
                @"      '._  / / \ \  _.'      ",
                @"         '=------='          "
            } : new string[] {
                @"           +           ",
                @"       ___/A\___       ",
                @"    ( /  VIC-A  \ )    ",
                @"   ((|   \ /    |))   ",
                @"   ((|    V     |))   ",
                @"    ( \_______/ )     ",
                @"       '=---='         "
            };
            int top = Math.Max(1, (h - emblem.Length - 8) / 2);
            int scan = (int)(t * 6) % Math.Max(1, emblem.Length);
            for (int row = 0; row < emblem.Length; row++) {
                string line = emblem[row];
                if (t < 1.5 && row > t / 1.5 * emblem.Length) line = " . : .  . : . ";
                Text(cells, w, h, top + row, line, (ushort)(row == scan ? 15 : row % 3 == 0 ? 14 : 6));
            }
            string[] labels = russian ? new string[] {
                "СИСТЕМА: VIC-A / ПОРТАТИВНЫЙ ТЕРМИНАЛ",
                "УЗЕЛ: ЛИЧНОЕ РАБОЧЕЕ ПРОСТРАНСТВО",
                "ДАТА: " + DateTime.Now.ToString("dd.MM.yyyy"),
                "РЕЖИМ: ИНИЦИАЛИЗАЦИЯ ОБОЛОЧКИ",
                "ПЕРЕХОД В ЦЕНТР УПРАВЛЕНИЯ..."
            } : new string[] {
                "SYSTEM: VIC-A / PORTABLE TERMINAL",
                "NODE: PERSONAL WORKSPACE",
                "DATE: " + DateTime.Now.ToString("yyyy-MM-dd"),
                "MODE: SHELL INITIALIZATION",
                "OPENING CONTROL ROOM..."
            };
            for (int row = 0; row < labels.Length; row++) {
                int count = (int)Math.Max(0, (t - 1.5 - row * 1.05) * 42);
                count = Math.Min(labels[row].Length, count);
                string line = labels[row].Substring(0, count);
                if (count < labels[row].Length && t > 1.5 + row * 1.05) line += "_";
                Text(cells, w, h, top + emblem.Length + 1 + row, line, (ushort)(row == 4 ? 15 : 14));
            }
            Text(cells, w, h, h - 2, russian ? "ЗАСТАВКА / НЕ ОТЧЁТ О БЕЗОПАСНОСТИ / КЛАВИША: ПРОПУСТИТЬ" : "INTRO / NOT A SECURITY REPORT / ANY KEY TO SKIP", 8);
        }
        private static void EmptyStar(Cell[] cells, int w, int h, int x, int y, char glyph, ushort color) {
            if (x < 0 || y < 0 || x >= w || y >= h) return;
            int index = y * w + x;
            if (cells[index].Character == ' ') { cells[index].Character = glyph; cells[index].Attributes = color; }
        }
        private static void Eye(Cell[] cells, int w, int h, double t, bool russian) {
            // Full-field text texture, white sclera, amber iris and a separately dilating pupil.
            // The final starfield is revealed by the pupil; it is not a dissolving torus.
            string glyphs = "0123456789/\\()[]{}<>!|iltrjfxvcnuzXYMW@#";
            double opening = Smooth((t - .7) / 2.1);
            double lid = opening;
            foreach (double blink in new double[] { 6.4, 10.8 }) {
                double distance = Math.Abs(t - blink);
                if (distance < .70) lid *= Smooth(distance / .70);
            }
            double dilation = Smooth((t - 14.2) / 8.5);
            double finish = Smooth((t - 28.4) / 1.2);
            double pupil = .22 + 2.05 * dilation;
            double gaze = .035 * Math.Sin(t * .5) * (1 - dilation);
            double entry = Smooth(t / .7);
            for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
                int index = y * w + x;
                cells[index].Character = ' '; cells[index].Attributes = 0;
                double px = (x - (w - 1) * .5) / (w * .48);
                double py = (y - (h - 1) * .48) / (h * .49);
                double radius = Math.Sqrt(Math.Pow((px - gaze) * 1.30, 2) + py * py);
                double angle = Math.Atan2(py, (px - gaze) * 1.30);
                double noise = Hash(x + (int)(t * 9), y);
                double stripe = .74 + .26 * Math.Sin(y * 3.02 + px * 1.7 + t * .4);
                double aperture = Math.Pow(Math.Max(0, 1 - px * px), .62) * .69 * lid + 2.5 * dilation;
                bool insideLid = Math.Abs(py) < aperture && Math.Abs(px) < 1 + dilation;
                bool inPupil = insideLid && radius < pupil;
                double intensity = .12 + .23 * noise;
                ushort color = 6;
                if (insideLid) {
                    if (radius > .64 + 1.45 * dilation) {
                        intensity = (.72 + .28 * noise) * stripe;
                        color = (ushort)(stripe > .66 ? 15 : 7);
                    } else {
                        double radial = .54 + .27 * Math.Sin(angle * 33 + radius * 21 - t * .5)
                                              + .12 * Math.Sin(angle * 77 - radius * 12 + t * .8);
                        intensity = Clamp((.48 + .44 * radial) * stripe);
                        color = (ushort)(intensity > .78 ? 15 : intensity > .35 ? 14 : 6);
                        if (radius > .61 + 1.45 * dilation) { color = 8; intensity *= .40; }
                    }
                    if (inPupil) { intensity = 0; color = 0; }
                } else {
                    // Upper/lower lids remain a dense moving copper text field, as in the reference.
                    double crease = Math.Exp(-Math.Pow((Math.Abs(py) - aperture - .08) / .07, 2));
                    intensity = Clamp(intensity * stripe + crease * .18);
                    if (noise < .20) color = 8;
                    if (Math.Abs(py) < .032 && lid < .1) { color = 8; intensity *= .12; }
                }
                // A soft small pink sphere lives inside the expanding dark pupil.
                if (inPupil && dilation > .12) {
                    double sr = Math.Sqrt(Math.Pow(px / .23, 2) + Math.Pow(py / .34, 2));
                    if (sr < 1) {
                        intensity = Math.Sqrt(1 - sr * sr) * (.65 + .35 * Math.Sin(y * 3.02 + t * .4));
                        intensity *= Smooth((dilation - .12) / .40);
                        color = (ushort)(intensity > .55 ? 15 : intensity > .20 ? 13 : 12);
                    }
                }
                intensity *= entry * (1 - finish);
                if (intensity > .045) {
                    int k = (int)((x * 7 + y * 11 + (int)(t * 8) + noise * 13) % glyphs.Length);
                    cells[index].Character = intensity < .15 ? ".,:;"[k % 4] : glyphs[k];
                    cells[index].Attributes = color;
                }
            }
            // Separate second pass preserves all four arms of a star instead of overwriting them.
            for (int y = 2; y < h - 3; y++) for (int x = 2; x < w - 2; x++) {
                int index = y * w + x;
                double seed = Hash(x * 3, y * 5);
                if (seed < .984 || cells[index].Character != ' ') continue;
                double px = (x - (w - 1) * .5) / (w * .48);
                double py = (y - (h - 1) * .48) / (h * .49);
                double radius = Math.Sqrt(Math.Pow((px - gaze) * 1.30, 2) + py * py);
                if (radius > pupil || dilation < .15 || finish > .8) continue;
                double pulse = .5 + .5 * Math.Sin(t * .9 + seed * 400);
                EmptyStar(cells, w, h, x, y, pulse > .78 ? '+' : '.', (ushort)(pulse > .55 ? 15 : 8));
                if (pulse > .74 && seed > .988) {
                    EmptyStar(cells, w, h, x - 1, y, '-', 7); EmptyStar(cells, w, h, x + 1, y, '-', 7);
                    EmptyStar(cells, w, h, x, y - 1, '|', 8); EmptyStar(cells, w, h, x, y + 1, '|', 8);
                    EmptyStar(cells, w, h, x - 2, y, '.', 8); EmptyStar(cells, w, h, x + 2, y, '.', 8);
                    EmptyStar(cells, w, h, x, y - 2, '.', 8); EmptyStar(cells, w, h, x, y + 2, '.', 8);
                }
            }
            if (finish > .65) {
                Text(cells, w, h, h / 2 - 1, "V  I  C  -  A", 15);
                Text(cells, w, h, h / 2 + 1, russian ? "ЛИЧНОЕ РАБОЧЕЕ ПРОСТРАНСТВО" : "PERSONAL WORKSPACE", 13);
            }
        }
        public static int[] EyeSnapshot(int w, int h, double time) {
            if (w < 40 || w > 160 || h < 16 || h > 60 || Double.IsNaN(time) || time < 0 || time > 30)
                throw new ArgumentOutOfRangeException();
            Cell[] cells = new Cell[w * h];
            Eye(cells, w, h, time, false);
            int[] packed = new int[cells.Length];
            for (int k = 0; k < cells.Length; k++) packed[k] = cells[k].Character | (cells[k].Attributes << 16);
            return packed;
        }
        public static bool Play(double seconds, int style, bool russian) {
            if (Console.IsOutputRedirected || Console.IsInputRedirected) return false;
            IntPtr handle = GetStdHandle(-11);
            if (handle == IntPtr.Zero || handle == new IntPtr(-1)) return false;
            Stopwatch clock = Stopwatch.StartNew();
            while (clock.Elapsed.TotalSeconds < seconds) {
                if (Console.KeyAvailable) { Console.ReadKey(true); return true; }
                int w = Math.Min(120, Console.WindowWidth);
                int h = Math.Min(38, Console.WindowHeight - 1);
                if (w < 40 || h < 16) return false;
                Cell[] cells = new Cell[w * h];
                double t = clock.Elapsed.TotalSeconds;
                if (style == 1) { Archive(cells, w, h, t, russian); }
                else { Eye(cells, w, h, t, russian); }
                Rect region = new Rect {
                    Left = (short)Console.WindowLeft, Top = (short)Console.WindowTop,
                    Right = (short)(Console.WindowLeft + w - 1), Bottom = (short)(Console.WindowTop + h - 1)
                };
                if (!WriteCells(handle, cells, new Coord((short)w, (short)h), new Coord(0, 0), ref region)) return false;
                Thread.Sleep(40);
            }
            return true;
        }
    }
}
'@ -ErrorAction Stop
    }
    $styleId = 0; if ($Style -eq 'archive') { $styleId = 1 }
    $duration = 30.0; if ($Style -eq 'archive') { $duration = 9.5 }
    $null = [VicAAscii.Intro]::Play($duration, $styleId, ($Language -eq 'ru'))
}
