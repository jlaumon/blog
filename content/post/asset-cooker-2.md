+++
date = "2024-12-14T18:03:00+02:00"
description = "Asset Cooker, a build system for game assets with a UI. Part 2: USN Journals and Fast Startup."
tags = ["Asset Cooker", "C++"]
title = "Asset Cooker -  Part 2: USN Journals and Fast Startup"
draft = false

+++
I said I would write a second article about Asset Cooker, and here it is! Barely six months later! 

Truth is, I couldn’t find a nice way of structuring the article, so I procrastinated a lot. This article doesn't go too much into details because of that, but hopefully it still has the interesting bits. 

And now at least I can blog about something else next!

<!--more-->

## What are USN journals? 

A **USN** is just a number that gets incremented any time a file is modified. The journal stores **entries** saying "at this USN value, this file was modified". The journal keeps 32MB worth of changes, the oldest entries get thrown away to make space for the new ones. It's a relatively simple idea. 

When you want to **keep track of file changes**, it's very convenient: you can essentially ask the journal "give me all the changes that happened between this USN and the current USN”, and then you just have to remember the current USN to ask again later. 

There are two **pitfalls** though:

 - The journal may not have all the info you want. 32MB gets filled fairly quickly, especially on the `C:\` drive where Windows and other programs create temporary files all the time.
 - You're looking at a view of the past. The journal will contain many events for files that **don't exist anymore**, or **got moved/renamed since**. Interpretting that correctly can get tricky. 

OK there are three pitfalls actually. The third one is that it's a **rather obscure API**. It's sometimes a bit weird and often barely documented.

Sometimes you don't know why a function would fail, so it's unclear what to do if that happens. Sometimes it's obvious a function can fail, but you don't know what the error code will be. It's the **Dark Souls** of programming, crash and retry. 

Lucky for you, I already went through most of it with **Asset Cooker**, so check out the code if you want the easy mode. I even wrote comments. 

- `FileDrive::FileDrive` shows [how to open the USN journal](https://github.com/jlaumon/AssetCooker/blob/1de12a4063008ef210574813b1ded5941ec054d9/src/FileSystem.cpp#L486-L496) (without requiring admin rights). 
- `FileDrive::ReadUSNJournal` and `ProcessMonitorDirectory` show [how to read the journal](https://github.com/jlaumon/AssetCooker/blob/1de12a4063008ef210574813b1ded5941ec054d9/src/FileSystem.cpp#L702) and an example of [how to deal with the events](https://github.com/jlaumon/AssetCooker/blob/1de12a4063008ef210574813b1ded5941ec054d9/src/FileSystem.cpp#L772).

## How does Asset Cooker start so fast?

Even with **hundreds of thousands of files**, it usually starts in **under a second**. How is that possible?

**Asset Cooker** needs two things: **the list of all the files** in the directories it watches, and **all their USNs** (they're needed to know if commands need to cook). 

Listing the files **efficiently** is actually fairly simple, **Windows has a function for that** (in addition to many functions that also do that, but inefficiently). It's `GetFileInformationByHandleEx` with the `FileIdExtdDirectoryInfo` parameter. Take a look at [FileRepo::ScanDirectory](https://github.com/jlaumon/AssetCooker/blob/1de12a4063008ef210574813b1ded5941ec054d9/src/FileSystem.cpp#L366) for an example. 

Listing the USNs is a **problem** however, the files need to be **opened** to get it. And with many files, this gets very **slow**.

One trick is to **read the entire USN journal instead**. If the files were modified recently, their **final USN** will be in there. This helps **reduce** how many files need to be opened in the end. It can seem counterintuitive as it means doing a lot of extra work to process USN events we don't care about, but it's actually **massively faster** than **opening many files**. 

A second trick is to use **multiple threads**. Both listing and opening files goes **faster** with multiple threads, but it doesn't scale infinitely. Asset Cooker uses **four threads** for that, YMMV.

Even with all of that, the startup time is still probably somewhere between a few seconds and a minute for 100K files (depending on how many files need to actually be opened). It's not great. 

The last trick is to **not do any of that**, except the first time. **Asset Cooker** writes a **cache file** with the list of all the files and all their USNs on exit. Reading that cached state back takes something like 50 milliseconds, and then **Asset Cooker** just **checks the USN journal** to see if anything changed since. 

Total time it takes **from process start to cooking**: about **250 milliseconds**. 

--

If you have a question, these days I'm on [Bluesky](https://bsky.app/profile/jeremy.laumon.name).
