using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace VibeGaming.UnrealEvaluation
{
    public sealed class UnrealEvaluationSessionHandle
    {
        public UnrealEvaluationSessionHandle(
            string sessionId,
            int processId,
            string windowHandleToken,
            string processToken)
        {
            SessionId = sessionId;
            ProcessId = processId;
            WindowHandleToken = windowHandleToken;
            ProcessToken = processToken;
        }

        public string SessionId { get; private set; }
        public int ProcessId { get; private set; }
        public string WindowHandleToken { get; private set; }
        public string ProcessToken { get; private set; }

        public override string ToString()
        {
            return SessionId;
        }
    }

    public sealed class WindowSnapshot
    {
        public IntPtr Handle { get; internal set; }
        public uint ProcessId { get; internal set; }
        public int ClientLeft { get; internal set; }
        public int ClientTop { get; internal set; }
        public int ClientWidth { get; internal set; }
        public int ClientHeight { get; internal set; }
        public bool IsForeground { get; internal set; }
        public bool IsVisible { get; internal set; }
        public bool IsMinimized { get; internal set; }
        public uint Dpi { get; internal set; }
        public string CoordinateSpace { get; internal set; }
    }

    public sealed class ControlledInputState
    {
        public ushort[] KeysDown { get; internal set; }
        public string[] MouseButtonsDown { get; internal set; }
        public bool AnyDown { get; internal set; }
    }

    public sealed class ClientCaptureFrame
    {
        public WindowSnapshot Snapshot { get; internal set; }
        public byte[] Bgra32 { get; internal set; }
        public int Stride { get; internal set; }
        public int ExposureSampleCount { get; internal set; }
        public string ExposureAssurance { get; internal set; }
    }

    public static class WindowsEvaluationNative
    {
        public const string InteropVersion = "1.1.0";

        private const uint WM_CLOSE = 0x0010;
        private const uint GW_OWNER = 4;
        private const uint GA_ROOT = 2;
        private const int SW_RESTORE = 9;
        private const uint SWP_NOSIZE = 0x0001;
        private const uint SWP_NOMOVE = 0x0002;
        private const uint SWP_SHOWWINDOW = 0x0040;
        private static readonly IntPtr HWND_TOP = IntPtr.Zero;

        private const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000;
        private const int JobObjectBasicAccountingInformation = 1;
        private const int JobObjectExtendedLimitInformation = 9;

        private const uint INPUT_MOUSE = 0;
        private const uint INPUT_KEYBOARD = 1;
        private const uint KEYEVENTF_EXTENDEDKEY = 0x0001;
        private const uint KEYEVENTF_KEYUP = 0x0002;
        private const uint KEYEVENTF_SCANCODE = 0x0008;
        private const uint MAPVK_VK_TO_VSC = 0;

        private const uint MOUSEEVENTF_MOVE = 0x0001;
        private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
        private const uint MOUSEEVENTF_LEFTUP = 0x0004;
        private const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
        private const uint MOUSEEVENTF_RIGHTUP = 0x0010;
        private const uint MOUSEEVENTF_MIDDLEDOWN = 0x0020;
        private const uint MOUSEEVENTF_MIDDLEUP = 0x0040;
        private const uint MOUSEEVENTF_XDOWN = 0x0080;
        private const uint MOUSEEVENTF_XUP = 0x0100;
        private const uint MOUSEEVENTF_VIRTUALDESK = 0x4000;
        private const uint MOUSEEVENTF_ABSOLUTE = 0x8000;
        private const uint XBUTTON1 = 0x0001;
        private const uint XBUTTON2 = 0x0002;

        private const int SM_XVIRTUALSCREEN = 76;
        private const int SM_YVIRTUALSCREEN = 77;
        private const int SM_CXVIRTUALSCREEN = 78;
        private const int SM_CYVIRTUALSCREEN = 79;
        private const int DWMWA_CLOAKED = 14;
        private static readonly IntPtr DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = new IntPtr(-4);
        private static readonly UIntPtr EXECUTOR_INPUT_MARKER = new UIntPtr(0x56474245u);
        private static readonly ushort[] CONTROLLED_VIRTUAL_KEYS = BuildControlledVirtualKeys();
        private const int INPUT_WATCHDOG_INTERVAL_MS = 25;
        private static readonly object InputWatchdogSync = new object();
        private static readonly Dictionary<ushort, bool> InputWatchdogKeys =
            new Dictionary<ushort, bool>();
        private static readonly HashSet<string> InputWatchdogMouseButtons =
            new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        private static Timer inputWatchdogTimer;
        private static IntPtr inputWatchdogWindow = IntPtr.Zero;
        private static uint inputWatchdogProcessId;
        private static bool inputWatchdogFaulted;
        private static string inputWatchdogFaultCode = "OK";
        private static int inputWatchdogNativeError;
        private static int inputWatchdogCallbackRunning;
        private static long inputWatchdogGeneration;

        private const uint CREATE_SUSPENDED = 0x00000004;
        private const uint WAIT_OBJECT_0 = 0x00000000;
        private const uint WAIT_TIMEOUT = 0x00000102;
        private const uint INFINITE = 0xFFFFFFFF;
        private const uint SRCCOPY = 0x00CC0020;
        private const uint CAPTUREBLT = 0x40000000;
        private const uint DIB_RGB_COLORS = 0;
        private const int BI_RGB = 0;

        private const int VK_LBUTTON = 0x01;
        private const int VK_RBUTTON = 0x02;
        private const int VK_MBUTTON = 0x04;
        private const int VK_XBUTTON1 = 0x05;
        private const int VK_XBUTTON2 = 0x06;

        private delegate bool EnumWindowsProc(IntPtr window, IntPtr parameter);

        private static ushort[] BuildControlledVirtualKeys()
        {
            List<ushort> keys = new List<ushort>(new ushort[]
            {
                0x08, 0x09, 0x0D, 0x10, 0x11, 0x12, 0x13, 0x14, 0x1B, 0x20,
                0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x2D, 0x2E,
                0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5
            });
            for (ushort key = 0x30; key <= 0x39; key++)
            {
                keys.Add(key);
            }

            for (ushort key = 0x41; key <= 0x5A; key++)
            {
                keys.Add(key);
            }

            for (ushort key = 0x70; key <= 0x87; key++)
            {
                keys.Add(key);
            }

            return keys.ToArray();
        }

        private static bool BindInputWatchdogSessionLocked(
            IntPtr window,
            uint expectedProcessId,
            bool rejectLatchedFault,
            out string validationCode,
            out int nativeError)
        {
            validationCode = "OK";
            nativeError = 0;
            if (window == IntPtr.Zero || expectedProcessId == 0)
            {
                validationCode = "INPUT_WATCHDOG_BINDING_INVALID";
                nativeError = 87;
                return false;
            }

            if (inputWatchdogWindow == IntPtr.Zero)
            {
                inputWatchdogWindow = window;
                inputWatchdogProcessId = expectedProcessId;
            }
            else if (inputWatchdogWindow != window ||
                     inputWatchdogProcessId != expectedProcessId)
            {
                validationCode = "INPUT_WATCHDOG_SESSION_MISMATCH";
                return false;
            }

            if (rejectLatchedFault && inputWatchdogFaulted)
            {
                validationCode = inputWatchdogFaultCode;
                nativeError = inputWatchdogNativeError;
                return false;
            }

            return true;
        }

        private static void EnsureInputWatchdogTimerLocked()
        {
            if (inputWatchdogTimer == null &&
                (InputWatchdogKeys.Count > 0 || InputWatchdogMouseButtons.Count > 0))
            {
                long generation = ++inputWatchdogGeneration;
                inputWatchdogTimer = new Timer(
                    InputWatchdogTick,
                    generation,
                    INPUT_WATCHDOG_INTERVAL_MS,
                    INPUT_WATCHDOG_INTERVAL_MS);
            }
        }

        private static void StopInputWatchdogTimerLocked()
        {
            Timer timer = inputWatchdogTimer;
            inputWatchdogTimer = null;
            ++inputWatchdogGeneration;
            if (timer != null)
            {
                timer.Dispose();
            }
        }

        private static void LatchInputWatchdogFaultLocked(string faultCode, int nativeError)
        {
            if (inputWatchdogFaulted)
            {
                return;
            }

            inputWatchdogFaulted = true;
            inputWatchdogFaultCode = string.IsNullOrEmpty(faultCode)
                ? "INPUT_WATCHDOG_VALIDATION_FAILED"
                : faultCode;
            inputWatchdogNativeError = nativeError;
        }

        private static bool ReleaseInputWatchdogEdgesLocked(out int firstReleaseError)
        {
            firstReleaseError = 0;
            foreach (KeyValuePair<ushort, bool> key in
                     new List<KeyValuePair<ushort, bool>>(InputWatchdogKeys))
            {
                int releaseError;
                if (SendKeyboardCore(key.Key, true, key.Value, out releaseError))
                {
                    InputWatchdogKeys.Remove(key.Key);
                }
                else if (firstReleaseError == 0)
                {
                    firstReleaseError = releaseError;
                }
            }

            foreach (string button in new List<string>(InputWatchdogMouseButtons))
            {
                int releaseError;
                if (SendMouseButtonCore(button, true, out releaseError))
                {
                    InputWatchdogMouseButtons.Remove(button);
                }
                else if (firstReleaseError == 0)
                {
                    firstReleaseError = releaseError;
                }
            }

            bool allReleased = InputWatchdogKeys.Count == 0 &&
                               InputWatchdogMouseButtons.Count == 0;
            if (allReleased)
            {
                StopInputWatchdogTimerLocked();
            }
            else
            {
                inputWatchdogFaulted = true;
                inputWatchdogFaultCode = "INPUT_WATCHDOG_RELEASE_FAILED";
                inputWatchdogNativeError = firstReleaseError;
                EnsureInputWatchdogTimerLocked();
            }

            return allReleased;
        }

        private static void InputWatchdogTick(object state)
        {
            if (Interlocked.Exchange(ref inputWatchdogCallbackRunning, 1) != 0)
            {
                return;
            }

            try
            {
                lock (InputWatchdogSync)
                {
                    long callbackGeneration = state is long ? (long)state : -1;
                    if (inputWatchdogTimer == null ||
                        callbackGeneration != inputWatchdogGeneration)
                    {
                        return;
                    }

                    if (InputWatchdogKeys.Count == 0 &&
                        InputWatchdogMouseButtons.Count == 0)
                    {
                        StopInputWatchdogTimerLocked();
                        return;
                    }

                    WindowSnapshot snapshot;
                    string validationCode;
                    int nativeError;
                    bool bindingValid = TryGetWindowSnapshot(
                        inputWatchdogWindow,
                        inputWatchdogProcessId,
                        true,
                        out snapshot,
                        out validationCode,
                        out nativeError);
                    if (bindingValid)
                    {
                        return;
                    }

                    LatchInputWatchdogFaultLocked(validationCode, nativeError);
                    int releaseError;
                    ReleaseInputWatchdogEdgesLocked(out releaseError);
                }
            }
            catch
            {
                lock (InputWatchdogSync)
                {
                    long callbackGeneration = state is long ? (long)state : -1;
                    if (inputWatchdogTimer == null ||
                        callbackGeneration != inputWatchdogGeneration)
                    {
                        return;
                    }
                    LatchInputWatchdogFaultLocked("INPUT_WATCHDOG_CALLBACK_FAILED", 0);
                    int releaseError;
                    ReleaseInputWatchdogEdgesLocked(out releaseError);
                }
            }
            finally
            {
                Interlocked.Exchange(ref inputWatchdogCallbackRunning, 0);
            }
        }

        private static bool SendKeyboardWatchdogBound(
            IntPtr window,
            uint expectedProcessId,
            ushort virtualKey,
            bool keyUp,
            bool extended,
            out bool inputDispatched,
            out string validationCode,
            out int nativeError)
        {
            inputDispatched = false;
            lock (InputWatchdogSync)
            {
                if (!BindInputWatchdogSessionLocked(
                        window,
                        expectedProcessId,
                        !keyUp,
                        out validationCode,
                        out nativeError))
                {
                    return false;
                }

                if (!SendKeyboardCore(virtualKey, keyUp, extended, out nativeError))
                {
                    validationCode = "KEYBOARD_SEND_FAILED";
                    return false;
                }

                inputDispatched = true;
                if (keyUp)
                {
                    InputWatchdogKeys.Remove(virtualKey);
                    if (InputWatchdogKeys.Count == 0 &&
                        InputWatchdogMouseButtons.Count == 0)
                    {
                        StopInputWatchdogTimerLocked();
                    }
                }
                else
                {
                    InputWatchdogKeys[virtualKey] = extended;
                    EnsureInputWatchdogTimerLocked();
                }

                validationCode = "OK";
                nativeError = 0;
                return true;
            }
        }

        private static bool SendMouseButtonWatchdogBound(
            IntPtr window,
            uint expectedProcessId,
            string button,
            bool buttonUp,
            out bool inputDispatched,
            out string validationCode,
            out int nativeError)
        {
            inputDispatched = false;
            string normalizedButton = (button ?? string.Empty).ToLowerInvariant();
            lock (InputWatchdogSync)
            {
                if (!BindInputWatchdogSessionLocked(
                        window,
                        expectedProcessId,
                        !buttonUp,
                        out validationCode,
                        out nativeError))
                {
                    return false;
                }

                if (!SendMouseButtonCore(normalizedButton, buttonUp, out nativeError))
                {
                    validationCode = "MOUSE_BUTTON_SEND_FAILED";
                    return false;
                }

                inputDispatched = true;
                if (buttonUp)
                {
                    InputWatchdogMouseButtons.Remove(normalizedButton);
                    if (InputWatchdogKeys.Count == 0 &&
                        InputWatchdogMouseButtons.Count == 0)
                    {
                        StopInputWatchdogTimerLocked();
                    }
                }
                else
                {
                    InputWatchdogMouseButtons.Add(normalizedButton);
                    EnsureInputWatchdogTimerLocked();
                }

                validationCode = "OK";
                nativeError = 0;
                return true;
            }
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct POINT
        {
            public int X;
            public int Y;

            public POINT(int x, int y)
            {
                X = x;
                Y = y;
            }
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct RECT
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct STARTUPINFO
        {
            public uint cb;
            public string lpReserved;
            public string lpDesktop;
            public string lpTitle;
            public uint dwX;
            public uint dwY;
            public uint dwXSize;
            public uint dwYSize;
            public uint dwXCountChars;
            public uint dwYCountChars;
            public uint dwFillAttribute;
            public uint dwFlags;
            public ushort wShowWindow;
            public ushort cbReserved2;
            public IntPtr lpReserved2;
            public IntPtr hStdInput;
            public IntPtr hStdOutput;
            public IntPtr hStdError;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct PROCESS_INFORMATION
        {
            public IntPtr hProcess;
            public IntPtr hThread;
            public uint dwProcessId;
            public uint dwThreadId;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct BITMAPINFOHEADER
        {
            public uint biSize;
            public int biWidth;
            public int biHeight;
            public ushort biPlanes;
            public ushort biBitCount;
            public uint biCompression;
            public uint biSizeImage;
            public int biXPelsPerMeter;
            public int biYPelsPerMeter;
            public uint biClrUsed;
            public uint biClrImportant;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct BITMAPINFO
        {
            public BITMAPINFOHEADER bmiHeader;
            public uint bmiColors;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct IO_COUNTERS
        {
            public ulong ReadOperationCount;
            public ulong WriteOperationCount;
            public ulong OtherOperationCount;
            public ulong ReadTransferCount;
            public ulong WriteTransferCount;
            public ulong OtherTransferCount;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_BASIC_LIMIT_INFORMATION
        {
            public long PerProcessUserTimeLimit;
            public long PerJobUserTimeLimit;
            public uint LimitFlags;
            public UIntPtr MinimumWorkingSetSize;
            public UIntPtr MaximumWorkingSetSize;
            public uint ActiveProcessLimit;
            public UIntPtr Affinity;
            public uint PriorityClass;
            public uint SchedulingClass;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
        {
            public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
            public IO_COUNTERS IoInfo;
            public UIntPtr ProcessMemoryLimit;
            public UIntPtr JobMemoryLimit;
            public UIntPtr PeakProcessMemoryUsed;
            public UIntPtr PeakJobMemoryUsed;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_BASIC_ACCOUNTING_INFORMATION
        {
            public long TotalUserTime;
            public long TotalKernelTime;
            public long ThisPeriodTotalUserTime;
            public long ThisPeriodTotalKernelTime;
            public uint TotalPageFaultCount;
            public uint TotalProcesses;
            public uint ActiveProcesses;
            public uint TotalTerminatedProcesses;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MOUSEINPUT
        {
            public int dx;
            public int dy;
            public uint mouseData;
            public uint dwFlags;
            public uint time;
            public UIntPtr dwExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct KEYBDINPUT
        {
            public ushort wVk;
            public ushort wScan;
            public uint dwFlags;
            public uint time;
            public UIntPtr dwExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct HARDWAREINPUT
        {
            public uint uMsg;
            public ushort wParamL;
            public ushort wParamH;
        }

        [StructLayout(LayoutKind.Explicit)]
        private struct INPUTUNION
        {
            [FieldOffset(0)] public MOUSEINPUT mi;
            [FieldOffset(0)] public KEYBDINPUT ki;
            [FieldOffset(0)] public HARDWAREINPUT hi;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct INPUT
        {
            public uint type;
            public INPUTUNION data;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateJobObject(IntPtr securityAttributes, string name);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetInformationJobObject(
            IntPtr job,
            int informationClass,
            ref JOBOBJECT_EXTENDED_LIMIT_INFORMATION information,
            uint informationLength);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool QueryInformationJobObject(
            IntPtr job,
            int informationClass,
            ref JOBOBJECT_BASIC_ACCOUNTING_INFORMATION information,
            uint informationLength,
            IntPtr returnLength);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool TerminateJobObject(IntPtr job, uint exitCode);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr handle);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CreateProcessW(
            string applicationName,
            StringBuilder commandLine,
            IntPtr processAttributes,
            IntPtr threadAttributes,
            [MarshalAs(UnmanagedType.Bool)] bool inheritHandles,
            uint creationFlags,
            IntPtr environment,
            string currentDirectory,
            ref STARTUPINFO startupInfo,
            out PROCESS_INFORMATION processInformation);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint ResumeThread(IntPtr thread);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool TerminateProcess(IntPtr process, uint exitCode);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);

        [DllImport("kernel32.dll")]
        private static extern uint GetCurrentThreadId();

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr parameter);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsWindow(IntPtr window);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsWindowVisible(IntPtr window);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsIconic(IntPtr window);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetClientRect(IntPtr window, out RECT rectangle);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetWindowRect(IntPtr window, out RECT rectangle);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ClientToScreen(IntPtr window, ref POINT point);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetForegroundWindow(IntPtr window);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool BringWindowToTop(IntPtr window);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ShowWindowAsync(IntPtr window, int command);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetWindowPos(
            IntPtr window,
            IntPtr insertAfter,
            int x,
            int y,
            int width,
            int height,
            uint flags);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool AttachThreadInput(uint firstThread, uint secondThread, bool attach);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SetFocus(IntPtr window);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern IntPtr GetWindow(IntPtr window, uint command);

        [DllImport("user32.dll")]
        private static extern IntPtr GetAncestor(IntPtr window, uint flags);

        [DllImport("user32.dll")]
        private static extern IntPtr WindowFromPoint(POINT point);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetCursorPos(out POINT point);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetCursorPos(int x, int y);

        [DllImport("user32.dll")]
        private static extern int GetSystemMetrics(int index);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint SendInput(uint count, INPUT[] inputs, int size);

        [DllImport("user32.dll")]
        private static extern short GetAsyncKeyState(int virtualKey);

        [DllImport("user32.dll")]
        private static extern uint MapVirtualKey(uint code, uint mapType);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr dpiContext);

        [DllImport("user32.dll")]
        private static extern uint GetDpiForWindow(IntPtr window);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr GetDC(IntPtr window);

        [DllImport("user32.dll")]
        private static extern int ReleaseDC(IntPtr window, IntPtr deviceContext);

        [DllImport("gdi32.dll", SetLastError = true)]
        private static extern IntPtr CreateCompatibleDC(IntPtr deviceContext);

        [DllImport("gdi32.dll", SetLastError = true)]
        private static extern IntPtr CreateCompatibleBitmap(
            IntPtr deviceContext,
            int width,
            int height);

        [DllImport("gdi32.dll", SetLastError = true)]
        private static extern IntPtr SelectObject(IntPtr deviceContext, IntPtr value);

        [DllImport("gdi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool DeleteObject(IntPtr value);

        [DllImport("gdi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool DeleteDC(IntPtr deviceContext);

        [DllImport("gdi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool BitBlt(
            IntPtr destination,
            int destinationX,
            int destinationY,
            int width,
            int height,
            IntPtr source,
            int sourceX,
            int sourceY,
            uint rasterOperation);

        [DllImport("gdi32.dll", SetLastError = true)]
        private static extern int GetDIBits(
            IntPtr deviceContext,
            IntPtr bitmap,
            uint startScan,
            uint scanLines,
            [Out] byte[] bits,
            ref BITMAPINFO bitmapInfo,
            uint usage);

        [DllImport("dwmapi.dll", PreserveSig = true)]
        private static extern int DwmGetWindowAttribute(
            IntPtr window,
            int attribute,
            out int value,
            int valueSize);

        private static bool EnterPerMonitorDpiAwareness(
            out IntPtr previousContext,
            out int nativeError)
        {
            previousContext = SetThreadDpiAwarenessContext(
                DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
            if (previousContext == IntPtr.Zero)
            {
                nativeError = Marshal.GetLastWin32Error();
                return false;
            }

            nativeError = 0;
            return true;
        }

        private static void RestoreDpiAwareness(IntPtr previousContext)
        {
            if (previousContext != IntPtr.Zero)
            {
                SetThreadDpiAwarenessContext(previousContext);
            }
        }

        // Compatibility probe for the PowerShell module. Coordinate-sensitive
        // operations establish and restore their own thread context; this method
        // intentionally leaves the caller's thread unchanged.
        public static bool EnsurePerMonitorDpiAwareness(out int nativeError)
        {
            IntPtr previousContext;
            if (!EnterPerMonitorDpiAwareness(out previousContext, out nativeError))
            {
                return false;
            }

            try
            {
                nativeError = 0;
                return true;
            }
            finally
            {
                RestoreDpiAwareness(previousContext);
            }
        }

        public static bool CreateKillOnCloseJob(out IntPtr job, out int nativeError)
        {
            job = CreateJobObject(IntPtr.Zero, null);
            if (job == IntPtr.Zero)
            {
                nativeError = Marshal.GetLastWin32Error();
                return false;
            }

            JOBOBJECT_EXTENDED_LIMIT_INFORMATION information =
                new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
            information.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
            if (!SetInformationJobObject(
                    job,
                    JobObjectExtendedLimitInformation,
                    ref information,
                    (uint)Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION))))
            {
                nativeError = Marshal.GetLastWin32Error();
                CloseHandle(job);
                job = IntPtr.Zero;
                return false;
            }

            nativeError = 0;
            return true;
        }

        public static bool AssignProcessToJob(IntPtr job, Process process, out int nativeError)
        {
            if (job == IntPtr.Zero || process == null)
            {
                nativeError = 87;
                return false;
            }

            bool assigned = AssignProcessToJobObject(job, process.Handle);
            nativeError = assigned ? 0 : Marshal.GetLastWin32Error();
            return assigned;
        }

        private static string QuoteCommandLineArgument(string value)
        {
            if (value == null)
            {
                return "\"\"";
            }

            if (value.Length > 0 && value.IndexOfAny(new char[] { ' ', '\t', '\n', '\v', '"' }) < 0)
            {
                return value;
            }

            StringBuilder quoted = new StringBuilder();
            quoted.Append('"');
            int backslashes = 0;
            foreach (char character in value)
            {
                if (character == '\\')
                {
                    backslashes++;
                    continue;
                }

                if (character == '"')
                {
                    quoted.Append('\\', backslashes * 2 + 1);
                    quoted.Append('"');
                    backslashes = 0;
                    continue;
                }

                quoted.Append('\\', backslashes);
                backslashes = 0;
                quoted.Append(character);
            }

            quoted.Append('\\', backslashes * 2);
            quoted.Append('"');
            return quoted.ToString();
        }

        public static bool StartProcessSuspendedInJob(
            IntPtr job,
            string applicationPath,
            string[] arguments,
            string workingDirectory,
            out Process process,
            out int nativeError)
        {
            process = null;
            nativeError = 0;
            if (job == IntPtr.Zero || string.IsNullOrWhiteSpace(applicationPath) ||
                string.IsNullOrWhiteSpace(workingDirectory))
            {
                nativeError = 87;
                return false;
            }

            StringBuilder commandLine = new StringBuilder();
            commandLine.Append(QuoteCommandLineArgument(applicationPath));
            foreach (string argument in arguments ?? new string[0])
            {
                commandLine.Append(' ');
                commandLine.Append(QuoteCommandLineArgument(argument));
            }

            STARTUPINFO startupInfo = new STARTUPINFO();
            startupInfo.cb = (uint)Marshal.SizeOf(typeof(STARTUPINFO));
            PROCESS_INFORMATION processInformation;
            if (!CreateProcessW(
                    applicationPath,
                    commandLine,
                    IntPtr.Zero,
                    IntPtr.Zero,
                    false,
                    CREATE_SUSPENDED,
                    IntPtr.Zero,
                    workingDirectory,
                    ref startupInfo,
                    out processInformation))
            {
                nativeError = Marshal.GetLastWin32Error();
                return false;
            }

            bool assigned = false;
            try
            {
                assigned = AssignProcessToJobObject(job, processInformation.hProcess);
                if (!assigned)
                {
                    nativeError = Marshal.GetLastWin32Error();
                    TerminateProcess(processInformation.hProcess, 0xE0000011u);
                    WaitForSingleObject(processInformation.hProcess, 5000);
                    return false;
                }

                uint resumeResult = ResumeThread(processInformation.hThread);
                if (resumeResult == 0xFFFFFFFF)
                {
                    nativeError = Marshal.GetLastWin32Error();
                    TerminateProcess(processInformation.hProcess, 0xE0000012u);
                    WaitForSingleObject(processInformation.hProcess, 5000);
                    return false;
                }

                process = Process.GetProcessById((int)processInformation.dwProcessId);
                nativeError = 0;
                return true;
            }
            catch
            {
                nativeError = nativeError == 0 ? Marshal.GetLastWin32Error() : nativeError;
                TerminateProcess(processInformation.hProcess, 0xE0000013u);
                WaitForSingleObject(processInformation.hProcess, 5000);
                return false;
            }
            finally
            {
                if (processInformation.hThread != IntPtr.Zero)
                {
                    CloseHandle(processInformation.hThread);
                }

                if (processInformation.hProcess != IntPtr.Zero)
                {
                    CloseHandle(processInformation.hProcess);
                }
            }
        }

        public static bool TryGetJobActiveProcessCount(
            IntPtr job,
            out uint activeProcessCount,
            out int nativeError)
        {
            activeProcessCount = 0;
            if (job == IntPtr.Zero)
            {
                nativeError = 6;
                return false;
            }

            JOBOBJECT_BASIC_ACCOUNTING_INFORMATION information =
                new JOBOBJECT_BASIC_ACCOUNTING_INFORMATION();
            bool queried = QueryInformationJobObject(
                job,
                JobObjectBasicAccountingInformation,
                ref information,
                (uint)Marshal.SizeOf(typeof(JOBOBJECT_BASIC_ACCOUNTING_INFORMATION)),
                IntPtr.Zero);
            if (!queried)
            {
                nativeError = Marshal.GetLastWin32Error();
                return false;
            }

            activeProcessCount = information.ActiveProcesses;
            nativeError = 0;
            return true;
        }

        public static bool TerminateJob(IntPtr job, uint exitCode, out int nativeError)
        {
            if (job == IntPtr.Zero)
            {
                nativeError = 6;
                return false;
            }

            bool terminated = TerminateJobObject(job, exitCode);
            nativeError = terminated ? 0 : Marshal.GetLastWin32Error();
            return terminated;
        }

        public static bool CloseJob(IntPtr job, out int nativeError)
        {
            if (job == IntPtr.Zero)
            {
                nativeError = 0;
                return true;
            }

            bool closed = CloseHandle(job);
            nativeError = closed ? 0 : Marshal.GetLastWin32Error();
            return closed;
        }

        public static WindowSnapshot[] EnumerateVisibleTopLevelWindows(uint processId)
        {
            List<WindowSnapshot> windows = new List<WindowSnapshot>();
            EnumWindowsProc callback = delegate(IntPtr window, IntPtr parameter)
            {
                uint ownerProcessId;
                GetWindowThreadProcessId(window, out ownerProcessId);
                if (ownerProcessId != processId || !IsWindowVisible(window) || IsIconic(window))
                {
                    return true;
                }

                if (GetWindow(window, GW_OWNER) != IntPtr.Zero)
                {
                    return true;
                }

                int cloaked;
                if (DwmGetWindowAttribute(window, DWMWA_CLOAKED, out cloaked, sizeof(int)) == 0 && cloaked != 0)
                {
                    return true;
                }

                WindowSnapshot snapshot;
                string validationCode;
                int validationError;
                if (TryGetWindowSnapshot(
                        window,
                        processId,
                        false,
                        out snapshot,
                        out validationCode,
                        out validationError))
                {
                    windows.Add(snapshot);
                }

                return true;
            };

            if (!EnumWindows(callback, IntPtr.Zero))
            {
                return new WindowSnapshot[0];
            }

            GC.KeepAlive(callback);
            windows.Sort(delegate(WindowSnapshot left, WindowSnapshot right)
            {
                long leftArea = (long)left.ClientWidth * left.ClientHeight;
                long rightArea = (long)right.ClientWidth * right.ClientHeight;
                return rightArea.CompareTo(leftArea);
            });
            return windows.ToArray();
        }

        public static bool TryGetWindowSnapshot(
            IntPtr window,
            uint expectedProcessId,
            bool requireForeground,
            out WindowSnapshot snapshot,
            out string validationCode,
            out int nativeError)
        {
            snapshot = null;
            nativeError = 0;
            validationCode = "DPI_AWARENESS_CONTEXT_FAILED";
            IntPtr previousDpiContext;
            if (!EnterPerMonitorDpiAwareness(out previousDpiContext, out nativeError))
            {
                return false;
            }

            try
            {
                if (window == IntPtr.Zero || !IsWindow(window))
                {
                    validationCode = "WINDOW_INVALID";
                    return false;
                }

                if (!IsWindowVisible(window))
                {
                    validationCode = "WINDOW_NOT_VISIBLE";
                    return false;
                }

                if (IsIconic(window))
                {
                    validationCode = "WINDOW_MINIMIZED";
                    return false;
                }

                uint processId;
                if (GetWindowThreadProcessId(window, out processId) == 0)
                {
                    validationCode = "WINDOW_PID_QUERY_FAILED";
                    nativeError = Marshal.GetLastWin32Error();
                    return false;
                }

                if (processId != expectedProcessId)
                {
                    validationCode = "WINDOW_PID_MISMATCH";
                    return false;
                }

                RECT clientRectangle;
                if (!GetClientRect(window, out clientRectangle))
                {
                    validationCode = "CLIENT_RECT_QUERY_FAILED";
                    nativeError = Marshal.GetLastWin32Error();
                    return false;
                }

                int logicalWidth = clientRectangle.Right - clientRectangle.Left;
                int logicalHeight = clientRectangle.Bottom - clientRectangle.Top;
                if (logicalWidth <= 0 || logicalHeight <= 0)
                {
                    validationCode = "CLIENT_AREA_INVALID";
                    return false;
                }

                POINT origin = new POINT(0, 0);
                POINT bottomRight = new POINT(logicalWidth, logicalHeight);
                if (!ClientToScreen(window, ref origin) ||
                    !ClientToScreen(window, ref bottomRight))
                {
                    validationCode = "CLIENT_ORIGIN_QUERY_FAILED";
                    nativeError = Marshal.GetLastWin32Error();
                    return false;
                }

                int width = bottomRight.X - origin.X;
                int height = bottomRight.Y - origin.Y;
                if (width <= 0 || height <= 0)
                {
                    validationCode = "CLIENT_AREA_INVALID";
                    return false;
                }

                bool foreground = GetForegroundWindow() == window;
                if (requireForeground && !foreground)
                {
                    validationCode = "FOREGROUND_NOT_CONFIRMED";
                    return false;
                }

                snapshot = new WindowSnapshot
                {
                    Handle = window,
                    ProcessId = processId,
                    ClientLeft = origin.X,
                    ClientTop = origin.Y,
                    ClientWidth = width,
                    ClientHeight = height,
                    IsForeground = foreground,
                    IsVisible = true,
                    IsMinimized = false,
                    Dpi = GetDpiForWindow(window),
                    CoordinateSpace = "physical_screen_pixels"
                };
                validationCode = "OK";
                nativeError = 0;
                return true;
            }
            finally
            {
                RestoreDpiAwareness(previousDpiContext);
            }
        }

        public static bool RequestForeground(IntPtr window, out int nativeError)
        {
            nativeError = 0;
            if (window == IntPtr.Zero || !IsWindow(window) || !IsWindowVisible(window))
            {
                nativeError = 1400;
                return false;
            }

            if (GetForegroundWindow() == window)
            {
                return true;
            }

            ShowWindowAsync(window, SW_RESTORE);
            IntPtr previousForeground = GetForegroundWindow();
            uint targetProcessId;
            uint targetThread = GetWindowThreadProcessId(window, out targetProcessId);
            uint foregroundProcessId = 0;
            uint foregroundThread = previousForeground == IntPtr.Zero
                ? 0
                : GetWindowThreadProcessId(previousForeground, out foregroundProcessId);
            uint currentThread = GetCurrentThreadId();
            bool attachedTarget = false;
            bool attachedForeground = false;

            try
            {
                if (targetThread != 0 && targetThread != currentThread)
                {
                    attachedTarget = AttachThreadInput(currentThread, targetThread, true);
                }

                if (foregroundThread != 0 &&
                    foregroundThread != currentThread &&
                    foregroundThread != targetThread)
                {
                    attachedForeground = AttachThreadInput(currentThread, foregroundThread, true);
                }

                SetWindowPos(window, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
                BringWindowToTop(window);
                SetForegroundWindow(window);
                SetFocus(window);
            }
            finally
            {
                if (attachedForeground)
                {
                    AttachThreadInput(currentThread, foregroundThread, false);
                }

                if (attachedTarget)
                {
                    AttachThreadInput(currentThread, targetThread, false);
                }
            }

            bool confirmed = GetForegroundWindow() == window;
            nativeError = confirmed ? 0 : Marshal.GetLastWin32Error();
            return confirmed;
        }

        public static bool RequestForegroundBound(
            IntPtr window,
            uint expectedProcessId,
            out string validationCode,
            out int nativeError)
        {
            WindowSnapshot snapshot;
            if (!TryGetWindowSnapshot(
                    window,
                    expectedProcessId,
                    false,
                    out snapshot,
                    out validationCode,
                    out nativeError))
            {
                return false;
            }

            if (!RequestForeground(window, out nativeError))
            {
                validationCode = "FOREGROUND_REQUEST_FAILED";
                return false;
            }

            if (!TryGetWindowSnapshot(
                    window,
                    expectedProcessId,
                    true,
                    out snapshot,
                    out validationCode,
                    out nativeError))
            {
                return false;
            }

            validationCode = "OK";
            nativeError = 0;
            return true;
        }

        private static bool IsPointOwnedByTarget(
            IntPtr window,
            uint expectedProcessId,
            int screenX,
            int screenY,
            out string validationCode,
            out int nativeError)
        {
            nativeError = 0;
            IntPtr hit = WindowFromPoint(new POINT(screenX, screenY));
            if (hit == IntPtr.Zero)
            {
                validationCode = "POINTER_HIT_TEST_FAILED";
                return false;
            }

            IntPtr root = GetAncestor(hit, GA_ROOT);
            if (root == IntPtr.Zero)
            {
                root = hit;
            }

            uint hitProcessId;
            if (GetWindowThreadProcessId(root, out hitProcessId) == 0)
            {
                validationCode = "POINTER_HIT_PID_QUERY_FAILED";
                nativeError = Marshal.GetLastWin32Error();
                return false;
            }

            if (root != window || hitProcessId != expectedProcessId)
            {
                validationCode = "POINTER_TARGET_OCCLUDED";
                return false;
            }

            validationCode = "OK";
            return true;
        }

        private static bool SameClientBinding(WindowSnapshot before, WindowSnapshot after)
        {
            return before != null && after != null &&
                   before.Handle == after.Handle &&
                   before.ProcessId == after.ProcessId &&
                   before.ClientLeft == after.ClientLeft &&
                   before.ClientTop == after.ClientTop &&
                   before.ClientWidth == after.ClientWidth &&
                   before.ClientHeight == after.ClientHeight &&
                   before.Dpi == after.Dpi;
        }

        public static bool SendKeyboardBound(
            IntPtr window,
            uint expectedProcessId,
            ushort virtualKey,
            bool keyUp,
            bool extended,
            out bool inputDispatched,
            out string validationCode,
            out int nativeError)
        {
            inputDispatched = false;
            WindowSnapshot snapshot;
            if (!TryGetWindowSnapshot(
                    window,
                    expectedProcessId,
                    true,
                    out snapshot,
                    out validationCode,
                    out nativeError))
            {
                return false;
            }

            if (!SendKeyboardWatchdogBound(
                    window,
                    expectedProcessId,
                    virtualKey,
                    keyUp,
                    extended,
                    out inputDispatched,
                    out validationCode,
                    out nativeError))
            {
                return false;
            }

            WindowSnapshot postSnapshot;
            if (!TryGetWindowSnapshot(
                    window,
                    expectedProcessId,
                    true,
                    out postSnapshot,
                    out validationCode,
                    out nativeError))
            {
                validationCode = "BINDING_LOST_AFTER_DISPATCH";
                return false;
            }

            validationCode = "OK";
            nativeError = 0;
            return true;
        }

        public static bool SendMouseMoveBound(
            IntPtr window,
            uint expectedProcessId,
            double normalizedX,
            double normalizedY,
            out WindowSnapshot dispatchSnapshot,
            out int screenX,
            out int screenY,
            out bool inputDispatched,
            out string validationCode,
            out int nativeError)
        {
            dispatchSnapshot = null;
            screenX = 0;
            screenY = 0;
            inputDispatched = false;
            nativeError = 0;
            validationCode = "DPI_AWARENESS_CONTEXT_FAILED";
            if (double.IsNaN(normalizedX) || double.IsInfinity(normalizedX) ||
                double.IsNaN(normalizedY) || double.IsInfinity(normalizedY) ||
                normalizedX < 0 || normalizedX > 1 ||
                normalizedY < 0 || normalizedY > 1)
            {
                validationCode = "NORMALIZED_POINT_INVALID";
                nativeError = 87;
                return false;
            }

            IntPtr previousDpiContext;
            if (!EnterPerMonitorDpiAwareness(out previousDpiContext, out nativeError))
            {
                return false;
            }

            try
            {
                if (!TryGetWindowSnapshot(
                        window,
                        expectedProcessId,
                        true,
                        out dispatchSnapshot,
                        out validationCode,
                        out nativeError))
                {
                    return false;
                }

                int clientX = Math.Min(
                    dispatchSnapshot.ClientWidth - 1,
                    Math.Max(0, (int)Math.Floor(normalizedX * dispatchSnapshot.ClientWidth)));
                int clientY = Math.Min(
                    dispatchSnapshot.ClientHeight - 1,
                    Math.Max(0, (int)Math.Floor(normalizedY * dispatchSnapshot.ClientHeight)));
                screenX = dispatchSnapshot.ClientLeft + clientX;
                screenY = dispatchSnapshot.ClientTop + clientY;

                if (!IsPointOwnedByTarget(
                        window,
                        expectedProcessId,
                        screenX,
                        screenY,
                        out validationCode,
                        out nativeError))
                {
                    return false;
                }

                if (!SendMouseMoveToScreenPoint(screenX, screenY, out nativeError))
                {
                    validationCode = "POINTER_MOVE_SEND_FAILED";
                    return false;
                }

                inputDispatched = true;
                POINT cursor;
                if (!GetCursorPos(out cursor))
                {
                    validationCode = "CURSOR_POSITION_QUERY_FAILED_AFTER_DISPATCH";
                    nativeError = Marshal.GetLastWin32Error();
                    return false;
                }

                if (Math.Abs(cursor.X - screenX) > 1 || Math.Abs(cursor.Y - screenY) > 1)
                {
                    validationCode = "CURSOR_POSITION_MISMATCH_AFTER_DISPATCH";
                    return false;
                }

                WindowSnapshot postSnapshot;
                if (!TryGetWindowSnapshot(
                        window,
                        expectedProcessId,
                        true,
                        out postSnapshot,
                        out validationCode,
                        out nativeError) ||
                    !SameClientBinding(dispatchSnapshot, postSnapshot))
                {
                    validationCode = "BINDING_CHANGED_AFTER_DISPATCH";
                    return false;
                }

                if (!IsPointOwnedByTarget(
                        window,
                        expectedProcessId,
                        cursor.X,
                        cursor.Y,
                        out validationCode,
                        out nativeError))
                {
                    validationCode = "POINTER_TARGET_LOST_AFTER_DISPATCH";
                    return false;
                }

                validationCode = "OK";
                nativeError = 0;
                return true;
            }
            finally
            {
                RestoreDpiAwareness(previousDpiContext);
            }
        }

        public static bool SendMouseButtonBound(
            IntPtr window,
            uint expectedProcessId,
            string button,
            bool buttonUp,
            out bool inputDispatched,
            out string validationCode,
            out int nativeError)
        {
            inputDispatched = false;
            nativeError = 0;
            validationCode = "DPI_AWARENESS_CONTEXT_FAILED";
            IntPtr previousDpiContext;
            if (!EnterPerMonitorDpiAwareness(out previousDpiContext, out nativeError))
            {
                return false;
            }

            try
            {
                WindowSnapshot snapshot;
                if (!TryGetWindowSnapshot(
                        window,
                        expectedProcessId,
                        true,
                        out snapshot,
                        out validationCode,
                        out nativeError))
                {
                    return false;
                }

                POINT cursor;
                if (!GetCursorPos(out cursor))
                {
                    validationCode = "CURSOR_POSITION_QUERY_FAILED";
                    nativeError = Marshal.GetLastWin32Error();
                    return false;
                }

                if (!IsPointInsideClient(snapshot, cursor.X, cursor.Y))
                {
                    validationCode = "POINTER_OUTSIDE_CLIENT";
                    return false;
                }

                if (!IsPointOwnedByTarget(
                        window,
                        expectedProcessId,
                        cursor.X,
                        cursor.Y,
                        out validationCode,
                        out nativeError))
                {
                    return false;
                }

                if (!SendMouseButtonWatchdogBound(
                        window,
                        expectedProcessId,
                        button,
                        buttonUp,
                        out inputDispatched,
                        out validationCode,
                        out nativeError))
                {
                    return false;
                }

                WindowSnapshot postSnapshot;
                if (!TryGetWindowSnapshot(
                        window,
                        expectedProcessId,
                        true,
                        out postSnapshot,
                        out validationCode,
                        out nativeError) ||
                    !SameClientBinding(snapshot, postSnapshot))
                {
                    validationCode = "BINDING_CHANGED_AFTER_DISPATCH";
                    return false;
                }

                POINT postCursor;
                if (!GetCursorPos(out postCursor) ||
                    !IsPointInsideClient(postSnapshot, postCursor.X, postCursor.Y) ||
                    !IsPointOwnedByTarget(
                        window,
                        expectedProcessId,
                        postCursor.X,
                        postCursor.Y,
                        out validationCode,
                        out nativeError))
                {
                    validationCode = "POINTER_TARGET_LOST_AFTER_DISPATCH";
                    return false;
                }

                validationCode = "OK";
                nativeError = 0;
                return true;
            }
            finally
            {
                RestoreDpiAwareness(previousDpiContext);
            }
        }

        public static bool IsClientAreaUnoccluded(
            IntPtr window,
            uint expectedProcessId,
            out int failedSampleIndex)
        {
            failedSampleIndex = -1;
            int nativeError;
            IntPtr previousDpiContext;
            if (!EnterPerMonitorDpiAwareness(out previousDpiContext, out nativeError))
            {
                return false;
            }

            try
            {
                WindowSnapshot snapshot;
                string validationCode;
                if (!TryGetWindowSnapshot(
                        window,
                        expectedProcessId,
                        true,
                        out snapshot,
                        out validationCode,
                        out nativeError))
                {
                    return false;
                }

                if (!CheckNoHigherZOrderOverlap(
                        window,
                        snapshot,
                        out validationCode,
                        out nativeError))
                {
                    failedSampleIndex = -2;
                    return false;
                }

                return CheckExposureSamples(
                    window,
                    expectedProcessId,
                    snapshot,
                    out failedSampleIndex,
                    out validationCode,
                    out nativeError);
            }
            finally
            {
                RestoreDpiAwareness(previousDpiContext);
            }
        }

        private static bool CheckExposureSamples(
            IntPtr window,
            uint expectedProcessId,
            WindowSnapshot snapshot,
            out int failedSampleIndex,
            out string validationCode,
            out int nativeError)
        {
            failedSampleIndex = -1;
            nativeError = 0;
            int index = 0;
            const int samplesPerAxis = 9;
            for (int yIndex = 0; yIndex < samplesPerAxis; yIndex++)
            {
                int screenY = snapshot.ClientTop + (int)Math.Round(
                    (snapshot.ClientHeight - 1) * yIndex / (double)(samplesPerAxis - 1),
                    MidpointRounding.AwayFromZero);
                for (int xIndex = 0; xIndex < samplesPerAxis; xIndex++)
                {
                    int screenX = snapshot.ClientLeft + (int)Math.Round(
                        (snapshot.ClientWidth - 1) * xIndex / (double)(samplesPerAxis - 1),
                        MidpointRounding.AwayFromZero);
                    if (!IsPointOwnedByTarget(
                            window,
                            expectedProcessId,
                            screenX,
                            screenY,
                            out validationCode,
                            out nativeError))
                    {
                        failedSampleIndex = index;
                        return false;
                    }

                    index++;
                }
            }

            validationCode = "OK";
            return true;
        }

        private static bool CheckNoHigherZOrderOverlap(
            IntPtr window,
            WindowSnapshot snapshot,
            out string validationCode,
            out int nativeError)
        {
            validationCode = "OK";
            nativeError = 0;
            bool targetSeen = false;
            bool overlapFound = false;
            bool enumerationFault = false;
            int enumerationError = 0;
            int targetLeft = snapshot.ClientLeft;
            int targetTop = snapshot.ClientTop;
            int targetRight = checked(snapshot.ClientLeft + snapshot.ClientWidth);
            int targetBottom = checked(snapshot.ClientTop + snapshot.ClientHeight);

            EnumWindowsProc callback = delegate(IntPtr candidate, IntPtr parameter)
            {
                if (candidate == window)
                {
                    targetSeen = true;
                    return true;
                }

                if (targetSeen || !IsWindowVisible(candidate) || IsIconic(candidate))
                {
                    return true;
                }

                int cloaked;
                if (DwmGetWindowAttribute(candidate, DWMWA_CLOAKED, out cloaked, sizeof(int)) == 0 &&
                    cloaked != 0)
                {
                    return true;
                }

                RECT candidateRectangle;
                if (!GetWindowRect(candidate, out candidateRectangle))
                {
                    enumerationFault = true;
                    enumerationError = Marshal.GetLastWin32Error();
                    return true;
                }

                bool intersects = candidateRectangle.Left < targetRight &&
                    candidateRectangle.Right > targetLeft &&
                    candidateRectangle.Top < targetBottom &&
                    candidateRectangle.Bottom > targetTop;
                if (intersects)
                {
                    overlapFound = true;
                }

                return true;
            };

            bool enumerated = EnumWindows(callback, IntPtr.Zero);
            GC.KeepAlive(callback);
            if (!enumerated)
            {
                validationCode = "WINDOW_Z_ORDER_ENUMERATION_FAILED";
                nativeError = Marshal.GetLastWin32Error();
                return false;
            }

            if (enumerationFault)
            {
                validationCode = "WINDOW_Z_ORDER_RECT_QUERY_FAILED";
                nativeError = enumerationError;
                return false;
            }

            if (!targetSeen)
            {
                validationCode = "TARGET_NOT_IN_Z_ORDER";
                return false;
            }

            if (overlapFound)
            {
                validationCode = "CLIENT_OVERLAPPED_BY_HIGHER_WINDOW";
                return false;
            }

            return true;
        }

        public static bool CaptureClientBgraBound(
            IntPtr window,
            uint expectedProcessId,
            out ClientCaptureFrame frame,
            out int failedSampleIndex,
            out string validationCode,
            out int nativeError)
        {
            frame = null;
            failedSampleIndex = -1;
            validationCode = "DPI_AWARENESS_CONTEXT_FAILED";
            nativeError = 0;
            IntPtr previousDpiContext;
            if (!EnterPerMonitorDpiAwareness(out previousDpiContext, out nativeError))
            {
                return false;
            }

            try
            {
                WindowSnapshot snapshot;
                if (!TryGetWindowSnapshot(
                        window,
                        expectedProcessId,
                        true,
                        out snapshot,
                        out validationCode,
                        out nativeError))
                {
                    return false;
                }

                if (!CheckNoHigherZOrderOverlap(
                        window,
                        snapshot,
                        out validationCode,
                        out nativeError))
                {
                    failedSampleIndex = -2;
                    return false;
                }

                if (!CheckExposureSamples(
                        window,
                        expectedProcessId,
                        snapshot,
                        out failedSampleIndex,
                        out validationCode,
                        out nativeError))
                {
                    return false;
                }

                long byteLength = (long)snapshot.ClientWidth * snapshot.ClientHeight * 4L;
                if (byteLength <= 0 || byteLength > 268435456L)
                {
                    validationCode = "CAPTURE_SIZE_UNSAFE";
                    nativeError = 8;
                    return false;
                }

                IntPtr sourceDc = IntPtr.Zero;
                IntPtr memoryDc = IntPtr.Zero;
                IntPtr bitmap = IntPtr.Zero;
                IntPtr previousBitmap = IntPtr.Zero;
                try
                {
                    sourceDc = GetDC(IntPtr.Zero);
                    if (sourceDc == IntPtr.Zero)
                    {
                        validationCode = "SCREEN_DC_ACQUISITION_FAILED";
                        nativeError = Marshal.GetLastWin32Error();
                        return false;
                    }

                    memoryDc = CreateCompatibleDC(sourceDc);
                    if (memoryDc == IntPtr.Zero)
                    {
                        validationCode = "CAPTURE_DC_CREATION_FAILED";
                        nativeError = Marshal.GetLastWin32Error();
                        return false;
                    }

                    bitmap = CreateCompatibleBitmap(
                        sourceDc,
                        snapshot.ClientWidth,
                        snapshot.ClientHeight);
                    if (bitmap == IntPtr.Zero)
                    {
                        validationCode = "CAPTURE_BITMAP_CREATION_FAILED";
                        nativeError = Marshal.GetLastWin32Error();
                        return false;
                    }

                    previousBitmap = SelectObject(memoryDc, bitmap);
                    if (previousBitmap == IntPtr.Zero || previousBitmap == new IntPtr(-1))
                    {
                        validationCode = "CAPTURE_BITMAP_SELECTION_FAILED";
                        nativeError = Marshal.GetLastWin32Error();
                        return false;
                    }

                    if (!BitBlt(
                            memoryDc,
                            0,
                            0,
                            snapshot.ClientWidth,
                            snapshot.ClientHeight,
                            sourceDc,
                            snapshot.ClientLeft,
                            snapshot.ClientTop,
                            SRCCOPY | CAPTUREBLT))
                    {
                        validationCode = "CAPTURE_BITBLT_FAILED";
                        nativeError = Marshal.GetLastWin32Error();
                        return false;
                    }

                    int stride = checked(snapshot.ClientWidth * 4);
                    byte[] pixels = new byte[checked(stride * snapshot.ClientHeight)];
                    BITMAPINFO bitmapInfo = new BITMAPINFO();
                    bitmapInfo.bmiHeader.biSize = (uint)Marshal.SizeOf(typeof(BITMAPINFOHEADER));
                    bitmapInfo.bmiHeader.biWidth = snapshot.ClientWidth;
                    bitmapInfo.bmiHeader.biHeight = -snapshot.ClientHeight;
                    bitmapInfo.bmiHeader.biPlanes = 1;
                    bitmapInfo.bmiHeader.biBitCount = 32;
                    bitmapInfo.bmiHeader.biCompression = BI_RGB;
                    bitmapInfo.bmiHeader.biSizeImage = (uint)pixels.Length;
                    int copiedLines = GetDIBits(
                        memoryDc,
                        bitmap,
                        0,
                        (uint)snapshot.ClientHeight,
                        pixels,
                        ref bitmapInfo,
                        DIB_RGB_COLORS);
                    if (copiedLines != snapshot.ClientHeight)
                    {
                        validationCode = "CAPTURE_PIXEL_READ_FAILED";
                        nativeError = Marshal.GetLastWin32Error();
                        return false;
                    }

                    for (int alphaIndex = 3; alphaIndex < pixels.Length; alphaIndex += 4)
                    {
                        pixels[alphaIndex] = 255;
                    }

                    WindowSnapshot postSnapshot;
                    if (!TryGetWindowSnapshot(
                            window,
                            expectedProcessId,
                            true,
                            out postSnapshot,
                            out validationCode,
                            out nativeError) ||
                        !SameClientBinding(snapshot, postSnapshot))
                    {
                        validationCode = "CAPTURE_BINDING_CHANGED";
                        return false;
                    }

                    if (!CheckNoHigherZOrderOverlap(
                            window,
                            postSnapshot,
                            out validationCode,
                            out nativeError))
                    {
                        failedSampleIndex = -3;
                        return false;
                    }

                    int postFailedSampleIndex;
                    if (!CheckExposureSamples(
                            window,
                            expectedProcessId,
                            postSnapshot,
                            out postFailedSampleIndex,
                            out validationCode,
                            out nativeError))
                    {
                        failedSampleIndex = postFailedSampleIndex < 0
                            ? postFailedSampleIndex
                            : 81 + postFailedSampleIndex;
                        return false;
                    }

                    frame = new ClientCaptureFrame
                    {
                        Snapshot = postSnapshot,
                        Bgra32 = pixels,
                        Stride = stride,
                        ExposureSampleCount = 162,
                        ExposureAssurance = "z_order_overlap_check_pre_and_post"
                    };
                    validationCode = "OK";
                    nativeError = 0;
                    return true;
                }
                catch (OverflowException)
                {
                    validationCode = "CAPTURE_SIZE_UNSAFE";
                    nativeError = 8;
                    return false;
                }
                catch (OutOfMemoryException)
                {
                    validationCode = "CAPTURE_MEMORY_ALLOCATION_FAILED";
                    nativeError = 8;
                    return false;
                }
                finally
                {
                    if (previousBitmap != IntPtr.Zero && previousBitmap != new IntPtr(-1) &&
                        memoryDc != IntPtr.Zero)
                    {
                        SelectObject(memoryDc, previousBitmap);
                    }

                    if (bitmap != IntPtr.Zero)
                    {
                        DeleteObject(bitmap);
                    }

                    if (memoryDc != IntPtr.Zero)
                    {
                        DeleteDC(memoryDc);
                    }

                    if (sourceDc != IntPtr.Zero)
                    {
                        ReleaseDC(IntPtr.Zero, sourceDc);
                    }
                }
            }
            finally
            {
                RestoreDpiAwareness(previousDpiContext);
            }
        }

        public static bool PostClose(IntPtr window, out int nativeError)
        {
            bool posted = PostMessage(window, WM_CLOSE, IntPtr.Zero, IntPtr.Zero);
            nativeError = posted ? 0 : Marshal.GetLastWin32Error();
            return posted;
        }

        public static bool PostCloseBound(
            IntPtr window,
            uint expectedProcessId,
            out string validationCode,
            out int nativeError)
        {
            WindowSnapshot snapshot;
            if (!TryGetWindowSnapshot(
                    window,
                    expectedProcessId,
                    false,
                    out snapshot,
                    out validationCode,
                    out nativeError))
            {
                return false;
            }

            if (GetAncestor(window, GA_ROOT) != window || GetWindow(window, GW_OWNER) != IntPtr.Zero)
            {
                validationCode = "WINDOW_NOT_UNOWNED_TOP_LEVEL";
                nativeError = 0;
                return false;
            }

            if (!PostClose(window, out nativeError))
            {
                validationCode = "WM_CLOSE_POST_FAILED";
                return false;
            }

            validationCode = "OK";
            nativeError = 0;
            return true;
        }

        public static bool TryGetCursorPosition(out int x, out int y, out int nativeError)
        {
            x = 0;
            y = 0;
            IntPtr previousDpiContext;
            if (!EnterPerMonitorDpiAwareness(out previousDpiContext, out nativeError))
            {
                return false;
            }

            try
            {
                POINT point;
                bool obtained = GetCursorPos(out point);
                x = obtained ? point.X : 0;
                y = obtained ? point.Y : 0;
                nativeError = obtained ? 0 : Marshal.GetLastWin32Error();
                return obtained;
            }
            finally
            {
                RestoreDpiAwareness(previousDpiContext);
            }
        }

        public static bool RestoreCursorPosition(int x, int y, out int nativeError)
        {
            IntPtr previousDpiContext;
            if (!EnterPerMonitorDpiAwareness(out previousDpiContext, out nativeError))
            {
                return false;
            }

            try
            {
                bool restored = SetCursorPos(x, y);
                nativeError = restored ? 0 : Marshal.GetLastWin32Error();
                return restored;
            }
            finally
            {
                RestoreDpiAwareness(previousDpiContext);
            }
        }

        public static bool IsPointInsideClient(WindowSnapshot snapshot, int x, int y)
        {
            if (snapshot == null)
            {
                return false;
            }

            return x >= snapshot.ClientLeft &&
                   y >= snapshot.ClientTop &&
                   x < snapshot.ClientLeft + snapshot.ClientWidth &&
                   y < snapshot.ClientTop + snapshot.ClientHeight;
        }

        public static bool SendKeyboard(
            ushort virtualKey,
            bool keyUp,
            bool extended,
            out int nativeError)
        {
            if (!keyUp)
            {
                return SendKeyboardCore(virtualKey, false, extended, out nativeError);
            }

            lock (InputWatchdogSync)
            {
                bool sent = SendKeyboardCore(virtualKey, true, extended, out nativeError);
                if (sent)
                {
                    InputWatchdogKeys.Remove(virtualKey);
                    if (InputWatchdogKeys.Count == 0 &&
                        InputWatchdogMouseButtons.Count == 0)
                    {
                        StopInputWatchdogTimerLocked();
                    }
                }

                return sent;
            }
        }

        private static bool SendKeyboardCore(
            ushort virtualKey,
            bool keyUp,
            bool extended,
            out int nativeError)
        {
            uint scanCode = MapVirtualKey(virtualKey, MAPVK_VK_TO_VSC);
            KEYBDINPUT keyboard = new KEYBDINPUT();
            if (scanCode == 0)
            {
                keyboard.wVk = virtualKey;
                keyboard.wScan = 0;
                keyboard.dwFlags = keyUp ? KEYEVENTF_KEYUP : 0;
            }
            else
            {
                keyboard.wVk = 0;
                keyboard.wScan = (ushort)scanCode;
                keyboard.dwFlags = KEYEVENTF_SCANCODE;
                if (keyUp)
                {
                    keyboard.dwFlags |= KEYEVENTF_KEYUP;
                }
            }

            if (extended)
            {
                keyboard.dwFlags |= KEYEVENTF_EXTENDEDKEY;
            }

            INPUT input = new INPUT
            {
                type = INPUT_KEYBOARD,
                data = new INPUTUNION { ki = keyboard }
            };
            return SendSingleInput(input, out nativeError);
        }

        public static bool SendMouseMoveToScreenPoint(int screenX, int screenY, out int nativeError)
        {
            IntPtr previousDpiContext;
            if (!EnterPerMonitorDpiAwareness(out previousDpiContext, out nativeError))
            {
                return false;
            }

            try
            {
                int virtualLeft = GetSystemMetrics(SM_XVIRTUALSCREEN);
                int virtualTop = GetSystemMetrics(SM_YVIRTUALSCREEN);
                int virtualWidth = GetSystemMetrics(SM_CXVIRTUALSCREEN);
                int virtualHeight = GetSystemMetrics(SM_CYVIRTUALSCREEN);
                if (virtualWidth <= 1 || virtualHeight <= 1 ||
                    screenX < virtualLeft || screenY < virtualTop ||
                    screenX >= virtualLeft + virtualWidth ||
                    screenY >= virtualTop + virtualHeight)
                {
                    nativeError = 87;
                    return false;
                }

                int absoluteX = (int)Math.Round(
                    (screenX - virtualLeft) * 65535.0 / (virtualWidth - 1),
                    MidpointRounding.AwayFromZero);
                int absoluteY = (int)Math.Round(
                    (screenY - virtualTop) * 65535.0 / (virtualHeight - 1),
                    MidpointRounding.AwayFromZero);
                INPUT input = new INPUT
                {
                    type = INPUT_MOUSE,
                    data = new INPUTUNION
                    {
                        mi = new MOUSEINPUT
                        {
                            dx = absoluteX,
                            dy = absoluteY,
                            mouseData = 0,
                            dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK,
                            time = 0,
                            dwExtraInfo = EXECUTOR_INPUT_MARKER
                        }
                    }
                };
                return SendSingleInput(input, out nativeError);
            }
            finally
            {
                RestoreDpiAwareness(previousDpiContext);
            }
        }

        public static bool SendMouseButton(string button, bool buttonUp, out int nativeError)
        {
            string normalizedButton = (button ?? string.Empty).ToLowerInvariant();
            if (!buttonUp)
            {
                return SendMouseButtonCore(normalizedButton, false, out nativeError);
            }

            lock (InputWatchdogSync)
            {
                bool sent = SendMouseButtonCore(normalizedButton, true, out nativeError);
                if (sent)
                {
                    InputWatchdogMouseButtons.Remove(normalizedButton);
                    if (InputWatchdogKeys.Count == 0 &&
                        InputWatchdogMouseButtons.Count == 0)
                    {
                        StopInputWatchdogTimerLocked();
                    }
                }

                return sent;
            }
        }

        private static bool SendMouseButtonCore(string button, bool buttonUp, out int nativeError)
        {
            uint flags;
            uint mouseData = 0;
            switch ((button ?? string.Empty).ToLowerInvariant())
            {
                case "left":
                    flags = buttonUp ? MOUSEEVENTF_LEFTUP : MOUSEEVENTF_LEFTDOWN;
                    break;
                case "right":
                    flags = buttonUp ? MOUSEEVENTF_RIGHTUP : MOUSEEVENTF_RIGHTDOWN;
                    break;
                case "middle":
                    flags = buttonUp ? MOUSEEVENTF_MIDDLEUP : MOUSEEVENTF_MIDDLEDOWN;
                    break;
                case "x1":
                    flags = buttonUp ? MOUSEEVENTF_XUP : MOUSEEVENTF_XDOWN;
                    mouseData = XBUTTON1;
                    break;
                case "x2":
                    flags = buttonUp ? MOUSEEVENTF_XUP : MOUSEEVENTF_XDOWN;
                    mouseData = XBUTTON2;
                    break;
                default:
                    nativeError = 87;
                    return false;
            }

            INPUT input = new INPUT
            {
                type = INPUT_MOUSE,
                data = new INPUTUNION
                {
                    mi = new MOUSEINPUT
                    {
                        dx = 0,
                        dy = 0,
                        mouseData = mouseData,
                        dwFlags = flags,
                        time = 0,
                        dwExtraInfo = UIntPtr.Zero
                    }
                }
            };
            return SendSingleInput(input, out nativeError);
        }

        public static bool QueryInputWatchdog(
            IntPtr window,
            uint expectedProcessId,
            out bool active,
            out bool faulted,
            out string faultCode,
            out int nativeError)
        {
            active = false;
            faulted = false;
            faultCode = "OK";
            nativeError = 0;
            lock (InputWatchdogSync)
            {
                if (inputWatchdogWindow == IntPtr.Zero)
                {
                    return true;
                }

                if (inputWatchdogWindow != window ||
                    inputWatchdogProcessId != expectedProcessId)
                {
                    faultCode = "INPUT_WATCHDOG_SESSION_MISMATCH";
                    return false;
                }

                if (InputWatchdogKeys.Count > 0 ||
                    InputWatchdogMouseButtons.Count > 0)
                {
                    WindowSnapshot snapshot;
                    string validationCode;
                    int validationError;
                    bool bindingValid = TryGetWindowSnapshot(
                        inputWatchdogWindow,
                        inputWatchdogProcessId,
                        true,
                        out snapshot,
                        out validationCode,
                        out validationError);
                    if (!bindingValid)
                    {
                        LatchInputWatchdogFaultLocked(validationCode, validationError);
                        int releaseError;
                        ReleaseInputWatchdogEdgesLocked(out releaseError);
                    }
                }

                active = InputWatchdogKeys.Count > 0 ||
                         InputWatchdogMouseButtons.Count > 0;
                faulted = inputWatchdogFaulted;
                faultCode = faulted ? inputWatchdogFaultCode : "OK";
                nativeError = faulted ? inputWatchdogNativeError : 0;
                return true;
            }
        }

        public static bool ClearInputWatchdog(
            IntPtr window,
            uint expectedProcessId,
            out string validationCode,
            out int nativeError)
        {
            validationCode = "OK";
            nativeError = 0;
            lock (InputWatchdogSync)
            {
                if (inputWatchdogWindow != IntPtr.Zero &&
                    (inputWatchdogWindow != window ||
                     inputWatchdogProcessId != expectedProcessId))
                {
                    validationCode = "INPUT_WATCHDOG_SESSION_MISMATCH";
                    return false;
                }

                if (InputWatchdogKeys.Count > 0 ||
                    InputWatchdogMouseButtons.Count > 0)
                {
                    validationCode = "INPUT_WATCHDOG_ACTIVE";
                    return false;
                }

                StopInputWatchdogTimerLocked();
                inputWatchdogWindow = IntPtr.Zero;
                inputWatchdogProcessId = 0;
                inputWatchdogFaulted = false;
                inputWatchdogFaultCode = "OK";
                inputWatchdogNativeError = 0;
                return true;
            }
        }

        public static bool StopInputWatchdog(
            IntPtr window,
            uint expectedProcessId,
            out bool faulted,
            out string faultCode,
            out int nativeError)
        {
            faulted = false;
            faultCode = "OK";
            nativeError = 0;
            lock (InputWatchdogSync)
            {
                if (inputWatchdogWindow == IntPtr.Zero)
                {
                    return true;
                }

                if (inputWatchdogWindow != window ||
                    inputWatchdogProcessId != expectedProcessId)
                {
                    faultCode = "INPUT_WATCHDOG_SESSION_MISMATCH";
                    return false;
                }

                int releaseError;
                bool allReleased = ReleaseInputWatchdogEdgesLocked(out releaseError);
                for (int attempt = 0; !allReleased && attempt < 3; attempt++)
                {
                    Thread.Sleep(10);
                    allReleased = ReleaseInputWatchdogEdgesLocked(out releaseError);
                }

                faulted = inputWatchdogFaulted;
                faultCode = faulted ? inputWatchdogFaultCode : "OK";
                nativeError = faulted ? inputWatchdogNativeError : 0;
                if (!allReleased)
                {
                    return false;
                }

                StopInputWatchdogTimerLocked();
                inputWatchdogWindow = IntPtr.Zero;
                inputWatchdogProcessId = 0;
                inputWatchdogFaulted = false;
                inputWatchdogFaultCode = "OK";
                inputWatchdogNativeError = 0;
                return true;
            }
        }

        private static bool IsExtendedVirtualKey(ushort virtualKey)
        {
            return virtualKey == 0x21 || virtualKey == 0x22 ||
                   virtualKey == 0x23 || virtualKey == 0x24 ||
                   virtualKey == 0x25 || virtualKey == 0x26 ||
                   virtualKey == 0x27 || virtualKey == 0x28 ||
                   virtualKey == 0x2D || virtualKey == 0x2E ||
                   virtualKey == 0xA3 || virtualKey == 0xA5;
        }

        public static bool QuerySupportedInputState(
            ushort[] virtualKeys,
            out ControlledInputState state,
            out int nativeError)
        {
            nativeError = 0;
            HashSet<ushort> uniqueKeys = new HashSet<ushort>(virtualKeys ?? new ushort[0]);
            List<ushort> keysDown = new List<ushort>();
            foreach (ushort virtualKey in uniqueKeys)
            {
                if ((GetAsyncKeyState(virtualKey) & 0x8000) != 0)
                {
                    keysDown.Add(virtualKey);
                }
            }

            List<string> buttonsDown = new List<string>();
            int[] buttonVirtualKeys = new int[]
            {
                VK_LBUTTON, VK_RBUTTON, VK_MBUTTON, VK_XBUTTON1, VK_XBUTTON2
            };
            string[] buttonNames = new string[] { "left", "right", "middle", "x1", "x2" };
            for (int index = 0; index < buttonVirtualKeys.Length; index++)
            {
                if ((GetAsyncKeyState(buttonVirtualKeys[index]) & 0x8000) != 0)
                {
                    buttonsDown.Add(buttonNames[index]);
                }
            }

            state = new ControlledInputState
            {
                KeysDown = keysDown.ToArray(),
                MouseButtonsDown = buttonsDown.ToArray(),
                AnyDown = keysDown.Count > 0 || buttonsDown.Count > 0
            };
            return true;
        }

        public static bool QueryAllControlledInputState(
            out ControlledInputState state,
            out int nativeError)
        {
            return QuerySupportedInputState(CONTROLLED_VIRTUAL_KEYS, out state, out nativeError);
        }

        public static bool ReleaseAllSupportedInputs(
            ushort[] virtualKeys,
            out ControlledInputState postState,
            out int failedReleaseCount,
            out int nativeError)
        {
            failedReleaseCount = 0;
            nativeError = 0;
            HashSet<ushort> uniqueKeys = new HashSet<ushort>(virtualKeys ?? new ushort[0]);
            foreach (ushort virtualKey in uniqueKeys)
            {
                int releaseError;
                if (!SendKeyboard(
                        virtualKey,
                        true,
                        IsExtendedVirtualKey(virtualKey),
                        out releaseError))
                {
                    failedReleaseCount++;
                    if (nativeError == 0)
                    {
                        nativeError = releaseError;
                    }
                }
            }

            foreach (string button in new string[] { "left", "right", "middle", "x1", "x2" })
            {
                int releaseError;
                if (!SendMouseButton(button, true, out releaseError))
                {
                    failedReleaseCount++;
                    if (nativeError == 0)
                    {
                        nativeError = releaseError;
                    }
                }
            }

            int queryError = 0;
            ushort[] queriedKeys = uniqueKeys.Count == 0
                ? new ushort[0]
                : new List<ushort>(uniqueKeys).ToArray();
            postState = null;
            for (int attempt = 0; attempt < 10; attempt++)
            {
                QuerySupportedInputState(queriedKeys, out postState, out queryError);
                if (!postState.AnyDown)
                {
                    break;
                }

                if (attempt < 9)
                {
                    System.Threading.Thread.Sleep(10);
                }
            }
            if (nativeError == 0)
            {
                nativeError = queryError;
            }
            return failedReleaseCount == 0 && !postState.AnyDown;
        }

        public static bool ReleaseAllControlledInputs(
            out ControlledInputState postState,
            out int failedReleaseCount,
            out int nativeError)
        {
            return ReleaseAllSupportedInputs(
                CONTROLLED_VIRTUAL_KEYS,
                out postState,
                out failedReleaseCount,
                out nativeError);
        }

        private static bool SendSingleInput(INPUT input, out int nativeError)
        {
            if (input.type == INPUT_KEYBOARD)
            {
                input.data.ki.dwExtraInfo = EXECUTOR_INPUT_MARKER;
            }
            else if (input.type == INPUT_MOUSE)
            {
                input.data.mi.dwExtraInfo = EXECUTOR_INPUT_MARKER;
            }

            INPUT[] inputs = new INPUT[] { input };
            uint sent = SendInput(1, inputs, Marshal.SizeOf(typeof(INPUT)));
            if (sent != 1)
            {
                nativeError = Marshal.GetLastWin32Error();
                return false;
            }

            nativeError = 0;
            return true;
        }
    }
}
