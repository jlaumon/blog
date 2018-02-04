+++
date = "2018-01-21T10:33:38+01:00"
description = ""
tags = []
title = ""
draft = true

+++

1- meltdown 

read kernel address from user space, use result to compute a user address and read it; it generates a page fault but you know if value was 1 or 0 depending on whether the user address is in the cache

can avoid page fault by putting the code inside an if that will not be taken

2- spectre 1

same thing but from kernel space (no page fault in this case, the if is required)
hard to find code in the kernel that can do that, but hard to patch them all
interpreter / JIT can be used to generate this kind of code pattern
could be web browser instead of kernel, javascript instead of user space program

3- spectre 2

same thing except instead of having the leaking code inside an if, you jump to it with an indirect branch
big improvement: the leaking code can be anywhere in the kernel/target code (and there is plenty of code using this pattern)
but also very hard to train the branch predictor to make it jump to this address