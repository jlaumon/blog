+++
date = "2025-04-21T17:14:00+02:00"
description = "D3D12 Resource States rules are complicated, especially around state promotion and decay, but this article is helpful summary."
tags = ["GPU", "D3D12"]
title = "D3D12 Resource States Cheat Sheet"
draft = false

+++

The D3D12 Transition barriers may look simple at first glance, but once you consider **state promotion** and interactions with **copy queues**, there are quite a lot of subtle rules. 

The documentation is pretty complete, but also a bit scattered and confusing. 

I wished several times I had a **cheat sheet**, and had instead to rely on my **old comments** and testing things with the **debug layer** enabled. This article is an attempt at helping future me :) 

<!--more-->

## The Basics 

Each subresource has a state. **Buffer** resources always have a single subresource, but **Textures** can have multiple ones (one per mip per array slice, etc.).

Some states are **read-only**, some are **writable**. Subresources can either be in a combination of read-only states, or in one writable state. 

To change a subresource state, a Transition barrier is generally used. But as we'll see, they can sometimes be omitted, and that can make a big difference in **performance**. 

Last important point: **Copy queues are special**. Subresources actually have a separate state on Copy queues. And before being used on a Copy queue, a subresource must be transitioned to `COMMON` on a Direct/Compute queue. More on that later. 

## Promotion and Decay 

Under some conditions, subresources in the `COMMON` state can **implicitly transition** (ie. be **promoted**) to a different state, based on how they're used. The inverse can also happen, where subresources in a different state than `COMMON` can **decay** back to `COMMON` automatically. 

Buffers and Textures work in pretty different ways in that regard, so I'm going to treat them separately for clarity. I'm also going to ignore “simultaneous-access textures”, because why would you use them.

### Buffers

Buffers in the `COMMON` state can be **promoted to any state**, always. 

If they get promoted to a read-only state, they can then be used in other read-only states without a barrier; the read-only states accumulate. Using them in a writable state after that requires a Transition barrier, but the `BeforeState` of the barrier can be left to `COMMON`. 

If they get promoted to a writable state, any further state change requires a barrier. The `BeforeState` of the barrier can also be left to `COMMON` in that case.

Buffers decay back to `COMMON` at the end of an ExecuteCommandLists, always.

### Textures

Promotions for Textures are more **limited** and more **complicated**.

Texture subresources in the `COMMON` state can **only** be promoted to read-only states or `COPY_DEST`. 

Like for Buffers, if they get promoted to a read-only state, they can then be used in other read-only states without a barrier. Using them in a writable state after that requires a Transition barrier and the `BeforeState` of the barrier can be left to `COMMON`. 

If they get promoted to `COPY_DEST`, any further state change requires a barrier. The `BeforeState` of the barrier can also be left to `COMMON` in that case.

Texture subresources can also decay back to `COMMON` at the end of an ExecuteCommandLists, but the rules are different depending on the queue type:

 - On a **Copy queue**, they always decay back to `COMMON`
 - On a **Direct/Compute queue**, they only decay if they are in a promoted read-only state. So if you used a barrier, there's no decay 

## Interactions with Copy Queues

Subresources have to be in `COMMON` state (on Direct/Compute queues) before they can be used on Copy queues, but promoted states still count as `COMMON`! 

This means that as long as a subresource is in a promoted state, it's possible to use it on a Copy queue and on a Direct/Compute queue **at the same time**. One of the queues can even be **writing** to it! 

There are some **restrictions**: only one queue can write at a time, and the bytes written should not be read by the other queues (synchronization with fences is still required to make sure the writes become visible to the other queues). 

In practice, that means you can, for example:
 - sub-allocate your meshes in a large Buffer, and use a Copy queue to upload new meshes while the Direct queue is rendering the pre-existing meshes
 - defragment heaps by copying Textures from one heap to another on a Copy queue while the Direct queue reads the (source) Textures

And I haven't tried it (yet), but it should even be possible to asynchronously upload parts of a Texture atlas on a Copy queue while the Direct queue reads from different parts of the atlas. 

## Enhanced barriers? 

Enhanced barriers should help make this less confusing (if not less complicated) since many of the strange rules of resource states are about emulating layout transitions, and they become explicit instead. I haven't had time to really dig into them yet, so I can't say for sure. 

Sadly there are still drivers out there that do not support them, drivers that are out of support and will only go away when their user replaces the hardware. But we're getting there.

## Sources

- [Implicit State Transitions](https://learn.microsoft.com/en-us/windows/win32/direct3d12/using-resource-barriers-to-synchronize-resource-states-in-direct3d-12#implicit-state-transitions)
- [Multi-queue Resource Access](https://learn.microsoft.com/en-us/windows/win32/direct3d12/user-mode-heap-synchronization#multi-queue-resource-access)
- [Resource State Promotion and Decay](https://microsoft.github.io/DirectX-Specs/d3d/D3D12EnhancedBarriers.html#resource-state-promotion-and-decay)



