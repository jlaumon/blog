+++
date = "2024-07-22T21:24:00+02:00"
description = "Asset Cooker, a build system for game assets with a UI. Part 1: Memory and Storage."
tags = ["Asset Cooker", "C++"]
title = "Asset Cooker - Part 1: Memory and Storage"
draft = false

+++

A few weeks ago, I released my hobby projet: [Asset Cooker](https://github.com/jlaumon/AssetCooker). I even made a [short release trailer](https://www.youtube.com/watch?v=hvbVC4m6BOo) for it.

![Asset Cooker icon](images/chef-hat-heart.png)

So, what is **Asset Cooker**? 

It's a **build system**. Put very briefly, it has **commands** that have **inputs** and **outputs** (which are files). If the outputs don't exist, or if the inputs are modified, it execute the command to (re)generate the outputs.

I don't plan on describing everything in articles, because that would be too much (and not all of it interesting), but I'll try to do a few (short?) articles about single topics that I find interesting. 

In this first article, I'm going to talk about **memory and storage**. Asset Cooker has to deal with **a lot of items**. Hundreds of thousands of files, of commands, and of strings. Managing that carefully is very important.

<!--more-->

--

Asset Cooker stores one [FileInfo](https://github.com/jlaumon/AssetCooker/blob/e26bb3c52a69eb90d889194a878c83492edf883e/src/FileSystem.h#L154-L183) per file. FileInfos are **small structs** that contain basic informations about a file, like its path or the **USN** representing the last time it was modified (it's just a 64bit number).

The interesting **design decision** here is that FileInfos are **never destroyed**. If a file is deleted, that information is stored in the FileInfo, but the FileInfo stays alive. 

If the file is created again later, the **same** FileInfo is updated again. This means all the code can reference FileInfos without worrying about their lifetimes, and that simplifies **a lot of things**.

To support this **efficiently**, all FileInfos are stored in a **custom vector** ([VMemArray](https://github.com/jlaumon/AssetCooker/blob/main/src/VMemArray.h)) that uses **virtual memory** to grow while keeping the data address **stable** (unlike eg. `std::vector`). Essentially, it reserves a few GiBs from the start but only commits pages as needed. 

The **file paths** are also stored in a specific VMemArray ([StringPool](https://github.com/jlaumon/AssetCooker/blob/main/src/StringPool.h)) so the FileInfo can just keep a pointer to it without caring about lifetime/ownership.

Since everything is stored in these **large arrays**, using **indices** instead of pointers is trivial, and contributes to saving memory. [FileID](https://github.com/jlaumon/AssetCooker/blob/e26bb3c52a69eb90d889194a878c83492edf883e/src/FileSystem.h#L122-L141) is such an example of FileInfo **4-byte index**, wrapped in a struct to make it **type safe**. In practice, it's a tiny bit more complicated since each root folder (FileRepo) has its own array of FileInfos, but that just means a few bits of the FileID are used as a FileRepo index. 

Another cool trick permitted by this design is that **multiple threads** can read the VMemArray containing FileInfos **without any synchronization**. Since FileInfos are never destroyed, they are only added **at the end** of the array. Threads adding FileInfos still need synchronization, but as long as they update the array size only when they're **done writing**, there can be readers iterating the array **at the same time** without issue.

**Commands** follow exactly the **same patterns**: stored in a VMemArray, never destroyed, referenced with type safe indices. 

And to finish, a few words about about **strings**. There are only two types of strings: **persistent** strings allocated in a **StringPool**, or **temporary** strings stored in **fixed size buffers** ([TempString](https://github.com/jlaumon/AssetCooker/blob/e26bb3c52a69eb90d889194a878c83492edf883e/src/Strings.h#L90-L131)) on the stack. The performance cost of many small allocations is never an issue here!

--

Next time we'll take a look at the **USN journals** and the **incredible startup times** of Asset Cooker. 

Shout at me on [twitter](https://twitter.com/_plop_/status/1815471030904734199) or [mastodon](https://mastodon.gamedev.place/@jerem/112831813733353420).
