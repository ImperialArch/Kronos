const std = @import("std");
const windows = std.os.windows;

extern "kernel32" fn ExitThread(dwExitCode: windows.DWORD) callconv(windows.WINAPI) noreturn;

pub fn main() !void {
    std.debug.print("Hello world test - Reflective loading works!\n", .{});
    
    ExitThread(0); // exit thread only so it doesn't kill our process 
}