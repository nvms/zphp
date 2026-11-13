// the win32 api zphp calls directly: processes and pipes for proc_open,
// virtual memory for the call regions, handle bookkeeping. declared here
// rather than taken from std.os.windows, which keeps only what std itself uses
const std = @import("std");

pub const HANDLE = std.os.windows.HANDLE;
pub const BOOL = c_int;
pub const TRUE: BOOL = 1;
pub const FALSE: BOOL = 0;
pub const DWORD = u32;

pub const INVALID_HANDLE_VALUE: HANDLE = @ptrFromInt(std.math.maxInt(usize));
pub const INFINITE: DWORD = 0xffffffff;
pub const WAIT_OBJECT_0: DWORD = 0;

pub const HANDLE_FLAG_INHERIT: DWORD = 0x1;
pub const DUPLICATE_SAME_ACCESS: DWORD = 0x2;

pub const GENERIC_READ: DWORD = 0x80000000;
pub const GENERIC_WRITE: DWORD = 0x40000000;
pub const FILE_SHARE_READ: DWORD = 0x1;
pub const FILE_SHARE_WRITE: DWORD = 0x2;
pub const OPEN_EXISTING: DWORD = 3;
pub const FILE_ATTRIBUTE_NORMAL: DWORD = 0x80;
pub const FILE_TYPE_PIPE: DWORD = 3;
pub const ERROR_BROKEN_PIPE: DWORD = 109;

pub const STD_INPUT_HANDLE: DWORD = @bitCast(@as(i32, -10));
pub const STD_OUTPUT_HANDLE: DWORD = @bitCast(@as(i32, -11));
pub const STD_ERROR_HANDLE: DWORD = @bitCast(@as(i32, -12));

pub const STARTF_USESTDHANDLES: DWORD = 0x100;
pub const NORMAL_PRIORITY_CLASS: DWORD = 0x20;
pub const CREATE_UNICODE_ENVIRONMENT: DWORD = 0x400;

pub const MEM_COMMIT: DWORD = 0x1000;
pub const MEM_RESERVE: DWORD = 0x2000;
pub const MEM_RELEASE: DWORD = 0x8000;
pub const PAGE_NOACCESS: DWORD = 0x01;
pub const PAGE_READWRITE: DWORD = 0x04;

pub const SECURITY_ATTRIBUTES = extern struct {
    nLength: DWORD,
    lpSecurityDescriptor: ?*anyopaque,
    bInheritHandle: BOOL,
};

pub const STARTUPINFOW = extern struct {
    cb: DWORD,
    lpReserved: ?[*:0]u16,
    lpDesktop: ?[*:0]u16,
    lpTitle: ?[*:0]u16,
    dwX: DWORD,
    dwY: DWORD,
    dwXSize: DWORD,
    dwYSize: DWORD,
    dwXCountChars: DWORD,
    dwYCountChars: DWORD,
    dwFillAttribute: DWORD,
    dwFlags: DWORD,
    wShowWindow: u16,
    cbReserved2: u16,
    lpReserved2: ?*u8,
    hStdInput: ?HANDLE,
    hStdOutput: ?HANDLE,
    hStdError: ?HANDLE,
};

pub const PROCESS_INFORMATION = extern struct {
    hProcess: HANDLE,
    hThread: HANDLE,
    dwProcessId: DWORD,
    dwThreadId: DWORD,
};

pub extern "kernel32" fn CloseHandle(handle: HANDLE) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetLastError() callconv(.winapi) DWORD;
pub extern "kernel32" fn FormatMessageW(flags: DWORD, source: ?*const anyopaque, message_id: DWORD, language_id: DWORD, buffer: [*]u16, size: DWORD, arguments: ?*anyopaque) callconv(.winapi) DWORD;
pub const FORMAT_MESSAGE_IGNORE_INSERTS: DWORD = 0x200;
pub const FORMAT_MESSAGE_FROM_SYSTEM: DWORD = 0x1000;
pub extern "kernel32" fn GetCurrentProcess() callconv(.winapi) HANDLE;
pub extern "kernel32" fn GetCurrentProcessId() callconv(.winapi) DWORD;
pub extern "kernel32" fn GetStdHandle(id: DWORD) callconv(.winapi) ?HANDLE;
pub extern "kernel32" fn SetHandleInformation(handle: HANDLE, mask: DWORD, flags: DWORD) callconv(.winapi) BOOL;
pub extern "kernel32" fn DuplicateHandle(source_process: HANDLE, source: HANDLE, target_process: HANDLE, target: *HANDLE, access: DWORD, inherit: BOOL, options: DWORD) callconv(.winapi) BOOL;
pub extern "kernel32" fn CreatePipe(read: *HANDLE, write: *HANDLE, attributes: ?*const SECURITY_ATTRIBUTES, size: DWORD) callconv(.winapi) BOOL;
pub extern "kernel32" fn CreateFileW(name: [*:0]const u16, access: DWORD, share: DWORD, attributes: ?*const SECURITY_ATTRIBUTES, disposition: DWORD, flags: DWORD, template: ?HANDLE) callconv(.winapi) HANDLE;
pub extern "kernel32" fn CreateProcessW(application: ?[*:0]const u16, command_line: ?[*:0]u16, process_attributes: ?*SECURITY_ATTRIBUTES, thread_attributes: ?*SECURITY_ATTRIBUTES, inherit_handles: BOOL, flags: DWORD, environment: ?*anyopaque, cwd: ?[*:0]const u16, startup: *STARTUPINFOW, info: *PROCESS_INFORMATION) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetExitCodeProcess(process: HANDLE, code: *DWORD) callconv(.winapi) BOOL;
pub extern "kernel32" fn WaitForSingleObject(handle: HANDLE, milliseconds: DWORD) callconv(.winapi) DWORD;
pub extern "kernel32" fn TerminateProcess(process: HANDLE, code: u32) callconv(.winapi) BOOL;
pub extern "kernel32" fn VirtualAlloc(address: ?*anyopaque, size: usize, allocation: DWORD, protect: DWORD) callconv(.winapi) ?*anyopaque;
pub extern "kernel32" fn VirtualFree(address: ?*anyopaque, size: usize, free_type: DWORD) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetFileType(handle: HANDLE) callconv(.winapi) DWORD;
pub extern "kernel32" fn PeekNamedPipe(pipe: HANDLE, buffer: ?*anyopaque, size: DWORD, bytes_read: ?*DWORD, available: ?*DWORD, left: ?*DWORD) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetFileAttributesW(path: [*:0]const u16) callconv(.winapi) DWORD;
pub extern "kernel32" fn SetFileAttributesW(path: [*:0]const u16, attributes: DWORD) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetEnvironmentVariableW(name: [*:0]const u16, buffer: ?[*]u16, size: DWORD) callconv(.winapi) DWORD;
pub extern "kernel32" fn SetFilePointerEx(file: HANDLE, distance: i64, new_pointer: ?*i64, method: DWORD) callconv(.winapi) BOOL;
pub extern "kernel32" fn SetConsoleCtrlHandler(handler: ?*const fn (DWORD) callconv(.winapi) BOOL, add: BOOL) callconv(.winapi) BOOL;
pub extern "kernel32" fn LoadLibraryW(name: [*:0]const u16) callconv(.winapi) ?HANDLE;
pub extern "kernel32" fn GetProcAddress(module: HANDLE, name: [*:0]const u8) callconv(.winapi) ?*anyopaque;
pub extern "kernel32" fn FreeLibrary(module: HANDLE) callconv(.winapi) BOOL;

// a loaded dll, with std.DynLib's interface
pub const DynLib = struct {
    module: HANDLE,

    pub fn open(path: []const u8) !DynLib {
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buf);
        const wide = std.unicode.wtf8ToWtf16LeAllocZ(fba.allocator(), path) catch return error.NameTooLong;
        return .{ .module = LoadLibraryW(wide.ptr) orelse return error.FileNotFound };
    }

    pub fn lookup(self: *DynLib, comptime T: type, name: [:0]const u8) ?T {
        return @ptrCast(@alignCast(GetProcAddress(self.module, name.ptr) orelse return null));
    }

    pub fn close(self: *DynLib) void {
        _ = FreeLibrary(self.module);
        self.* = undefined;
    }
};
