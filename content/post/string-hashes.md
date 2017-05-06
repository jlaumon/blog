+++
date = "2017-05-06T12:03:27+02:00"
description = ""
tags = ["C++", "Engine"]
title = "String Hashes"

+++

Strings are often used as **identifiers** in games: object names, sound effect names, particle type names, etc. They're a bit like enums with the advantage of allowing your game to be data-driven: you don't necessarily need to recompile your program to accept new values.

But strings are no fun: storing them efficiently is a headache, they're bigger and they're slower than enums.

Fortunately there's an alternative: **string hashes**. We like them a lot at [Pastagames](http://www.pastagames.com/), and here are our humble solutions to the practical problems that come with them.

<!--more-->

*This article was also posted on [Pastagames' blog](http://www.pastagames.com/string-hashes/).*

## Hash Function

There are tons of hash functions out there, so it's sometimes a little bit hard to choose. Fortunately there are [great summaries](http://aras-p.info/blog/2016/08/09/More-Hash-Function-Tests/) on the Internet.

We definitely want to hash mostly short strings, and in this case simpler functions are better. In the article linked above, Aras recommends **FNV-1a**. If you don't care about javascript as a platform, **Murmur2A** and **Murmur3** may be slightly more efficient. 

At Pastagames, we chose **djb2** some years ago. All in all, it makes very little difference because we don't hash strings that often anyway. The goal is to use the hash everywhere instead of the string, so we basically calculate the hash once and then we're done.

For this usage, **32 bits** hashes are often enough. The chances of having a collision are higher than with 64 bits hashes but still very, very low. In our biggest project, we have around 30K unique strings and we haven't got a single collision. And if we ever have one, well, we can just change one of the strings.

## Collision Detection

The chances of having collisions may be low, but detecting them during development is still critical, otherwise you will get really weird bugs.

The basic idea is simple: every time we hash a string, we access a global map (a hash map actually) to check if the hash was already associated with a different string.

In our implementation, this global hash map is mutexed, but to limit the contention when accessing it from multiple threads, we added two layers of **thread local caches**. 

The first layer keeps the 16 most recent hashes and the second layer, the 128 most recent. Of course, those sizes are very dependent on how we use the string hashes and may not help in your case (remember, [know your data](post/mike-actons-dod-workshop-2015/)). In our case, it also helped with the performance in debug builds (where the hash map is a lot slower because inlining is disabled), but not so much in optimized builds (to be fair, our cache implementation is pretty naive and we really stopped at "good enough").

An alternative to the caches would be to replace the mutex by a [readers-writer lock](https://en.wikipedia.org/wiki/Readers%E2%80%93writer_lock), or even use a [lock free hash map](https://github.com/preshing/junction) (although we do want to keep the hash map implementation simple, for reasons detailed below).

Last thing to note about our implementation: we store the strings in 64KB buffers to reduce the number of memory allocations. Each buffer acts as a linear allocator, and when it's full we just allocate a new one. We never free the strings so we don't even need to keep track of these buffers. YOLO.

## Debugging

The first thing we did is add a `const char* getString()` function to our StringHash class. That's really easy to implement since we just need to access to the global hash map mentioned above. Since the strings are never freed, the pointer returned by the function will always be valid. 

With this `getString()`, we can use strings instead of hashes in the **logs**, the **debug UIs**, the **editors** and even when **serializing** to textual data formats. The only limitation is that we can only use it in **development builds** because the collision detection (and the hash map) are disabled the final build. But that's usually not a problem. To simplify things the `getString()` function stays defined in the final build, but always returns an empty string.

So far so good, but still, it's hard to tell that 4086421542 is "banana" when you look at a StringHash variable in the debugger. So the second thing we did is **store the pointer** returned by `getString()` along with the hash inside the StringHash class. It makes the string visible in the debugger but it also makes the class bigger, which is not great. Fortunately there's another option: the **Visual Studio Debug Visualizers** (aka. the [Natvis files](https://msdn.microsoft.com/en-us/library/jj620914.aspx)) and that's what we used in the end (at least on the platforms that support it).

Natvis are basically XML "scripts" that tell the debugger how to display a class. In this particular case, we need to use the [CustomListItems](https://msdn.microsoft.com/en-us/library/jj620914.aspx#CustomListItems-expansion) tag to do a lookup inside the global hash map and find the string. That's where having a **simple hash map implementation** becomes important, scripting in XML is *painful*.

First thing to note, since the key of the map is **already a hash**, we don't need a function to rehash it. If you're using an std::unordered_map, the 3rd template parameter should be a funtion that does nothing.

Next, a hash map that uses [linear probing](https://en.wikipedia.org/wiki/Linear_probing) makes everything a lot easier: we can just jump at the right bucket index and do a linear search from there (note that std::unordered_map does **not** use linear probing, you need a custom hash map [like this one](https://github.com/rigtorp/HashMap)). 

Here is what the natvis look like (based on the hash map implementation linked above):

```xml
<?xml version="1.0" encoding="utf-8"?>

<AutoVisualizer xmlns="http://schemas.microsoft.com/vstudio/debugger/natvis/2010">

<Type Name="Pasta::StringHash">
    <Expand>
	    <CustomListItems>
        <Variable Name="buckets" InitialValue="s_GlobalStringMap->buckets_.mpBegin" />
        <Variable Name="num_buckets" InitialValue="s_GlobalStringMap->buckets_.mpEnd - s_GlobalStringMap->m_map.buckets_.mpBegin" />
        <Variable Name="start_bucket" InitialValue="m_hash % num_buckets" />
        <Variable Name="i" InitialValue="start_bucket" />
        <Loop>
          <If Condition="buckets[i].first == m_hash">
            <Item Name="string">buckets[i].second, na</Item>
            <Break />
          </If>
          <Exec>i = (i + 1) % num_buckets</Exec>
        </Loop>
      </CustomListItems>
      <Item Name="hash">m_hash</Item>
    </Expand>
</Type>

</AutoVisualizer>
```

Very verbose, but not so complicated. We start looking at `m_hash % num_buckets` and check out every bucket until we find our hash or get back where we started.

It's also possible to follow the chaining used by std::unordered_map (although more complicated), but another reason to use to linear probing is that some consoles only partially support the natvis file syntax and have a simpler "linear search" tag instead of the very complex CustomListItems tag. But that's another story.

Here is what it looks like in the debugger:

![StringHash natvis](images/stringhash_debugger.png)

Exactly like when we store the string inside the class.

One last thing worth mentioning: global StringHash variables are going to access the global hash map in their constructor so we need to make sure that the map is initialized *before* any StringHash. A typical solution for that (since in C++, global variable initialization order is not defined) is to make the hash map **static inside a function**. However, we *also* need to declare a global pointer to the hash map, otherwise we can't access it from the natvis file.


```c++

// --- StringHash.h ---
struct StringHash
{
  ...
  // Declaring the map inside the StringHash class will help the debugger find it
  // (in case another global variable with the same name exist) and will prevent
  // the variable from being optimized away (which can happen since it's never 
  // referenced in the code.)
  static StringMap* s_GlobalStringMap;
}

// --- StringHash.cpp ---
static StringMap* GetGlobalStringMap()
{
  static StringHash::StringMap s_StringMap;
  return &s_StringMap;
}

StringMap* StringHash::s_GlobalStringMap = GetGlobalStringMap();
```

## Compile Time Hashes

Another advantage of using a simple hash function is that it's easy to make a **constexpr** version of it (even with the restrictions of c++11).

For example, djb2:

```c++
uint32_t HashStr(const char* _str)
{
  if (*src == 0)
      return 0;

  uint32_t hash = 5381;
  
  char c;
  while ((c = *_str++) != 0)
    hash = ((hash << 5) + hash) + c;

  return hash;
}

```

Becomes:

```c++
constexpr uint32_t HashStrRecur(uint32_t _hash, const char* _str)
{
  return (*_str == 0) ? _hash : HashStrRecur(((_hash << 5) + _hash) + *_str, _str + 1);
}

constexpr uint32_t HashStr(const char* _str)
{
  return (*_str == 0) ? 0 : HashStrRecur(5381, _str);
}
```

If you also declare the StringHash constructors constexpr, all the hashes of string literals will be calculated at **compile time**. Yay!

Of course this is incompatible with the collision detection / debugging part, but with a few macros and #ifdefs, it's pretty easy to have the debug features in development builds and the constexpr for release builds. 

## That's all folks!

Phew, that was a little longer than expected.

Next up, the fiber based job system. Completely inspired by the Naughty Dog GDC presentation, but with a few small differences and a few more implementation details.
