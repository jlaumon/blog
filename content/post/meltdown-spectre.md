+++
date = "2018-01-21T10:33:38+01:00"
description = ""
tags = [ "Security" ]
title = "Meltdown and Spectre explained"
draft = true

+++

You may have heard of **Meltdown** and **Spectre**. In January, these two new **security vulnerabilites** were made public, and it was kind of a big deal: all modern processors were more or less vulnerable, all systems affected, they could steal your passwords and everything.

Things have settled down a little bit since then; security patches have been released, no actual attacks have been reported. But still, discoveries of that scale are not common, so I was curious: How do they work? 

The explanations I could find on the Internet came in two flavors:
the one for security experts and academics ([extremely technical, very hard to follow](https://googleprojectzero.blogspot.fr/2018/01/reading-privileged-memory-with-side.html)) and the ones for scared customers ([that will make you doubt everything you known about computers](https://www.youtube.com/watch?v=syAdX44pokE)).

So I decided to write my own, for people that have some knowledge about CPUs, but no interest in actually exploiting the vulnerability.

<img style="display: block; margin-left: auto; margin-right: auto;" src="images/spectre.png">

<!--more-->


## Background 

Some background knowledge is necessary, so I'm going to explain some of it here, but not all. 

Note that everything I write here only applies to *modern* CPUs/systems (eg. computer/laptops/mobiles/consoles, but not eg. gameboys).

### Virtual memory

The addresses you see in the debugger when you write a program is called a **virtual address**. It's not the actual address where the data resides in the RAM, it's a mapping created by the kernel (the core of the OS). The actual address is called the **physical address**. The memory is mapped in chunks, called  **memory pages**, of usually 4KB (but they can be larger).

The kernel manages these mappings in what is called a **page table**. The translation from virtual to physical is done automatically by the CPU, in hardware. Each process has its own page table, and can only access the memory through virtual addresses. The kernel is the only one that can see, and deal with, the page table and physical addresses.

Each page can have different access protections, pretty much like files. Some of them can be read-only, some of them can only be read with the right access level (usually meaning that you need to be inside the kernel to do so).

If a process tries to access an address that is protected, or that is not mapped to a physical address, a **page fault** is triggered. It behaves like an exception: if uncatched, the program crashes.

So, to recap, a process cannot access other processes' memory because it doesn't have any mappings for it in its page table. Knowing the virtual address of another process' data is useless since it doesn't point anywhere without the proper entry in the page table. A process also can't read the kernel's memory because, even if there may be an entry in the page table for it, it's protected.

That is some strong security, right? Note that virtual memory is also useful for other reasons (notably [paging](https://en.wikipedia.org/wiki/Paging), [but not only](http://ourmachinery.com/post/virtual-memory-tricks/)).

## Meltdown

This is the simplest one, and is specific to modern Intel processors.

### The attack

Consider the following code snippet, where `kernel_mem` points to some data belonging to the OS:

```c++
#define CACHELINE 64
char* kernel_mem = ...
char user_mem[256 * CACHELINE];

int index = kernel_mem[0] * CACHELINE; // BOOM
int value = user_mem[index];
```

It should read `user_mem` at an index depending on the value read from `kernel_mem`. Except, like I said in the paragraph above, the memory pages belonging to the OS are protected, so the line where `kernel_mem` is read will trigger a page fault (hence the comment "BOOM") and the line where `user_mem` is read will never be executed.

Or will it? 

The thing is, modern CPUs don't really execute instructions one at a time (that's too slow), instead, they are **pipelined**. Each instruction passes through a certain number of **stages**, each corresponding to a component within the CPU core. The goal being to try to keep each component as busy as possible by allowing multiple instructions to be *in flight* simultaneously.

There are limits to that simultaneity however, and here, reading `user_mem` clearly depends on reading the value of `kernel_mem` *first*. But if the value is in the cache, it can be available very quickly, allowing the second instruction to start executing *before* the memory access rights have been validated (that's the Intel specific part).

Of course after a while, the access rights check returns a failure, the pipeline is flushed (meaning the reading of `user_mem` is aborted before being finalized) and the page fault interrupt handler is executed.

But, because the reading of `user_mem` was partially executed, the cache line containing `user_mem[index]` was loaded into the cache!

All the attacker has to do after that, is read `user_mem` at every multiple of the cache line size, and measure how long takes every read. If one read is significantly faster than the others, it means that this cache line was in the cache, and the value of `kernel_mem[0]` can be deduced from the index. 

Repeat the process to leak an arbitrary amount of data and that's pretty much it. 

### Mitigation

Simplest attack, but also simplest fix: all the major OSes decided to just remove all the kernel pages from the page table, rendering the attack impossible.

This has a cost however: every time a process does a **syscall** (ie. calling a function inside the kernel), the kernel will have to map all its memory pages, and then unmap them before returning to the process that called it. The cost is mainly visible for servers that need to do a lot of I/O, as they usually involve lots of syscalls.


## Spectre

There are two variants for Spectre.

### Variant 1: Bounds check bypass

This time, the attack code has to run inside the *victim*'s environment, which could be the kernel or another process. Since the attacker needs to have some control over what code is executed, it's a lot easier if the victim is an interpreter or a JIT engine, such as a javascript engine in a web browser or the [eBPF interpreter](https://opensource.com/article/17/9/intro-ebpf) in the linux kernel.

Such interpreters need to have a lot of safeties, to make sure a user cannot harm the host (intentionally or not). One of such safeties is testing every array access to make sure it is not *out-of-bounds*. And this is exactly what this first variant of Spectre is about: **bypassing bounds checks**.

Consider this code, which is very similar to the example for Meltdown, except it's supposed to be run by the victim:

```C++
#define CACHELINE 64

char* victim_array = ...;
int   victim_array_size = ...;

char attacker_mem[256 * CACHELINE];
int  attacker_offset = ...; // Greater than victim_array_size

if (attacker_offset < victim_array_size) 
{
    char out_of_bounds_value = victim_array[attacker_offset];
    char value = attacker_mem[out_of_bounds_value * CACHELINE];
}
```

If `attacker_offset` is greater or equal to `victim_array_size`, the code inside the if will never be executed, right?

Except modern CPUs have another secret weapons: branch predictors. The branch predictor is a component that will, as the name suggest, try to guess the result of a branch (eg. an if) before its condition is actually evaluated. Based on the guess, the CPU can start executing instructions that are after the branch immediately, thus keeping its pipeline fed all the time. This is called **speculative execution**. 

Of course, if after evaluating the branch the branch predictor is proved wrong, the pipeline will be flushed and all the intermediary results will be discarded. Except that... some values may have been loaded into the cache, again!

So, in this example, if the branch predictor can be trained to predict a `true` (by running the code many times with a valid `attacker_offset`), and if `victim_array_size` is not in the cache (so that the condition takes a long time to evaluate), the code inside the if will be speculately executed, loading values of `attacker_mem` into the cache and indirectly leaking *out-of-bounds* values from `victim_array`, like Meldown did for `kernel_mem`. If you go far enough out of bounds, you can leak anything in the victim's memory.

### Variant 2: Branch target injection

There are several types of branches: an `if` statement is what is called a conditional branch, the processor will jump to the `else` block if the condition is `false`, but the position of the else block is known, it doesn't need to be evaluated by the CPU. There is another type of branch, called **indirect branches**, where the target is not known in advance because it is the result of some calculation. For example, function pointers, or virtual calls.

The branch predictor also knows how to predict the target of these branches, again, to make sure the CPU can start executing the intructions that come after it without having to wait.

This second variant of Spectre is all about training the branch predictor to predict a wrong address for an indirect branch run by the kernel. And at this wrong address, the attacker will put the same cache-leaking code as the first variant.



direct branches mean that the processor will jump to a known position to execute the code there (for example, a function call, the processor will jump at the function's address), conditional branches mean that it will jump if a certain condition is met (for example, in an `if` statement, the processor will jump to the `else` block if the condition is false), and finally indirect branches, which mean that the processor will jump at a position that will only be known 

### Mitigation

The web browsers, being one of the main targets of the first variant, all decided to reduce the resolution of the timers available in javascript. It doesn't prevent the speculative execution from leaking data into the cache, but the timers are not precise enough to measure if values are in the cache or not.


---

read kernel address from user space, use result to compute a user address and read it; it generates a page fault but you know if value was 1 or 0 depending on whether the user address is in the cache

can avoid page fault by putting the code inside an if that will not be taken

2- spectre 1

same thing but from kernel space (no page fault in this case, the if is required)
hard to find code in the kernel that can do that, but hard to patch them all
interpreter / JIT can be used to generate this kind of code pattern
could be web browser instead of kernel, javascript instead of user space program

3- spectre 2

same thing except instead of having the leaking code inside an if, you jump to it with an indirect branch
big improvement: the leaking code can be anywhere in the kernel/target code (and there is plenty of code using this pattern)
but also very hard to train the branch predictor to make it jump to this address

mitigation: 
- disabling speculative execution around indirect branches in the kernel, if supported by CPU
- retpoline, software construct using call+ret to make speculative execution execute an infinite loop