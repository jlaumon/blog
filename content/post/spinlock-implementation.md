+++
date = "2017-12-31T13:03:00+01:00"
description = "Spin Lock implementation tricks from Naughty Dog's lead programmer Jason Gregory."
tags = ["Engine", "Concurrency", "C++"]
title = "Spin Lock Implementation"

+++

I attended a [Game Connection master class](https://www.game-connection.com/masterclasses/) this year again. This time it was with [Jason Gregory](http://www.gameenginebook.com/bio.html) (Lead Programmer at [Naughty Dog](https://www.naughtydog.com/)) on concurrent programming, and it was very interesting. 

I won't give a full account because we saw *way* too many things (500 slides!).

Instead, I'll just write about a few [spin lock](https://en.wikipedia.org/wiki/Spinlock) implementation tricks that he showed us.

<!--more-->

## The spin lock
Here is the spin lock that we had at Pastagames. It's pretty a straightforward (one could almost say naive) implementation:

```c++
void Lock(AtomicI32& _spinLock)
{
	for (;;)
	{
		i32 expected = 0;
		i32 store = 1;
		if (_spinLock.compareExchange_Acquire(expected, store))
			break;
	}
}
```

It tries to exchange a 0 with a 1 in an atomic integer. 0 means it's unlocked, 1 means it's locked. If the value inside the atomic was already 1 (ie. already locked by someone else), it loops and tries again. `AtomicI32` is a custom type, but it's the same idea as `std::atomic<int>`.

And here is the new and improved version based on Naughty Dog's spin lock that Jason Gregory showed us:

```c++
void Lock(AtomicI32& _spinLock)
{
	for (;;)
	{
		if (_spinLock.load_Acquire() == 0)
		{
			i32 expected = 0;
			i32 store = 1;
			if (_spinLock.compareExchange_Acquire(expected, store))
				break;
		}
		EMIT_PAUSE_INSTRUCTION();
	}
}
```

## Take a break

The first obvious difference is this `EMIT_PAUSE_INSTRUCTION` macro. On x86/x64, it translates into the [\_mm_pause()](https://software.intel.com/en-us/node/524249) intrinsic, which in turn emits an instruction called `PAUSE`.

This `PAUSE` instruction helps the CPU understand it's inside a spin lock loop: instead of speculatively execute many iterations of the loop, it's going to relax and wait for the result of the current iteration before starting the next. It saves energy, leaves more resources for the other thread if the CPU supports hyperthreading, and also avoids costly pipeline flushes when the atomic is written to by another thread.

*Note: Other CPU architectures may have a similar instruction, although their actual effect may be slightly different; on ARM, there's `YIELD`.*

## Only play if you're going to win
The second difference is the load that appeared before the compare-exchange. Or more precisely, it's the fact that we're only attempting the compare-exchange if the lock appears to be free (and so is likely to succeed).

What you may not know about the `CMPXCHG` (compare-exchange) instruction on x86/x64  (at least *I* didn't), is that it always writes to the target memory location, even if the comparison fails (in this case, it just writes back the old value). And it's important, because if the current CPU core writes to a memory location, it means all the other cores will have to invalidate their copy of the cacheline in their cache.

Picture this: two threads/cores are competing to get a lock, but the lock is already taken by a third one.

With the first version of the code, the two spinning cores will keep invalidating each other's copy of the cacheline and have to go through a higher, shared, cache level (or memory) to communicate the updated cacheline. It generates plenty of traffic between caches (and maybe between caches and memory), and all of that for nothing - the cacheline content is identical!

![Useless!](https://media.giphy.com/media/DOnYXfamcw8k8/giphy.gif)

In the second version however, the two spinning cores only read, so the cacheline stays valid in both cores L1 caches. It's also valid in the third core's cache (the one that has the lock) since it was the last one to write. That means no message needs to be exchanged until the lock is actully released, and even releasing it may be faster since the third core doesn't need to fetch the cacheline first. Way better!

*Note: Other CPU architectures often implement compare-exchange with two separate instructions: first a "load-link", and then a "store-conditional" ([LL/SC](https://en.wikipedia.org/wiki/Load-link/store-conditional)). The store-conditional may actually be conditional in this case and this may be a non-problem for these architectures. But even in this case, the additional load we're doing is harmless.*

And that's it for the spin lock tricks!

Finally, if you want to know more about how cache coherency works in a multi-core environment, [Fabian Giesen wrote a pretty comprehensive article about it](https://fgiesen.wordpress.com/2014/07/07/cache-coherency/).



