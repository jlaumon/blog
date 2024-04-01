+++
date = "2024-04-01T17:02:00+02:00"
description = "A story about Copy Queues and waiting."
tags = ["GPU"]
title = "Copy Queue woes."
draft = false

+++

Consider this case: you're launching several **Async Compute** jobs. They need some input buffers to be uploaded, and some output buffers to be read back.

![Base scenario](images/CopyQueues_base.svg)

How do you minimize the time it takes to get all the outputs back to the CPU? I'm focusing on D3D12 and Windows for this article.

<!--more-->

--


One obvious thing to add here is a **Copy Queue**. The uploads/readbacks might be a bit faster (because **Copy Queues** are good at saturating the PCIe bus) and it should free some time on the **Compute Queue** itself, right? 

However this is what happens:

![Naive **Copy Queue**](images/CopyQueues_naive.svg)

That's because the obvious way of implementing this is to make the **Compute Queue** wait for the **Copy Queue** (until "Upload 1" is finished) and then make the **Copy Queue** wait for the **Compute Queue** (until "Dispatch 1" is finished). 

So when the "CPU 2" thread submits its work, both queues are already "busy" waiting, and the entire thing is delayed.

What can be done? 

One option would be to have two **Compute  Queues** and two **Copy Queues**. That's maybe fine with two, but it might become complicated with more jobs. Having N queues (eg. one per thread) would work (there are no hard limits on the number of queues) but then synchronizing all of it with the **Direct Queue**, and keeping track of how resources get uploaded, sounds annoyingly complicated.

One other option would be to have a **Copy Queue** for uploads, and one for readbacks. The complexity is already much more manageable, but it opens up this case:

![Naive **Copy Queue**](images/CopyQueues_up_rb_queues.svg)

Here, "Readback 2" gets submitted first, because submitting anything is a race between "CPU 1" and "CPU 2", and "Readback 1" has to wait a very long time.

You could fix that by mutexing the whole process, but `ExecuteCommandLists` is an expensive call, so making it even more serial isn't ideal.

Yet another option (my favorite) is to not make the queues wait at all! Instead, have a thread wait on the queue, and submit the work when it's the right time.

![Thread Wait](images/CopyQueues_thread.svg)

Here the "Upload 1" and "Upload 2" are submitted immediately, but "Dispatch 1" and "Dispatch 2" are queued on the CPU side and submitted by that waiting thread once the corresponding upload is finished. Same thing with "Readback 1" and "Readback 2".

So what do you need to set that up exactly?

 - A **Fence** per queue (you should already have that)
 - An extra thread
 - For each queue, an array of waiting Command Lists (sorted based on the **Fence** value they need to wait)
 - An extra Win32 Event to wake up the thread when a new **Command List** is added to the array

The trick is to use `WaitForMultipleObjects` to make the thread wait until either: one of the Fences reach a value a **Command List** wants in OR a new **Command List** is added to the front of the list.

It adds a little bit of delay because now the `ExecuteCommandLists` will only start when the GPU is already done with the dependent work (and that function is quite slow), but it's relatively simple and removes the worst cases very nicely.

This is what it looks like with all the details:

![Thread Wait](images/CopyQueues_details.svg)

**Note:** If one thread is not enough to submit all the Command Lists without causing extra delays, you can very easily change that to one thread per queue.

--

**Bonus:** if there are background loadings at the same time, this might also happen:

![Background Loadings](images/CopyQueues_bg_loadings.svg)

Here again you might think that adding a second **Copy Queue** would solve it. But dependeing on how the hardware queues are assigned, it might look like this:

![Background Loadings with second **Copy Queue**](images/CopyQueues_bg_loadings_2nd_queue.svg)

However, there is a simple solution! Command queues accept a priority value on creation, set it to `D3D12_COMMAND_QUEUE_PRIORITY_HIGH` and enjoy the copies nicely overlapping.

![Background Loadings with second **Copy Queue** but high priority](images/CopyQueues_bg_loadings_hi_prio.svg)

And that's it!

Thanks to Jesse Natalie and Matthäus Chajdas who answered my questions when I started looking into this.

