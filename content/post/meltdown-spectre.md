+++
date = "2018-03-25T13:59:49+02:00"
description = "Meltdown and Spectre explained to people that have some knowledge about CPUs but no interest in exploiting the vulnerabilities."
tags = [ "Security" ]
title = "Meltdown and Spectre explained, again"

+++

You may have heard of **Meltdown** and **Spectre**. In January, these two new **security vulnerabilities** were made public, and it was kind of a big deal: all modern processors were more or less vulnerable, all systems affected, they could steal your passwords and everything.

Things have settled down a little bit since then; security patches have been released and no actual attacks have been reported. But still, discoveries of that scale are not common, so I was curious: How do these vulnerabilities work? 

The explanations I could find on the Internet came in two flavors:
the one for security experts ([extremely technical, very hard to follow](https://googleprojectzero.blogspot.fr/2018/01/reading-privileged-memory-with-side.html)) and the ones for scared customers ([that will make you doubt everything you known about computers](https://www.youtube.com/watch?v=syAdX44pokE)).

So I decided to write my own: for people that have some knowledge about CPUs, but no interest in actually exploiting the vulnerabilities.

![Spectre](images/spectre.png)

<!--more-->


## Background knowledge: Virtual memory

Some introduction is necessary to understand the rest of the article. I hope you know that modern [CPUs have caches](https://en.wikipedia.org/wiki/CPU_cache) for memory accesses. What you may not know (and that I'm going to explain here), is that they also use a [virtual memory](https://en.wikipedia.org/wiki/Virtual_memory) system. 

The addresses you see in the debugger when you debug a program is called a **virtual address**. It's not the actual address where the data resides in the RAM, it's a mapping created by the kernel (the core of the OS). The actual address is called the **physical address**. The memory is mapped in chunks, called  **memory pages**, of usually 4KB (but they can be larger).

The kernel manages these mappings in what is called a **page table**. The translation from virtual to physical is done automatically by the CPU, in hardware, based on this table. **Each process has its own page table**, meaning several processes can use the same virtual address without overwriting each other's memory: each will be mapped to a different physical address. User processes can only access the memory through virtual addresses. The kernel is the only one that can see, and deal with, the page table and physical addresses.

Each page can also have access protections, pretty much like files. Some of them can be read-only, some of them can only be read with the right access level (usually meaning that you need to be inside the kernel to do so).

If a process tries to access an address that is protected, or that is not mapped to a physical address, a **page fault** is triggered. It behaves like an exception: if uncatched, the program crashes.

So, to recap, **a process cannot access other processes' memory** because it doesn't have any mappings for it in its page table. **A process also can't read the kernel's memory**, because even if there may be an entry in the page table for it, it's protected.

That is some strong security, right? Note that virtual memory is also useful for reasons other than security ([paging](https://en.wikipedia.org/wiki/Paging) and [others](http://ourmachinery.com/post/virtual-memory-tricks/)), but it's off-topic here.

## Meltdown

This attack was dubbed "Variant 3: rogue data cache load" in the initial paper, and thus always explained last in every article I could find. But since it's the simplest one, we're going to cover it first.

It was initially discovered on Intel processors, but ARM admitted some of their processors are also affected. AMD CPUs are, however, apparently not vulnerable.

### The attack

Consider the following code snippet, where `kernel_mem` points to some data belonging to the OS:

```c++
#define CACHELINE 64
char* kernel_mem = ...
char user_mem[256 * CACHELINE];

int index = kernel_mem[0] * CACHELINE; // BOOM
int value = user_mem[index];
```

It should read `user_mem` at an index depending on the value read from `kernel_mem`. Except, like I said in the paragraph above, the memory pages belonging to the kernel are protected, so the line where `kernel_mem` is read will trigger a page fault (hence the comment "BOOM") and the line where `user_mem` is read will never be executed.

Or will it? 

The thing is, modern CPUs don't really execute instructions one at a time (that's too slow), instead, they are **pipelined**. Each instruction passes through a certain number of **stages**, each corresponding to a component within the CPU core. The goal being to try to keep each component as busy as possible by allowing multiple instructions to be *in flight* simultaneously.

There are limits to that simultaneity however, and here, reading `user_mem` clearly depends on reading the value of `kernel_mem` *first*. But if the value is in the cache, it can be available very quickly, allowing the second instruction to start executing **before the memory access rights have been validated** (and that's what makes Intel/ARM CPUs vulnerable).

Of course after a while, the access rights check returns a failure, the pipeline is flushed (meaning the reading of `user_mem` is aborted before being finalized) and the page fault interrupt handler is executed.

But, because the reading of `user_mem` was partially executed, the cache line containing `user_mem[index]` was loaded into the cache!

All the attacker has to do after that, is read `user_mem` at every multiple of the cache line size, and measure how long takes every read. If one read is significantly faster than the others, it means that this cache line was in the cache, and the value of `kernel_mem[0]` can be deduced from the index of the read. 

Repeat the process to leak an arbitrary amount of data and that's pretty much it. 

### Mitigation

Simplest attack, but also simplest fix: all the major OSes decided to just remove all the kernel pages from the page table, rendering the attack impossible.

This has a cost however: every time a process does a **syscall** (ie. calling a function inside the kernel), the kernel will have to map all its memory pages, and then unmap them before returning to the process that called it. The cost is mainly visible for servers that need to do a lot of I/O, as they usually involve lots of syscalls. Games are almost not impacted as they usually try to minimize syscalls anyway.

Hopefully the next generation of Intel/ARM CPUs will fix the vulnerability entirely and the costly patches in the OSes will not be necessary anymore.

## Spectre

This time, instead of trying to bypass the different protections set up by the virtual memory, the attack goal will be to run code directly inside the *victim*'s environment (which could be the kernel or another process), to take advantage of their access rights.

### Variant 1: Bounds check bypass

To have some control over the code executed, this variant will target principally [interpreters](https://en.wikipedia.org/wiki/Interpreter_(computing)) and [just-in-time compilation](https://en.wikipedia.org/wiki/Just-in-time_compilation) engines that execute "untrusted" code provided by a user. For example, a javascript engine in a web browser or the [eBPF interpreter](https://opensource.com/article/17/9/intro-ebpf) in the linux kernel.

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

Except modern CPUs have another secret weapons: **branch predictors**. The branch predictor is a component that will, as the name suggest, try to guess the result of a branch (eg. an if) before its condition is actually evaluated. Based on the guess, the CPU can start executing instructions that are after the branch immediately, thus keeping its pipeline fed all the time. This is called **speculative execution**. 

Of course, if after evaluating the branch the branch predictor is proved wrong, the pipeline will be flushed and all the intermediary results will be discarded. Except that... some values read by the speculative execution may have been loaded into the cache! Again!

So, in this example, if the branch predictor can be trained to predict a `true` (by running the code many times with a valid `attacker_offset`), and if `victim_array_size` is not in the cache (so that the condition takes a long time to evaluate), the code inside the if will be speculatively executed, loading values of `attacker_mem` into the cache and indirectly leaking *out-of-bounds* values from `victim_array`. If you go far enough out of bounds, you can leak anything in the victim's memory. And since it's only speculatively executed, there's no risk of triggering a page fault if the address was not valid.

### Mitigation for Variant 1

The web browsers, being one of the main targets, all decided to reduce the resolution of the timers available in javascript. It doesn't prevent the speculative execution from leaking data into the cache, but the timers are not precise enough to measure if values are in the cache or not.

The main other alternative is to prevent the speculative execution after a vulnerable bound check. Both x86 and ARM processors have some capability for *serializing* memory reads with some kind of fence instruction. The addition of these instructions can be done semi-automatically by the compiler, but the vulnerable code still needs to be identified and recompiled with the right compiler option.

The cost of this mitigation should be negligible since the number of vulnerable branches is relatively low.

### Variant 2: Branch target injection

Brief intermission to explain another important technical detail: **there are several types of branches**. 

An `if` statement is what is called a conditional branch, the processor will jump to the `else` block if the condition is `false`. In this case, the position of the else block is fixed, it doesn't need to be evaluated by the CPU. There is another type of branch, called **indirect branches**, where the target is not known in advance because it is the result of some calculation. For example, calling a **function pointer**, making a **virtual call**, or even executing a **`return` statement** (since the return address depends on the caller).

The branch predictor also knows how to predict the target of these branches. Again, it's to make sure the CPU can start executing the instructions that come after it without having to wait.

This **second variant of Spectre** is all about training the branch predictor to make an indirect branch - run by the kernel - jump to the attacker's code, where the same old cache leaking trick will be used.

Seems easy? In the first variant, it *was* easy because you could just run the code many times with a value that would make the `if` condition evaluate to `true`, until the branch predictor would predict the next as `true`. But here, it's not just `true`/`false`, **the branch predictor has to predict a whole address**... and we can't make the branch in the kernel jump to that address to train it.

Fortunately (or unfortunately), there are some implementations details that can be exploited. Branch predictors implementations differ for each CPU vendor/each CPU generation, but they all rely more or less on the same base: they have some kind of **cache that stores the histories of branches** and use it for their predictions. 

In the cache, **the branches are identified by their address** in the code, but a common optimization is to use only some bits of the address, or to hash the address into a value that uses a smaller number of bits, or both; saves space in the cache and helps making the hardware faster. But that also means that the predictor won't be able to distinguish branches that end up with the same identifier, and these branches will influence the each others predictions. That looks like a sensible optimization: worst case, some branches are mispredicted. *No big deal, heh?*

To train the branch predictor, the attacker only has to run a *second program* with **a branch whose address conflicts with the target kernel branch** of the *first program*, and make it jump repeatedly to the address of the cache-leaking code. And bingo!

![Training](images/training.gif)

### Mitigation for Variant 2

This variant is the hardest to set up. The attacker needs to know the details of the victim's branch predictor, and there are a few other details that I omitted for simplicity. But it's also the most powerful and the hardest to fix: **virtually all indirect branches are vulnerable**.

Intel and AMD published microcode updates for their x86 CPU, to add the capability to disable speculative execution around indirect branches and to flush the branch predictor history (called [IBPB, IBRS and STIBP](https://lkml.org/lkml/2018/1/22/598)). But these features are *painfully* expensive on current generations of CPUs, so it was not realistic to rely only on that. [Linus Torvalds was not happy](https://www.theregister.co.uk/2018/01/22/intel_spectre_fix_linux/). Also, [Intel initial update was buggy](https://www.theverge.com/2018/1/29/16944326/microsoft-spectre-processor-bug-emergency-windows-update-reboot-fix), that didn't help.

Luckily, there are also software workarounds, and those are a lot cheaper (although they don't cover 100% of the cases, so the new CPU features described above are still useful). These workaround either use the same kind of barrier instructions as the mitigation for the 1st variant, or, in the case of Google's [retpoline](https://support.google.com/faqs/answer/7625886), they exploit implementation details of the branch predictor to trick the CPU into speculatively execute an infinite loop. Talk about irony!

All the major OSes published patches that used both techniques to mitigate the vulnerabilities, but there is a *lot* of code to patch out there, so it's possible we'll continue to hear about this for some time. Depending on you CPU, the mitigations for this vulnerability are probably the most expensive of the three. But as for Meltdown, mostly the programs that do a lot of syscalls are impacted.

## Conclusion?

Reading about a good hack can be frightening, and at the same time I find it very entertaining. I hope you enjoyed reading this article! 

CPUs are fascinatingly complex nowadays, and maybe sometimes [we trust them](https://www.youtube.com/watch?v=ajccZ7LdvoQ) a little bit [too much](https://danluu.com/cpu-bugs/). If you want to know more about branch predictors (and I know you do, because they're awesome), I recommend this [article from Dan Luu](https://danluu.com/branch-prediction/) which explains a lot of the different techniques in a very clear manner.