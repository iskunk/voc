@* External Sporth Plugins.

Sporth, a stack-based synthesis language, is the preferred tool of choice for
sound design experimentation and prototyping with Voc.
A version of Voc has been ported to Sporth as third party plugin, known
as an {\it external Sporth Plugin}.


\subsec{Sporth Plugins as Seen from Sporth}
In Sporth, one has the ability to dynamically load custom unit-generators
or, {\it ugens}, into Sporth. Such a unit generator can be seen here in
Sporth code:

\sporthcode{test}

In the code above, the plugin file is loaded via \sword{fl} (function load)
and saved into the table \sword{\_voc}. An instance of \sword{\_voc} is created
with \sword{fe} (function execute). Finally, the dynamic plugin is closed
with \sword{fc} (function close).

\subsec{Sporth plugins as seen from C.}

Custom unit generators are written in C using a special interface provided by
the Sporth API. The functionality of an external sporth ugen is nearly identical
to an internal one, with exceptions being the function definition
and how custom user-data is handled. Besides that, they can be seen as
equivalent.

The entirety of the Sporth unit generator is contained within
a single subroutine, declared |static| so as to not clutter the global
namespace. The crux of the function is a case switch outlining four unique
states of operation, which define the {\it lifecycle} of a Sporth ugen. This
design concept comes from Soundpipe, the music DSP library that Sporth
is built on top of.

These states are executed in this order:

\begingroup
\smallskip
\leftskip=4pc
\item{1.} Create: allocates memory for the DSP module
\item{2.} Initialize: zeros out and sets up default values
\item{3.} Compute: Computes an audio-rate sample (or samples)
\item{4.} Destroy: frees all memory previously allocated in Create
\par
\endgroup

Create and init are called once during runtime, compute is called as many
times as needed while the program is running, and destroy is called
once when the program is stopped.

The code below shows the outline for the main Sporth Ugen.

@(ugen.c@>=
#include <stdlib.h>
#include <math.h>
#include <string.h>
#ifdef BUILD_SPORTH_PLUGIN
#include <soundpipe.h>
#include <sporth.h>
#include "voc.h"
#else
#include "plumber.h"
#endif

#ifdef BUILD_SPORTH_PLUGIN
static int sporth_voc(plumber_data *pd, sporth_stack *stack, void **ud)
#else
int sporth_voc(sporth_stack *stack, void *ud)
#endif
{
    sp_voc *voc;
    SPFLOAT out;
    SPFLOAT freq;
    SPFLOAT pos;
    SPFLOAT diameter;
    SPFLOAT tenseness;
    SPFLOAT nasal;
#ifndef BUILD_SPORTH_PLUGIN
    plumber_data *pd;
    pd = ud;
#endif


    switch(pd->mode) {
        case PLUMBER_CREATE:@/
            @<Creation@>;
            break;
        case PLUMBER_INIT: @/
            @<Initialization@>;
            break;

        case PLUMBER_COMPUTE: @/
            @<Computation@>;
            break;

        case PLUMBER_DESTROY: @/
            @<Destruction@>;
            break;
    }
    return PLUMBER_OK;
}

@<Return Function@>@/

@
The first state executed is {\bf creation}, denoted by the macro
|PLUMBER_CREATE|. This is the state where memory is allocated, tables are
created and stack arguments are checked for validity.

It is here that the top-level function |@<Voc Crea...@>| is called.

@<Creation@>=

sp_voc_create(&voc);
#ifdef BUILD_SPORTH_PLUGIN
*ud = voc;
#else
plumber_add_ugen(pd, SPORTH_VOC, voc);
#endif
if(sporth_check_args(stack, "fffff") != SPORTH_OK) {
    plumber_print(pd, "Voc: not enough arguments!\n");
}
nasal = sporth_stack_pop_float(stack);
tenseness = sporth_stack_pop_float(stack);
diameter = sporth_stack_pop_float(stack);
pos = sporth_stack_pop_float(stack);
freq = sporth_stack_pop_float(stack);
sporth_stack_push_float(stack, 0.0);

@ The second state executed is {\bf initialization}, denoted by the macro
|PLUMBER_INIT|. This is the state where variables get initalised or zeroed out.
It should be noted that auxiliary memory can allocated here for things
involving delay lines with user-specified sizes. For this reason, it is
typically not safe to call this twice for reinitialization. (The author admits
that this is not an ideal design choice.)

It is here that the top-level function |@<Voc Init...@>| is called.

@<Initialization@>=
#ifdef BUILD_SPORTH_PLUGIN
voc = *ud;
#else
voc = pd->last->ud;
#endif
sp_voc_init(pd->sp, voc);
nasal = sporth_stack_pop_float(stack);
tenseness = sporth_stack_pop_float(stack);
diameter = sporth_stack_pop_float(stack);
pos = sporth_stack_pop_float(stack);
freq = sporth_stack_pop_float(stack);
sporth_stack_push_float(stack, 0.0);

@ The third state executed is {\bf computation}, denoted by the macro
|PLUMBER_COMPUTE|. This state happens during Sporth runtime in the
audio loop. Generally speaking, this is where a Ugen will process audio.
In this state, strings in this callback are ignored; only
floating point values are pushed and popped.

It is here that the top-level function |@<Voc Comp...@>| is called.

@<Computation@>=
#ifdef BUILD_SPORTH_PLUGIN
voc = *ud;
#else
voc = pd->last->ud;
#endif
nasal = sporth_stack_pop_float(stack);
tenseness = sporth_stack_pop_float(stack);
diameter = sporth_stack_pop_float(stack);
pos = sporth_stack_pop_float(stack);
freq = sporth_stack_pop_float(stack);
sp_voc_set_frequency(voc, freq);
sp_voc_set_tenseness(voc, tenseness);

if(sp_voc_get_counter(voc) == 0) {
    sp_voc_set_velum(voc, 0.01 + 0.8 * nasal);
    sp_voc_set_tongue_shape(voc, 12 + 16.0 * pos, diameter * 3.5);
}

sp_voc_compute(pd->sp, voc, &out);
sporth_stack_push_float(stack, out);

@ The fourth and final state in a Sporth ugen is {\bf Destruction}, denoted
by |PLUMBER_DESTROY|.  Any memory allocated in |PLUMBER_CREATE|
should be consequently freed here.

It is here that the top-level function |@<Voc Dest...@>| is called.
@<Destruction@>=
#ifdef BUILD_SPORTH_PLUGIN
voc = *ud;
#else
voc = pd->last->ud;
#endif
sp_voc_destroy(&voc);

@ A dynamically loaded sporth unit-generated such as the one defined here
needs to have a globally accessible function called |sporth_return_ugen|.
All this function needs to do is return the ugen function, which is of type
|plumber_dyn_func|.
@<Return Function@>=
#ifdef BUILD_SPORTH_PLUGIN
@[plumber_dyn_func sporth_return_ugen() @]
{
    return sporth_voc;
}
#endif

@ \subsec{A Ugen for the Vocal Tract Model}
@(ugen.c@> +=

#ifdef BUILD_SPORTH_PLUGIN
static int sporth_tract(plumber_data *pd, sporth_stack *stack, void **ud)
{
    sp_voc *voc;
    SPFLOAT out;
    SPFLOAT pos;
    SPFLOAT diameter;
    SPFLOAT nasal;
    SPFLOAT in;

    switch(pd->mode) {
        case PLUMBER_CREATE:@/
            sp_voc_create(&voc);
            *ud = voc;
            if(sporth_check_args(stack, "ffff") != SPORTH_OK) {
                plumber_print(pd, "Voc: not enough arguments!\n");
            }
            nasal = sporth_stack_pop_float(stack);
            diameter = sporth_stack_pop_float(stack);
            pos = sporth_stack_pop_float(stack);
            in = sporth_stack_pop_float(stack);

            sporth_stack_push_float(stack, 0.0);
            break;
        case PLUMBER_INIT: @/
            voc = *ud;
            sp_voc_init(pd->sp, voc);
            nasal = sporth_stack_pop_float(stack);
            diameter = sporth_stack_pop_float(stack);
            pos = sporth_stack_pop_float(stack);
            in = sporth_stack_pop_float(stack);

            sporth_stack_push_float(stack, 0.0);
            break;
        case PLUMBER_COMPUTE: @/
            voc = *ud;
            nasal = sporth_stack_pop_float(stack);
            diameter = sporth_stack_pop_float(stack);
            pos = sporth_stack_pop_float(stack);
            in = sporth_stack_pop_float(stack);

            if(sp_voc_get_counter(voc) == 0) {
                sp_voc_set_velum(voc, 0.01 + 0.8 * nasal);
                sp_voc_set_tongue_shape(voc, 12 + 16.0 * pos, diameter * 3.5);
            }

            sp_voc_tract_compute(pd->sp, voc, &in, &out);
            sporth_stack_push_float(stack, out);
            break;
        case PLUMBER_DESTROY: @/
            voc = *ud;
            sp_voc_destroy(&voc);
            break;
    }

    return PLUMBER_OK;
}
#endif
@ \subsec{A multi ugen plugin implementation}
New Sporth developments contemporary with the creation of Voc have lead to
the development of Sporth plugins with multiple ugens.

@(ugen.c@>+=
#ifdef BUILD_SPORTH_PLUGIN
static const plumber_dyn_func sporth_functions[] = {
    sporth_voc,
    sporth_tract,
};

int sporth_return_ugen_multi(int n, plumber_dyn_func *f)
{
    if(n < 0 || n > 1) {
        return PLUMBER_NOTOK;
    }
    *f = sporth_functions[n];
    return PLUMBER_OK;
}
#endif

@* Sporth Code Examples.

Here are some sporth code examples.

\subsec{Chant}
\sporthcode{chant}

\subsec{Rant}
\sporthcode{rant}

\subsec{Unya}
\sporthcode{unya}

