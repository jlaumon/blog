+++
date = "2024-12-30T10:03:00+02:00"
description = "Bedrock is a C++ STL replacement library. It comes with several specialized allocators that are faster than using the heap, while still being convenient to use."
tags = ["Bedrock", "C++"]
title = "The allocators of Bedrock, my own C++ STL alternative"
draft = false

+++

For some reason, I started making my own **STL replacement library** about 2 months ago. It's called **Bedrock**. It's [available on github](https://github.com/jlaumon/Bedrock) under a copyleft license.

I don't expect it to become very useful to anyone, but making it has been a lot of fun, so I thought I'd share some of the experience. 

Today we're talking **allocators**. 

![Bedrock](images/Microsoft-Fluentui-Emoji-Flat-Rock-Flat.256.png)

<!--more-->

## TempString 

[Asset Cooker](post/asset-cooker-1/) (my previous pet project) needs a lot of **temporary strings**, so at the time I made a `TempString` class that contained a **fixed size buffer**, with a size configurable via a template parameter. I was not very happy with that solution though, because it meant I had to think about how large each string could be and often reserve much larger buffers than necessary. 

So when I started **Bedrock**, I went in a different direction. I wrote a regular `String` class and a `TempAllocator`. That allocator gets memory from a **thread local scratch buffer**, and falls back to allocating from the heap if it runs out. Allocating is normally very **fast**, it's just incrementing an integer. And the last allocation can be resized freely, that's a great advantage: no need to re-allocate and copy the data of a `Vector` or `String` when growing it! That's perfect for **temporary/stack variables** since it's usually the last one that gets resized. 

In terms of allocator interface, it means that instead of just the usual `Allocate` and `Free`, there's also `TryRealloc`. That function tries to **resize an existing memory block**, but unlike `realloc`, it returns false instead of allocating a new block when it can't.

## Out of order frees

It's all well and good, but there is one annoying limitation with this `TempAllocator`: de-allocations have to happen in the **reverse order** of the allocations. Again that’s fine most of the time for temporaries, but it becomes a problem when returning Temp containers or otherwise moving them.

So, for that case, I added a **small array** for storing blocks that were freed out of order. Whenever another block is freed, the allocator checks whether these pending blocks can be freed as well. The blocks are **stored sorted**, and **contiguous blocks are merged**, so only the first one in the array actually needs to be checked. Out of order frees are a rare case, so the performance of that code doesn't matter too much, but I tried to make sure that it **stays out of the hot path** with `[[unlikely]]` and `no_inline`. 

Since contiguous pending blocks are merged, even just 16 slots is plenty. But it's a fixed-size array, if it gets full, it **crashes**.  

## MemArena

At this point, `TempAllocator` was already **extremely convenient**, so I added handy **typedefs** for `TempString`, `TempVector` and `TempHashMap`. 

But I also wanted another allocator that could use **virtual memory** to grow its buffer instead (like AssetCooker’s [VMemArray](post/asset-cooker-1/)). That's a bit different from `TempAllocator` since instead of allocating from a **thread local buffer**, it would be allocating from a buffer **embedded inside the allocator**. 

Most of the allocation logic is identical however, so I moved it to a [`MemArena`](https://github.com/jlaumon/Bedrock/blob/db1402b4bdbaa68e9f1f6959c4469e665f0dc943/Bedrock/MemoryArena.h#L44) struct. `TempAllocator` uses a global thread local `MemArena`, [`VMemAllocator`](https://github.com/jlaumon/Bedrock/blob/db1402b4bdbaa68e9f1f6959c4469e665f0dc943/Bedrock/MemoryArena.h#L207) contains a `VMemArena`, derived from MemArena, which grows when it runs out. And… it just worked?

The only complication was that the array of pending frees was bloating the `VMemAllocator` (128 extra bytes) while being completely **unnecessary**: a `Vector` or `String` uses a single allocation so it's **always the last one**. Fortunately it was relatively easy to get rid of it with [template shenanigans](https://github.com/jlaumon/Bedrock/blob/db1402b4bdbaa68e9f1f6959c4469e665f0dc943/Bedrock/MemoryArena.h#L28).

## FixedMemArena

Drunk with meta programming power I thought: how much would it take to get my initial fixed-size String back? Turns out very little! [`FixedAllocator`](https://github.com/jlaumon/Bedrock/blob/db1402b4bdbaa68e9f1f6959c4469e665f0dc943/Bedrock/Allocator.h#L91) has a **fixed-size buffer** and a `MemArena` that is initialized with it, and that works. `FixedVector` and `FixedString` use this allocator. 

Note, though, that it's **not the most optimal** fixed-size container implementation: there's still a **pointer to the data array**, instead of the **array being used directly**. This **extra indirection** has an impact on the resulting machine code. 

It is however extremely easy to make a slightly different allocator that **falls back to using the heap** when the fixed buffer runs out (like `TempAllocator` does).

## Last one

Last variant I added just for the hell of it, is an [`ArenaAllocator`](https://github.com/jlaumon/Bedrock/blob/db1402b4bdbaa68e9f1f6959c4469e665f0dc943/Bedrock/Allocator.h#L38) that only **keeps a pointer to a MemArena**. That allows **allocating multiple containers** from the **same arena**, and I guess is what is most commonly called an **arena allocator**. The same can be done with a `VMemArena`, and that's what [`VMemHashMap`](https://github.com/jlaumon/Bedrock/blob/db1402b4bdbaa68e9f1f6959c4469e665f0dc943/Bedrock/HashMap.h#L617C63-L617C88) to allocate its two `Vectors` from the same memory block.

To be honest, I find it a bit **cumbersome** to set the arena on every container before using them, and it's opening doors to **ownership issues** (eg. what if the arena is destroyed before the vector), so I'm not sure I'm going to use a lot. Maybe, it'd be more convenient to set a "current arena" in a thread local pointer to make every `ArenaVector` automatically use it? But I guess I need a use case to try it first. This could be the base for a future `FrameAllocator` as well. 

## Summary 

Let's recap! What I have so far in Bedrock:

- `Vector`: uses the heap like std::vector would. 
- `TempVector`: uses a thread local arena, and can fall back to using the heap. 
- `VMemVector`: uses an internal arena that can grow by committing more virtual memory. 
- `FixedVector`: uses an internal arena that points to an internal fixed-size buffer. 
- `ArenaVector`: uses an external arena. 

That's all for now! I will try to write at least another article about the [`HashMap`](https://github.com/jlaumon/Bedrock/blob/db1402b4bdbaa68e9f1f6959c4469e665f0dc943/Bedrock/HashMap.h#L80), because I find the details interesting. 

--

If you have questions, these days I’m on [Bluesky](https://bsky.app/profile/jeremy.laumon.name).
