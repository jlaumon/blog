+++
date = "2017-08-27T11:14:19+02:00"
description = "How Pastagames uses its fiber based job system."
tags = ["Engine"]
title = "Job System"
draft = true
+++


We have a fiber based job system at Pastagames. I started coding it just after seeing this [Naughty Dog GDC Talk](http://www.gdcvault.com/play/1022186/Parallelizing-the-Naughty-Dog-Engine) back in 2015. And so far, we're really happy with it.

In this article, I'll focus on how we use it and not so much on how we implemented it ‒ our implementation is very close to what Christian Gyrling presented in his talk.

If you haven't seen the GDC Talk yet, you should watch it first. It's very interesting and it's probably necessary to follow what I'm talking about.


<!--more-->

# The basic idea

Let's start with the basics.

Launching jobs gives you a "counter", the value of the counter is the number of jobs you launched. When a job finishes, the counter is decremented by one; when all of them are finished, the value is zero.

To know if a job (or a group of jobs) is finished, you can check if the value of the counter is zero, or, you can also call a function that will make you wait until the counter reaches a certain value.

If you're in a job when you wait on a counter, the fiber executing this job is suspended and another one replaces it. The worker thread running the fibers never stops, that's what makes the whole thing very efficient.

If you're not in a job however, the thread itself gets suspended, and that's a lot more expensive. But it can be useful to be able to do that in some cases: most of our code runs in jobs, but we still have a few dedicated threads that sometimes need to wait on a counter (some networking threads, various debug related threads and... the main thread ‒ yeah we still have this one.)

# Generalizing

The counters are what makes the system so flexible, so we decided to use them to represent **all the asynchronous tasks** in our engine.

You want to load a file? The File Manager gives you a counter to wait on while a dedicated I/O thread does the work. Or you can keep the counter around and check its value every once in a while to see if it's finished.

You want to load a material? The Resource Manager is going to launch a job and give you back a counter. This job is going to ask the File Manager for the material file, and then, depending on the content of the file, ask again the Resource Manager to load textures and shaders. This in turn will start new jobs and etc.

You want to load a whole level of your game? That's the same story, just a deeper dependency graph. And inside this hierarchy of loadings, all the code is very simple because it's basically doing **synchronous loadings**: it starts a task and waits immediately on it. As long as the top caller is not waiting on the returned counter and instead checks every frame if the work is done, you get **asynchronous loadings**.

We apply the same idea for every system/manager in the engine. Updating a system is just a matter of launching a job, which in turn may spawn more jobs if its work can be parallelized. Most of the time we avoid updating more than one system at a time to simplify the thread safety, and that just means we just have to wait on the initial counter before moving on to the next system.

# Lifetime of counters

In the Naughty Dog Engine, freeing a counter is explicit, they have the function `WaitForCounterAndFree`. It means that if they don't want to free a counter, they can reuse it. But it also means that it's up to the user to orchestrate the freeing of the counter when more than one job is waiting on it, and that the engine has to detect if a counter is used after being freed.

This seemed too complicated / too error prone for us, so we decided to automatically free a counter when it reaches zero, and instead of giving a pointer to the user, we give them an **opaque handle**.

These handles are just ints. Half the bits represent an index into a big array of counters, and the other half represent a version number. If the version in the handle matches the version of the counter in the array, the handle is considered valid and we can read the counter value or wait on it. Otherwise it means that the counter was freed and its value is implicitely zero. Trying to wait on an invalid counter just returns immediately since the associated work is already finished.

Not having to care about the counter ownership allowed us to simplify a lot of things. For example, if ten jobs try to load the same material, the Resource Manager can give them all the same handle instead of allocating ten different counters. Or if the material is already loaded, it's not even going to allocate a counter and just return an invalid handle directly.


# Conclusion

This job system and its synchronization via counters is way more powerful and simpler to use than the one we had before. Since we added it, we replaced all the non-I/O related threads we had by jobs, and today, we tend to write more parallelized code just because of how simple it's become.

Actually, we use jobs so much now, that understanding what's displayed in our frame profiler can sometimes be a challenge. There are so many jobs being suspended and resumed that it's not always clear what's happening. 

One of the next item in our todo list will be to add a mode to our profiler that shows times per fiber instead of per thread, as well as showing the dependencies between the jobs.

I'll probably write a second article about this job system, just to give a few details about the implementation. Until next time!
