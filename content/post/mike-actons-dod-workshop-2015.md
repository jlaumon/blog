+++
date = "2016-03-19T12:04:48+01:00"
description = "The tale of one of Mike Acton's master class. Know your data!"
tags = ["Data-Oriented Design"]
title = "Mike Acton's Data-Oriented Design Workshop (2015)"
draft = false

+++

I attended Mike Acton's master class during last year's [Game Connection](http://www.game-connection.com/master-classes-0) in Paris. 
Unsurprisingly it was about data-oriented design, but it was a workshop, a practical exercise, and it showed us (or at least me) 
a new facet of the concept, as well as a few interesting techniques.

<!--more-->

If you're new to the concept of data-oriented design, you should first [read an introduction](http://gamesfromwithin.com/data-oriented-design).

*Know your data*, that's what Mike Acton keeps saying. I'd heard it before the master class but never really had thought about
what it implied. In this article ‒ which is pretty much just the tale of this master class ‒ I'll try to explain what it means,
and why it's so important.

## The exercise

The exercise was to try to make [tinyobjloader](https://github.com/syoyo/tinyobjloader) faster. It's a small open-source library that
parses OBJ files, simple text files used to store 3D geometry (meshes).

Mike had the only computer and was de facto doing everything.
He wasn't directly doing the exercise however, he just kept asking us what he should do and sometimes hinted us with questions. 

That can sound like a weird setup for a master class but ended up working perfectly. It was very interactive and we all left 
convinced we could do something similar on our own.

## The usual profiling

After a quick look at the code to understand what it did (Mike hadn't read it beforehand either, that's how confident he is), 
we made a small test app and ran it on a few OBJ files that Mike had brought (he hadn't read the code, but he wasn't unprepared).

The sizes of the files we tested ranged from a few MB to about 800MB. The big ones were so slow we didn't wait until they finished,
we waited several minutes then killed the app. 

Next, we fired up [Very Sleepy](http://www.codersnotes.com/sleepy/) (a profiler) to check where the time was spent. I'll skip over the details here, 
what you need to know is that *tinyobjloader* actually does two conceptually separate things: it parses the OBJ file and then converts the parsed 
data into a slightly different format.

The conversion part involves storing all the vertices into an std::map to deduplicate them, and that's very slow, 
especially when the mesh is big. This deduplication took the biggest part of the time, and seemed to be a good candidate 
for optimization. We decided to focus on that.

## So, what should we do?

First general reaction on our part: let's replace that std::map with a hash map! 

Tut tut, that's a pretty impulsive decision. Mike redirected the group with a question:

> Do we need that conversion in the first place?

After a few minutes of discussion, it turned out, no, not necessarily.

I'm not going too much into details here because it's a little bit long to explain
(I made an [appendix]({{< relref "#appendix" >}}) for that!), just know that since DirectX 10 / OpenGL 3, the graphics APIs are flexible enough
to handle the first format directly. 

And more importantly, not doing this conversion pretty much avoids the duplication.

Here I could recognize data-oriented thinking. What is it we're actually trying to do? By considering the flow of data 
at a more global level, from the OBJ reading to the vertex shader, we found out we were doing more than required.

OK, problem solved. We could just not do this conversion and it would certainly be a lot faster.

However that's no fun. For the sake of the exercise, we decided to pretend we absolutely needed this conversion. 
And deduplicating vertices with an std::map was still too slow.


## So, what should we do? #2

> Do we need to deduplicate the vertices?

Maybe you saw this one coming. Would it work without deduplicating the vertices? Yes. But since there would be more vertices, 
it would take more memory and the GPU would have more work to do.

> How much memory? How much work?

This is where the fun starts, and where I started to understand the meaning of *Know your data*. How many vertices ended up duplicated
by the conversion of those OBJ files?

Let's find out! Mike hacked into the source code to add a few calls to `printf`. `printf("a\n")` whenever a duplicated vertex was encountered, `printf("b\n")` otherwise.

He then ran the app on a few OBJ files and captured the output into a file:

    app.exe thing.OBJ > 1.txt

How many vertices in total? If you're a linux-style command line person, like Mike, you can do:

    wc -l 1.txt
	
Which counts the number of lines in the file (Windows users, check out [cmder](http://cmder.net/)). And if you're not that kind of person, 
getting the number of lines is still pretty easy with a decent text editor, like
[notepad++](https://notepad-plus-plus.org/).

How many duplicated vertices?

    grep a 1.txt | wc -l
	
`grep` prints all the lines containing 'a' and `wc` counts them. In notepad++, you can do a 'Find' (ctrl+f) 'a' and click on the 'Count' button to get the same
result.

The result varied from file to file but in the end the number of duplicated vertices wasn't very high. Something around 10-30%,
if I recall correctly.

We calculated how much memory it represented in term of vertex buffer and index buffer and concluded that it wasn't much either. In a game, usually, the majority of
the VRAM is used to store textures, so incrementing the space taken by meshes, even by 25%, is not a big deal. And it's a small price to pay to
save minutes or hours every time you build the data.

What about how much more work it represents? Again, in a game, the GPU usually spends a pretty small part of the frame running vertex shaders, so a small increase
there is probably affordable. 

In a real case, we ought to **validate those assumptions** more thoroughly. How much time is actually spent in the vertex shaders, how much memory 
is spent on meshes. We could also make a script that runs the app above on all the meshes of the game and gather the results in a CSV.

Here we were again, deciding not to do something in order to save time. We decided to keep the conversion, but avoid doing the deduplication of the vertices.
This time however, it was a trade: we traded time during the building of the data, for time and memory at runtime. But it was an **informed decision**, 
our knowledge of the data told us the trade was worth it.

At this point, the afternoon was well under way but we still had time to try something else. So we decided to try to keep the deduplication 
and see what we could do to improve it.

## So, what should we do? #3

Hmm. The std::map is very slow because it gets so big. Maybe we could only check the last N vertices we encountered instead of all of them?

> How can you tell if it's a good idea? And how much is N?

Again, let's observe the data. Mike modified the std::map to also store the last index of each vertex, so that when we encountered a vertex that's already
in the map, we could print the distance between the two occurrences.

We made an histogram to make the values more readable:

    sort -n 1.txt | uniq -c

`sort` sorts the values, `uniq` counts and remove contiguous duplicates (there's no alternative with notepad++, but you can do the same with very few
lines of python). The output looks something like:

    1 5
	3 6
	14 1
	
Meaning that a distance of `1` has been encountered five times, and so on. But that's just an example I made up, not the actual output we got.

The output we got seemed to show that a lot of duplicated vertices were close to each others,
but there were so many numbers that extracting informations visually was pretty difficult.

That's when Mike showed us the second tool of the trade: **the spreadsheet**. With any spreadsheet application, you can easily calculate
the average, standard deviation, [percentiles](https://en.wikipedia.org/wiki/Percentile) and even make graphs.

That helped us confirm that most duplicated vertices were close to each others, and only a small number were very far apart. A few printfs later,
we had the minimum values of N to catch either 80%, 90% or 95% of the duplicated vertices. I don't remember the exact numbers, but they were small, 
around a hundred or so.

With this knowledge, we could have devised a plan to make a cache small enough to be at the same time very fast and efficient enough, but 
the day was coming to an end and we stopped there. 

I think I would have tried a two levels cache with a naive linear search. 
Something like 60-70% of the duplicated vertices were extremely close to each other, maybe with a distance less than 20. So a L1 cache of 20 vertices and 
a L2 cache of around 100-200 vertices could have caught 90-95% of the duplications and would most certainly be a lot faster than the std::map (because
everything would fit in the CPU's cache).

And if the linear search is not fast enough, we could still sort the cache buffer and do a binary search. Or make some kind of fixed size hash map, with 
[quadratic probing](https://en.wikipedia.org/wiki/Quadratic_probing) for example. But I digress, what's important here is not the solution,
it's **the methodology**.

# So, what's the conclusion?

*Know your data*. Know **statistics** about your data. Know what the most common case is, and how frequent it is. 
That's the only way of making sensible decisions about the solution.

And what's more: **investigating your data is super easy!** A few minutes of hacking with printfs, simple tools
like command line utilities, scripts and spreadsheets and you can learn anything you need.




---

## Appendix
### The mesh conversion

For those who are interested, let's explain the conversion that happens inside *tinyobjloader*.

In the OBJ file, there's a list of triangles (that's not the actual OBJ syntax, mine is prettier):

    Triangle 1: 1/1/1  2/2/1  3/3/1
    Triangle 2: 3/3/1  2/2/1  4/4/1
	
Triangles contain 3 groups of indices, one group per vertex. Each index points respectively to a position, a 2D texture coordinate (UV) and a normal.

    Position 1:  0.0   0.0   0.0
    Position 2:  1.0   0.0   0.0
    Position 3:  0.0   1.0   0.0
    Position 4:  1.0   1.0   0.0
	
	UV 1:        0.0   0.0
	UV 2:        1.0   0.0
	UV 3:        0.0   1.0
	UV 4:        1.0   1.0
	
	Normal 1:    0.0   0.0   1.0
	
The problem here is that OpenGL/DirectX tell us that we need to have only one index per vertex to make an index buffer, 
and incidentally, we need to have the same number of positions, UVs and normals. The naive conversion gives us this:

    Triangle 0: 1  2  3
    Triangle 1: 4  5  6
	
	
	Position 1:  0.0   0.0   0.0
    Position 2:  1.0   0.0   0.0
    Position 3:  0.0   1.0   0.0
    Position 4:  0.0   1.0   0.0
    Position 5:  1.0   0.0   0.0
    Position 6:  1.0   1.0   0.0
	
	UV 1:        0.0   0.0
	UV 2:        1.0   0.0
	UV 3:        0.0   1.0
	UV 4:        0.0   1.0
	UV 5:        1.0   0.0
	UV 6:        1.0   1.0
	
	Normal 1:    0.0   0.0   1.0
    Normal 2:    0.0   0.0   1.0
    Normal 3:    0.0   0.0   1.0
    Normal 4:    0.0   0.0   1.0
    Normal 5:    0.0   0.0   1.0
    Normal 6:    0.0   0.0   1.0
	
Ouch, that got a lot bigger. As you can see, vertex 2-5 and 3-4 are identical, leading to a lot of duplicated data.
We could deduplicate them, and that's exactly what the std::map in *tinyobjloader* does. It maps a triplet of indices to a single index, and gets us this:

    Triangle 0: 1  2  3
    Triangle 1: 3  2  4

	
	Position 1:  0.0   0.0   0.0
    Position 2:  1.0   0.0   0.0
    Position 3:  0.0   1.0   0.0
    Position 4:  1.0   1.0   0.0
	
	UV 1:        0.0   0.0
	UV 2:        1.0   0.0
	UV 3:        0.0   1.0
	UV 4:        1.0   1.0
	
	Normal 1:    0.0   0.0   1.0
    Normal 2:    0.0   0.0   1.0
    Normal 3:    0.0   0.0   1.0
    Normal 4:    0.0   0.0   1.0
	
That's better, but on top of being slow to generate, the normals are still duplicated and we can't do anything about it. Or can we?

With this format, the index list usually goes into an index buffer, and the positions/UVs/normals go into vertex buffers,
but since OpenGL 3.0 / DirectX 10, there are other ways of feeding data to a shader and we could use the mesh in its first form.
We could:

 - put the triplet of indices in a vertex buffer
 - put positions/UVs/normals into uniform buffers (constant buffers in DX terms) 
 - draw the vertex buffer without index buffer
 
And then in the vertex shader, we would just have to read the uniform buffers at the index given by the current vertex to get the actual vertex attributes. 
That's one more indirection inside the vertex shader, but that's usually negligible.

With this solution, some data is still duplicated in the vertex buffer (`2/2/1` is present twice in this example). 
But the vertices are so small (3 16 bits ints) that adding an index buffer to deduplicate them would probably take more 
memory in the end. But that may still be worth it if you consider [post-transform vertex cache](https://www.opengl.org/wiki/Post_Transform_Cache).

So, is it worth it? Do you have lots of duplicates in your case? Are they close enough to fit in the post-transform vertex cache of your target platform?
These are the questions you should ask yourself, and now you also know how to answer them :)

