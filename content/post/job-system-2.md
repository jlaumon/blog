+++
date = "2018-10-20T11:10:00+02:00"
description = "Fiber based job system implementation details."
tags = ["Engine"]
title = "Job System #2"
draft = false

+++

Oops! I actually wrote this article one year ago but never finished it. Let's say it's finished, and boom! released.

This is a follow up on the previous article about [our fiber-based job system](post/job-system/). It contains a few details about our implementation, what we found to be important or not.

<!--more-->



### Stack sizes

We have two sizes of stacks. Initially we had just one but jobs calling middlewares needed really big stacks. Having two sizes really helps keeping the memory usage low. Small stacks are 20KB, large ones are 128KB.

### Jobs priority

We have three priorities :

 - high for jobs that need to finish this frame
 - medium for jobs that will need to finish next frame (eg. rendering jobs)
 - low for fully asynchronous jobs (.eg loadings)

The scheduling strategy is very simple: higher priority jobs always run before lower priority ones (same as Naughty Dog's engine.)

### Yield

We added a yield function to split long jobs and allow higher priority jobs to run. The function actually only yields if the job has been running for long enough, this way you can call it without fearing you're calling it too often.

### Lock-free queue

One of the most important part of a job system is the job queue.

We've been using [moodycamel's concurrent queue](https://github.com/cameron314/concurrentqueue/) since the beginning and it does the job pretty well. The sub-queues system it uses basically gives us work stealing without having to do anything.

[Molecular Musings' blog](https://blog.molecular-matters.com/2015/09/25/job-system-2-0-lock-free-work-stealing-part-3-going-lock-free/) describes an alternative that could be interesting if you want to roll your own lock free queue.

### Only wait for zero

Waiting on counter values other than zero is possible but was not really useful to us. It can be used for chaining jobs with just one counter: if job C waits for job B that in turn waits for job A, A can wait for value 2, B for value 1 and C for value 0. 

But it's simpler to just use three counters, and that's what we usually do. Removing the possibility of waiting on values other than zero would make the implementation somewhat simpler.

### Number of fibers

The number of fibers needed for loadings can sometimes be a problem. Loading an entity starts X jobs for loading materials, which in turn start Y jobs for loading textures, etc.

To avoid using too many fibers, we had to make sure there's a limit on how many simultaneous loadings can be launched for the highest level object (in this example, the entities).

For example, if we have 2000 entities to load in a level, we make a queue and only allow loading 20 of them at a time.

