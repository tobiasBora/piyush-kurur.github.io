---
title: Adventures in optimising ChaCha20 for Raaz.
tags: Raaz, Cryptography, Haskell
---

In this post, I note down some of the things I learned while
optimising ChaCha20 implementation in the Raaz library.

**TLDR:** Do not waste time on hand optimising when there is GCC, the
beast from the savanna.

## A brief description of the ChaCha20

We have a chacha state which is essentially a 4x4 matrix of 32-bit
unsigned word (`Word32` in Haskell). The main body of the chacha
transform consists of performing a quarter round, QROUND from now on,
first on all the rows of the matrix and then on each of the diagonals
of the matrix. For example, if the matrix is

```
	x0  x4  x8   x12
	x1  x5  x9   x13
	x2  x6  x10  x14
	x3  x7  x11  x15

```

Then a single round of ChaCha20 is the following operations.

```

	QROUND(x0, x4, x8,  x12); // QROUND(row0)
	QROUND(x1, x5, x9,  x13); // QROUND(row1)
	QROUND(x2, x6, x10, x14); // QROUND(row2)
	QROUND(x3, x7, x11, x15); // QROUND(row3)


	QROUND(x0, x5, x10, x15); // QROUND(diag0)
	QROUND(x1, x6, x11, x12); // QROUND(diag1)
	QROUND(x2, x7, x8,  x13); // QROUND(diag2)
	QROUND(x3, x4, x9,  x14); // QROUND(diag3)

```

The chacha20 stream is generated by performing this row and diagonal
transformations 20 times followed by some adding up.

The first step was to get a portable version of ChaCha20 with the
associated tests, which was done without much difficulty. You can have
a look at it
<https://github.com/raaz-crypto/raaz/blob/master/cbits/raaz/cipher/chacha20/cportable.c>
There was nothing clever here other than making sure that the
variables xi's are declared register.

## Vector optimisations

The quarter round essentially consists of only addition and xor. It
can easily be seen that the 4-row operations are independent of each
other. Similarly the four diagonal operations are independent of each
other. If we store each of the rows in a 128-bit vector consisting of
4 `Word32`'s, then the 4-row QROUND can be performed by a single
vector version of QROUND. In other words, if we have the vectors

```
V0 = {x0,   x1,   x2,   x3 };
V1 = {x4,   x5,   x6,   x7 };
V2 = {x8,   x9,   x10,  x11};
V3 = {x12,  x13,  x14,  x15};



```

then the _single_ `QROUND(V0,V1,V2,V3)` performs the `QROUND` for all
the rows.  For the diagonal ones we need to shift `V1`,`V2`, and `V3`
by 1, 2, and 3 positions to the left respectively and perform a
_single_ `QROUND(V0,V1,V2,V3)` again.

The optimisation for 256-bit vector instructions is similar, but we
have to do 2-chacha blocks at a time. This is possible because the two
chacha20 blocks differ only by a counter and can be done in parallel.


With the above optimisations I wrote two versions, one using the
   128-bit vector the other using 256-bit version using the support
   for vector types in GCC. Again the implementation was delightfully
   simple, in fact in many ways much simpler than the portable one
   because now we can use vector types.  The result of these
   optimisations were not very impressive though.

1. The performance of 128-bit vector version as compared to the
   portable version does not improve at all (actually it is slightly
   worse) instead of the expected 2x improvement.

2. The performance of 256-bit version with avx2 is better than the
   portable one by roughly a factor of 2x where as the naive
   expectations are a 4x improvement[^overhead].

I did look at the generate assembly and the code looked much like what
was expected. The 128-bit code was using `%xmm` registers as expected
and the 256-bit version was using the `%ymm` registers.


## Letting the beast loose.

Cabal install and stack compiles C code with `-O2`. Just to see what
has GCC got under its hood, I compiled stuff with the flags `-O3` and
what a surprise/shock I had. The portable C started competing with the
256-bit implementation. The generated assembly had the SIMD registers
in it. Encouraged, I decided to throw in the `-march=native` and the
figures blew me off. The portable C implementation was giving me an
insane 14.4 Gbps where as the 256-bit one was only giving me 9.55Gbps.


## Final tweaking and Cabal flags.

I can make two assumptions on the the message blocks because they are
used only through FFI. Firstly, I can assume that the message block is
32-byte (256-bit) aligned by making sure that the Haskell stub
function only passes 32-byte aligned buffers to the portable C
implementation. Implementations of primitives in Raaz are instances of
the `BlockAlgorithm` class. All I need to do is to ensure is that
`bufferStartAlignment` is 32 for portable C implementation as opposed
to word alignment. I can also assume that the pointer is not
aliased. This two tweaks gives only minor improvements and need not be
included at all.

The final performance figures are available at:

<https://gist.github.com/piyush-kurur/93955e669ab72a51996590bfc106677d>

The cabal package now has two flags `opt-native` and `opt-vectorise`
which results in adding the flags `-O2 -ftree-vectorize
-march=native`. These are not enabled by default but can be enabled if
you are compiling for yourself. With these changes there is no more a
need for the vector implementations. I am keeping it for historical
records.

## Who should not enable the above flags?

If you are cross compiling, for example, when you are compiling the
code for packaging for a distro, it is not advisable to enable these
flags. Note that the native in this case would mean the machine on
which it is compiled and not on the one where it is run. There is not much
of an advantage in the hand coded vector implementation either because one
cannot make assumptions on the target.

If you know that your target machine supports vector instructions, you
can vectorise with `-O2 -ftree-vectorize`. Throw in an `-mavx2`, if
you are sure of its supported on the target, and get most of the
performance described above. This would be the use case when you are
compiling on your local machine but deploying on the cloud for
example.

**Update:** I got rid of the `restrict` key word in the portable c
file because not all GCC versions seem to be familiar with it.

[^overhead]: The naive expectation will not hold because of some vector overheads.
