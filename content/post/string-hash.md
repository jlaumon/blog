+++
date = "2017-01-28T13:44:19+02:00"
description = ""
tags = []
title = "String Hashes"
draft = true

+++

Strings are often used as identifiers in games: object names, sound effect names, particle type names, etc. They're a bit like enums with the advantage of allowing your game to be data-driven, you don't necessarily need to recompile your program to accept new values.

But strings are no fun: they're not all the same size so storing them efficiently is a headache, they're kind of big, and they're overall pretty slow compared to enums.

Fortunately there's an alternative: **string hashes**. We like them a lot at Pastagames, and here are our humble solutions to the practical problems that come with them.

<!--more-->


## Hash Function

There are tons of hash functions out there, so it's sometimes a little bit hard to choose. Fortunately there are [great summaries](http://aras-p.info/blog/2016/08/09/More-Hash-Function-Tests/) on the Internet.

We definitely want to hash mostly short strings, and in this case simpler functions are better. In the article linked above, Aras recommends **FNV-1a**. If you don't care about javascript as a platform, **Murmur2A** and **Murmur3** may be slightly more efficient. 

At Pastagames, we chose **djb2** some years ago. All in all, it makes very little difference because we don't hash strings that often anyway. The goal is to use the hash everywhere instead of the string, so we basically calculate the hash once and then we're done.

For this usage, **32 bits** hashes are probably enough. The chances of having a collision are higher than with 64 bits hashes but still very, very low. In our biggest project, we have around 30K unique strings and we haven't got a single collision. And if we ever have one, well, we can just change one of the strings.

## Collision Detection

The chances of having collision may be low, but detecting them during development is still critical, because they can lead to really weird, hard-to-find, bugs. The basic idea is simple: every time we hash a string, we access a global map (a hash map actually) to check if this hash was already associated with a string. If there is a string and it's different, there's a collision.

In our implementation, this global hash map is mutexed to allow multi-threaded accesses. A [lock free hash maps exist](https://github.com/preshing/junction) or a [readers-writer lock](https://en.wikipedia.org/wiki/Readers%E2%80%93writer_lock) may be more appropriate depending on your usage, but we wanted to keep things simple for other reasons, more info in the [Debugging] section.

To limit the contention on the map, we added two layers of **thread local caches**. The first layer keeps the 16 most recent hashes and the second layer the 128 most recent. Of course those numbers completely depend on the use case ([know your data](post/mike-actons-dod-workshop-2015/)). It also helped with the performance in debug builds (where the hash map is a lot slower because inlining is disabled), but not so much in release (to be fair, our cache implementation is pretty naive and we stopped at "good enough").

Last thing to note, to reduce the number of memory allocations in the map, we store the strings in 64KB buffers. Each buffer act like a linear allocator, and when it's full we just allocate a new one. We never free the strings so we don't even need to keep track of the buffers. YOLO.

## Debugging

So, string hashes are cool, but still, it's hard to tell that 4086421542 means "banana". So the first thing we did is add an option to store both the hash and a pointer to the string inside our StringHash class (enabled with a #define). That's pretty easy thanks to the global hash map mentioned above, even if we construct the StringHash from an int, we can usually find back the string and get a pointer to it without worrying about its life time.

Having the string pointer in the class makes it easy to see the string in the debugger but it makes the class bigger, which is not great. Fortunately there's another solution with Visual Studio: the Debug Visualizers (aka. the [Natvis files](https://msdn.microsoft.com/en-us/library/jj620914.aspx)).

It's basically an XML "script" that tells the debugger how to display the class. In our case, we need to use the [CustomListItems](https://msdn.microsoft.com/en-us/library/jj620914.aspx#CustomListItems-expansion) tag to do a lookup inside the global hash map and find the string. That's where having a simple hash map implementation becomes important, scripting in XML is *painful*.

First, since the key of the map is already a hash, we don't need a function to rehash it (ie. the 3rd template parameter in std::unordered_map), a function that does nothing is perfect in our case.

Then, a hash map that uses [linear probing](https://en.wikipedia.org/wiki/Linear_probing) makes everything a lot easier (note that this is not what std::unordered_map does, you need a custom hash map [like this one for example](https://github.com/rigtorp/HashMap)). 

Linear probing means we can just jump at the right bucket index and do a linear search from there. It's also possible to follow the chaining that std::unordered_map uses (although more complicated), but the main reason we switched is because there are some consoles that don't support the full CustomListItems tag and just have a "linear search" tag instead.

Here is what the natvis file look like (using the hash map implementation linked above):

```xml
<?xml version="1.0" encoding="utf-8"?>

<AutoVisualizer xmlns="http://schemas.microsoft.com/vstudio/debugger/natvis/2010">

<Type Name="Pasta::StringHash">
    <Expand>
	    <CustomListItems>
        <Variable Name="buckets" InitialValue="s_GlobalStringMap->m_map.buckets_.mpBegin" />
        <Variable Name="num_buckets" InitialValue="s_GlobalStringMap->m_map.buckets_.mpEnd - s_GlobalStringMap->m_map.buckets_.mpBegin" />
        <Variable Name="i" InitialValue="m_hash % num_buckets" />
        <Loop>
          <Break Condition="i == num_buckets" />
          <If Condition="buckets[i].first == m_hash">
            <Item Name="string">buckets[i].second, na</Item>
            <Break />
          </If>
          <Exec>i++</Exec>
        </Loop>
      </CustomListItems>
      <Item Name="hash">m_hash</Item>
    </Expand>
</Type>

</AutoVisualizer>
```

And here is what it looks like in the debugger:

![StringHash natvis](images/stringhash_debugger.png)


## Compile Time Hashes

Another advantage of using a simple hash function is that it's easy to make a constexpr version of it (even with the restrictions of c++11).

For example, djb2:

code

Becomes:

```c++

```


