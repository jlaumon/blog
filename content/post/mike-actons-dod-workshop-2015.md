+++
date = "2016-01-10T15:54:48+01:00"
description = ""
tags = ["Data-Oriented Design"]
title = "Mike Acton's Data-Oriented Design Workshop (2015)"
draft = true

+++

I attended Mike Acton's master class during last year's [Game Connection](http://www.game-connection.com/master-classes-0) in Paris. Unsurprisingly it was about data-oriented design, 
but it was a workshop, a practical excercise, and it showed us (or at least me) a pretty different facet of the concept, as well as a few interesting techniques.

<!--more-->

First, if you're new to the concept of data-oriented design, you should [read an introduction](http://gamesfromwithin.com/data-oriented-design).

*Know your data*, that's what Mike Acton keeps saying. /* change this sentence or remove the praragraph */I thought it only meant you should know what your inputs and outputs are, because that's 
the only sensible way of designing your data structures. But it gained a lot more meaning that day.

## The exercice

The excercise was to try to make [tinyobjloader](https://github.com/syoyo/tinyobjloader) faster. It's a small opensource library that
reads OBJ files, and OBJ is a simple text file format to store meshes. 

Mike had the only computer and was de facto doing everything.
He wasn't directly doing the exercice however, he just kept asking us what he should do and sometimes hinted us by asking questions. That can sound
like a weird setup for a master class but ended up working perfectly. It was very interactive and we all left convinced we could do something similar again
on our own.

## The usual profiling

After a quick look at the code to understand what it does (Mike didn't read it beforehand either, that's how confident he is), 
we made a small test app and ran it on a few OBJ files that Mike had brought (he didn't read the code, but he wasn't unprepared).

The sizes of the files we tested ranged from a few MB to about 800MB. The big ones were so slow we didn't wait until they finished,
we waited several minutes then killed the app. 

Next step, we fired up [Very Sleepy](http://www.codersnotes.com/sleepy/) to check where the time was spent.
I'm not going to explain the working details of *tinyobjloader* because that's beside the point, what you need to know is that it does two conceptually separate
things: it parses the OBJ file and then converts the parsed data into a slighlty different format.

The conversion part involves storing all the vertices into an std::map to 
deduplicate them, and that's very slow, especially when the mesh is big. Also note that the duplication happens because of this conversion, the initial data
doesn't contain duplicates.

This deduplication is what took the biggest part of the time, and seemed to be a good candidate for optimization. We decided to focus on that.

## So, what should we do?

First general reaction on our part: let's replace that std::map with a hash map! 

Tut tut, that's a pretty bad decision. Mike redirected the group with a question:

> Do we need that conversion in the first place?

Turns out, no, not necessarily. Again, I'm not going into too much detail here, but just know that since DirectX 10 / OpenGL 3, the graphics APIs are a lot
more flexible and the GPU could handle the first format directly. The cost would be one more indirection in the vertex shader, but that's completely negligible.

Here I could recognize data-oriented thinking. What is it we're actually trying to do? What's the transformation we want to apply? What's the input, 
what's the ouput? By analysing the flow of data at a more global level, from the OBJ reading to the output of the vertex shader, 
we found out we were doing more than required.

The solution was just not to do the conversion, and change the way our vertex shaders gets their inputs. 

However that's no fun. For the sake of the exercise, we decided to pretend we absolutely needed this transformation. 
And deduplicating vertices with an std::map was still too slow.

## So, what should we do? #2

> Do we need to deduplicate the vertices?

I guess you saw that one coming. Would it work without deduplicating the vertices? Yes. But since there would be more vertices, 
it would take more memory and the GPU would have more work to do.

> How much memory? How much work?

This is were the fun starts, and where I started to understand the other meaning of *Know your data*. How many vertices ended up duplicated
by the conversion of those OBJ files?

Let's find out! Mike hacked into the source code to add a few calls to `printf`. `printf("a\n")` whenever a duplicated vertex was encountered, `printf("b\n")` otherwise.

He then ran the app on a few OBJ files and captured the output into a file:

    app.exe thingOBJ > 1.txt

How many vertices in total? If you're a linux-style command line person, like Mike, you can do:

    wc -l 1.txt
	
Which counts the number of lines in the file. If you're not that kind of person, getting the number of lines is pretty easy with a decent text editor, like
[notepad++](https://notepad-plus-plus.org/).

How many duplicated vertices?

    grep a 1.txt | wc -l
	
`grep` prints all the lines containing 'a' and `wc` counts them. In notepad++, you can do a 'Find' (ctrl+f) 'a' and click on the 'Count' button to get the same
result.

The result varied from file to file but in the end the number of duplicated vertices wasn't very high. Something around 10-20% most of the time,
if I remember correctly.

We calculated how much memory it represented in term of vertex buffer and index buffer and concluded that it wasn't much either. In a game, the majority of
the VRAM is used to store textures, so incrementing the space taken by meshes, even by 25%, is not a big deal. And it's a small price to pay to
save minutes or hours spent building data.

What about how much work it represents? Again, in a game, the GPU usually spends a pretty small part of the frame running vertex shaders, so a small increase
there is probably affordable. 

In a real case, we probably ought to validate those assumptions more thoroughly. How much time is actually spent in the vertex shaders, how much memory 
is spent on meshes. We can also make a script that runs the app above on all the meshes of the game and gather the results in a CSV. 

Here we were again, deciding not to do something in order to save time. We kept the conversion, but avoided doing the deduplication of the vertices.
This time however, it was a trade: we traded time during the building of the data, for time and memory at runtime. But our knowledge of the data told us the
trade was worth it.

At this point, the afternoon was well underway but we still had time to try something else. So we decided to try to keep the deduplication 
and see what we could do to improve it.

## So, what do we do? #3

Make

Here, we traded time . But more importantly, learned enough aboutnow know enough about our data to know that thisWe kept the conversion, but avoided doing the deduplication of the vertices. At this point,
we were in the middle of the afternoon and we had enough time to try something else: 



If you want to try the command line experience on Windows, check [cmder](http://cmder.net/) or [cygwin](https://www.cygwin.com/)
(there are probably other alternatives, but that's the two I know.)
