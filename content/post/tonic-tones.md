+++
date = "2016-10-08T13:14:19+02:00"
description = ""
tags = []
title = "tonic tones"
draft = true

+++

Back in 2010, when I was still a student, one of the assignments we had was to implement [Erik Reinhard's tone mapping operators](https://www.cs.utah.edu/~reinhard/cdrom/tonemap.pdf).
At the time, the teacher taunted us by saying that if we coded properly, updating the image should be "real time".
In my case, it wasn't.

Was my code that bad? Was the teacher a troll? In this article series, we'll try to find out. No GPU will be involved, all of this is just an excuse to look at
some disassembly and do some micro optimizations.

<!--more-->

## Tone Mapping

A little bit of background first. What is tone mapping? Very briefly: for low dynamic range (LDR) images, the max value of the red, green and blue channel is 1.0; 
for high dynamic range (HDR) images, there's no limit. HDR images are really cool because they give a better idea of the luminosity. There's not just one value for "white",
a picture of a light source (like the sun) could have pixels with an RGB value of tens of thousands. And having a lot more space for very bright colors also means you
can have a lot more precision for very dark colors.

There's one problem with HDR images though: your monitor is probably an LDR display and it can't display them (HDR displays do exist, but they're not common yet). 
So to visualize an HDR image, you first need to bring it into the [0,1] LDR range and that's what tone mapping is all about: 
algorithms to turn HDR images into LDR images without them ending up all black or all white.

## Tonic Tones

That's the name of [the program](https://github.com/jlaumon/TonicTones) I wrote back in 2010, and like most student projects, it's incredibly over-engineered.
It uses Qt for the UI and plugins to load images and to perform the tone mapping. 

I guess it was interesting to code at the time, but with all the dependencies it's a pain to compile, especially six years later. I actually tried to write this article twice over the last 5 years. 
Both times it took me so long to just make it work that I dropped the idea. Everytime I had to start over because a new version of Visual Studio
was out and I had to recompile some old image library and configure Qt all over again.

This time, no more bullshit, I recoded it from scratch using [dear imgui](https://github.com/ocornut/imgui) and [stb_image](https://github.com/nothings/stb)
and it probably took me half the time. Tonic Tones 2 is a lot simpler, and already a lot faster






ToneMap 11.41 ms
Yxy -> RGB 18.75 ms
displayImage 16.35 ms