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
        public static bool Play(double seconds, int style, bool russian) {
            if (Console.IsOutputRedirected || Console.IsInputRedirected) return false;
            IntPtr handle = GetStdHandle(-11);
            if (handle == IntPtr.Zero || handle == new IntPtr(-1)) return false;
            Stopwatch clock = Stopwatch.StartNew();
            string ramp = ".,:;irsXA253hMHGS#9B&@";
            while (clock.Elapsed.TotalSeconds < seconds) {
                if (Console.KeyAvailable) { Console.ReadKey(true); return true; }
                int w = Math.Min(120, Console.WindowWidth);
                int h = Math.Min(38, Console.WindowHeight - 1);
                if (w < 40 || h < 16) return false;
                Cell[] cells = new Cell[w * h];
                double t = clock.Elapsed.TotalSeconds;
                if (style == 1) { Archive(cells, w, h, t, russian); }
                else {
                double morph = Smooth((t - 6.6) / 1.0);
                double reveal = Smooth((t - 8.0) / 1.1);
                double opening = Smooth(t / 1.0);
                double eyelid = opening;
                foreach (double blink in new double[] { 2.8, 5.2 }) {
                    double d = Math.Abs(t - blink);
                    if (d < .48) eyelid *= Smooth(d / .48);
                }
                double scale = Math.Min(w / 96.0, h / 30.0);
                for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
                    int index = y * w + x;
                    cells[index].Character = ' ';
                    cells[index].Attributes = 0;
                    double px = (x - (w - 1) * .5) / (29.0 * scale);
                    double py = (y - (h - 1) * .46) / (12.0 * scale);
                    double r = Math.Sqrt(px * px + py * py);
                    double a = Math.Atan2(py, px);
                    double swirl = .78 + .22 * Math.Sin(a * 8 - t * 2.7 + r * 21);
                    double band = .76 + .24 * Math.Sin(y * 3.05 + t * 2.1 + px * 1.6);
                    double ring = Math.Exp(-Math.Pow((r - .94) / .20, 2)) * swirl * band;
                    double photon = Math.Exp(-Math.Pow((r - .76) / .034, 2)) * .90;
                    double diskR = Math.Sqrt(px * px + Math.Pow(py * 2.7, 2));
                    double disk = Math.Exp(-Math.Pow((diskR - 1.02) / .42, 2)) * .46 * band;
                    if (r < .68) disk *= .03;
                    double halo = Math.Exp(-Math.Pow((r - 1.1) / .57, 2)) * .16;
                    double gold = Math.Max(photon, ring) + disk + halo;
                    if (r < .65) gold *= .025;
                    double sphereR = Math.Sqrt(Math.Pow(px / .46, 2) + Math.Pow(py / .56, 2));
                    double sphere = 0;
                    if (sphereR < 1) sphere = Math.Sqrt(1 - sphereR * sphereR) * (.65 + .35 * Math.Sin(y * 3.05 + t * 1.6));
                    sphere += Math.Exp(-Math.Pow((sphereR - 1) / .18, 2)) * .24;
                    double light = Clamp(((1 - morph) * gold + morph * sphere) * opening * (1 - reveal));
                    double aperture = Math.Max(0, 1 - px * px / 2.1) * .98 * eyelid;
                    if (Math.Abs(py) > aperture) light *= .01;
                    else if (Math.Abs(Math.Abs(py) - aperture) < .055 && Math.Abs(px) < 1.44)
                        light = Math.Max(light, .48 * (1 - reveal));
                    double noise = Hash(x + (int)(t * 7), y);
                    light *= .80 + .20 * noise;
                    if (light > .045) {
                        int level = Math.Min(ramp.Length - 1, (int)(light * ramp.Length));
                        cells[index].Character = ramp[level];
                        ushort color;
                        if (morph < .55) color = (ushort)(light > .72 ? 15 : light > .38 ? 14 : light > .18 ? 6 : 8);
                        else color = (ushort)(light > .68 ? 15 : light > .34 ? 13 : light > .13 ? 12 : 4);
                        cells[index].Attributes = color;
                    }
                    double star = Hash(x, y);
                    if (star > .993 && light < .10 && opening > .4) {
                        double pulse = .5 + .5 * Math.Sin(t * 1.4 + star * 300);
                        cells[index].Character = pulse > .82 ? '+' : pulse > .4 ? '*' : '.';
                        cells[index].Attributes = (ushort)(pulse > .65 ? 15 : 8);
                        if (pulse > .87 && x > 1 && x < w - 2 && y > 1 && y < h - 4) {
                            cells[index - 1].Character = '-'; cells[index - 1].Attributes = 8;
                            cells[index + 1].Character = '-'; cells[index + 1].Attributes = 8;
                            cells[index - w].Character = '|'; cells[index - w].Attributes = 8;
                            cells[index + w].Character = '|'; cells[index + w].Attributes = 8;
                        }
                    }
                }
                Text(cells, w, h, h - 2, (russian ? "VIC-A / ЛЮБАЯ КЛАВИША: ПРОПУСТИТЬ" : "VIC-A / ANY KEY TO SKIP"), 8);
                if (reveal > .45) {
                    Text(cells, w, h, h / 2 - 1, "V  I  C  -  A", 15);
                    Text(cells, w, h, h / 2 + 1, "P O R T A B L E   W O R K S P A C E", 13);
                }
                }
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
    $null = [VicAAscii.Intro]::Play(9.5, $styleId, ($Language -eq 'ru'))
}
