#set page("us-letter", numbering: "1 of 1")
#align(center)[
	= Scheduler Report

	Arvinder Dhanoa |  Steven Sommers
]

#pagebreak()

#set block(spacing: 1.5em)
#set text(
	font: "New Computer Modern",
	size: 1em
)
#set par(
	justify: true,
	leading: 1em,
	first-line-indent: 2em
)
#show heading: it =>  {
    it
    par()[#text(size:0.5em)[#h(0.0em)]]
}

= Introduction

Schedulers are an important part of computer science, focusing on balancing and
juggling tasks, deciding which task deserves how much time. Implementing these
schedulers was an educational experience, both from a programmer's perspective
as well as from a theoretical point of view. This was a good chance to both
familiarize one of us with a new programming language (Steven), while still
limiting how many dependencies / environment we had to interact with. Watching
these schedulers work also lead to us understanding more the emergent behavior
these algorithms have, and a better foundational logic on the tradeoffs these
algorithms make.

= Contributions

Before talking about specifically what characteristics our implementations of
our schedulers had, it's worth noting what each of us did. The majority of the
schedulers were written by Steven, while Arvinder wrote most of the driver, and
GUI / logging logic. With that said, there are some design decisions we made
early on that likely weren't ideal in the long term.

= Implementation

Our implementation was done in rust. We specifically chose rust since it would
be a good programming language to choose for real operating system schedulers.
It gives explicit control over memory much like C/C++, while still benefiting
from higher level APIs and safer programming ideas that have come out since the
advent of these languages. Specifically, the memory safe aspect of rust allowed
us to debug far easier - since it meant we never ran into any kind of segfault
or undefined behavior. We did run into issues with the "borrow checker", or the
model rust uses to check the correct usage of memory (e.g. absence of use after
frees, double frees, out of bounds memory access, etc.), but these issues were
relatively easy to resolve.

The core implementation detail of our model was the `Scheduler` trait. Our
schedulers all shared this singular interface. Our `Scheduler` trait worked
for both our Ready and I/O queue, and as a result allowed the *implementation*
to not care about which kind of Scheduler it was. We could trivially add other
kinds of Schedulers as well, and the implementations would have to largely
be unchanged to accomodate that. Despite that, we did run into issues with
duplicating logic outside of the implementation, specifically in our logger -
but we don't believe the Scheduler trait to be entirely at fault here.

A scheduler, atleast according to us, is a type that implements two functions,
as well as a function that helps us understand the internal state of the
Scheduler:

#pagebreak()
```rs
pub trait Scheduler {
    fn tick(&mut self, system_state: &SystemState) -> SchedulerResult;
    fn enqueue(&mut self, proc: Process);
    // this is here so we can see the internal state.
    fn get_queue(&self) -> Vec<&Process>;
}
```

A `tick()` represents a single unit time passing \- *not* a quantum time.
Each time tick() is called, the Scheduler makes some progress on an underlying
process (or rather, the `PCB`, which we just call `Process` here), and returns
information about what it did. Specifically, it can say the following:

```rs
pub enum SchedulerResult {
    Finished(Process),
    // remaining burst
    Processing(Process),
    Idle,
    WrongKind,
    NoBurstLeft,
}
```

`Finished(Process)` represents having finished working on a burst on a Process,
and giving it back to the caller of `tick()` to choose what to do with the
`Process` next. `Processing(Process)` informs the caller that it did some
work on the given Process, and will continue to do so the next time it calls
`tick()`. `Idle` simply means that for some reason the Scheduler didn't do any
work that run, while `NoBurstLeft` means that the Scheduler queue is empty.
`WrongKind` is a programmer error, and it means that the Scheduler was given a
process with the wrong kind of Burst. E.G. a `Process` needs `IO` bursts next,
but was given to a `CPU` scheduler.

For a scheduler that cares about Quantum Time, the Quantum Time must be stored
internally, as well as how long inside this quantum time has passed as well.
This isn't exposed to the caller.

A practical and simple implementation is the FCFS scheduler, which simply takes
the front process in it's queue, does work on the burst if it's of the right
type, and then returns whether it finished or not. For the sake of keeping all
the code on one page, this code is shown on the next page.

#pagebreak()
```rust
match process.burst.front_mut() {
    Some(Burst(kind, burst_amt)) if self.kind == *kind => { 
        // if the burst kind matches, (both the scheduler and the
        // process are of the same type), remove 1 from the burst.
        // Then, either get rid of the burst and return Finished(proc)
        // or return Processing(proc) depending on whether the burst
        // is over.
        *burst_amt -= 1;
        if *burst_amt == 0 {
            let mut proc = self.processes.pop_front().unwrap();
            proc.burst.pop_front().unwrap();
            SchedulerResult::Finished(proc)
        } else {
            SchedulerResult::Processing(self.processes[0].clone())
        }
    },
    // in this case this is burst is meant for a different kind of
    // scheduler. Something went wrong.
    Some(Burst(_, _)) => SchedulerResult::WrongKind,
    // and we're out of bursts to process on this process!
    // something went wrong.
    None => SchedulerResult::NoBurstLeft,
}```

The job of the Driver then is to take a scheduler, a list of processes, and
if any processes have arrived (that is the current system time $>=$ arrival
time for any given process), you schedule it on the according scheduler that
it requires. You then call `tick()` on all schedulers after. When a `tick()`
returns `Finished(Process)`, you check what burst it needs next, and queue it to
go on that scheduler at the end of the tick as well.

This design worked relatively well. It was intuitive to think about, and in
practice just about everything a `Scheduler` would care about functioned in
terms of our `tick`s well. The caller didn't really have to worry about how the
Scheduler worked, and the abstraction was relatively clean.

A harder aspect to juggle, was actually getting statistics of our Scheduler.
While our Schedulers themselves didn't care about what kind of item they were
scheduling, this aspect of our code *definetly* did. What we did in order to
gather statistics about our code, was take the status of the entire system
state (that is, the finished processes, processes left to schedule, the queues
of the schedulers, and what they did), and added them to a list of log entries.
Our GUI, and logging implementation, then worked backwards to figure out what
events were occuring. They looked at the state of the system at the previous
`tick`, and the state of the current `tick`, and worked backwards to figure out
what must of occured on the current tick. For instance, if previously no process
was scheduled by the system, and one arrived this tick, a new process must have
arrived. A benefit of this approach was that because it stored the state of
the *entire* system in the logs, it was trivial to make the GUI be able to work
forwards or backwards in time, since that just meant passing a different subset
of logs.

Our `draw_frame` took a list of log entries, and drew what it wanted to show
on screen based off of that historical context. getting the nth frame is just
`Self::draw_frame(&mut self.term, &log_entries[0..n])` We then let the user
manipulate `n` with keyboard input and that allowed both forwards and backwards
time travel.

= Exploring the Simulations
#image("round-robin-equal.svg")
The above is a round robin run with all processes using a CPU burst of 4,
followed by an IO burst of 4, and then a CPU burst of 4. As we can see, an
interesting thing to note with round robin seems to be that it works to complete
all CPU work that arrived at the same time all at once, given that they're
similar work loads. This results in starving I/O until it gets flooded all at
once, and the round robin CPU scheduler is left with no work to do until the I/O
finishes on a process. Over time, this should even out (and although not graphed
above, we have tested it and seen that it does happen), but the wait time /
throughput of round robin isn't ideal. It *does* happen to be particularly good
at guaranteeing your process will get CPU time eventually, unlike what we expect
of SJF. This means that if your process count is bounded, it can guarantee you
get a certain amount of cpu time after a certain amount of quantum ticks, which
is ideal for real time systems. Although SJF isn't implemented, we'd expect
it to have the opposite tradeoff, where it would constantly try it's best to
keep both CPU / IO fed, at the drawback of not guaranteeing any longer CPU
time processes any (or atleast, less) cpu time. Our guess is round robin would
struggle with processes with similar large CPU bursts and IO bursts, since it
would starve itself when all processes get put on the IO queue at around the
same time.

#image("fcfs-equal.svg")
The above is FCFS under the same conditions. In this case we can see that it
performs exceptionally well where everything has equal bursts, since it keeps
everything fed. This results in it performing slightly better then round robin
in terms of cpu utilization, where round-robin performed at a 97%, FCFS got
100%.

Priority isn't included since in this case it performs exactly the same as FCFS
(since all the processes have the same priority).

It's worth noting as far as the priority case - We'd expect that generally
high priority processes wouldn't take much CPU / IO time. Things like OS
services which want to run *regularly*, but not nessecarily a lot of load in
of themselves. Assuming this holds true, we can see a huge benefit to using
priority in terms of it's low wait times for these high priority tasks, and
in this case larger tasks for your actual workload aren't terribly adversely
affected. We tested this on 4 processes, 3 being high priority and 1 being low.
The high priority processes had 2 cpu bursts of 2 unit time, and 2 IO bursts
of 2 unit time. The low priority process had a far higher 8 cpu and 8 IO. The
result was a wait of 11 on the low priority process and turn around of 43. The
lowest a high priority process did was a turn around of 13 and a wait of 5. We
didn't graph the execution due to how large the graph would be, but overall we
thought this matched our expectations for how it would play out - low priority
processes that wanted a large chunk of resources did relatively fine.

Oddly enough, when doing the same test with Round Robin, we get the same score
for wait and turnaround for the low priority. We speculate the reason why
round robin does as well as priority in this case is because the high priority
processes kept both CPU and I/O saturated in both round robin and priority
regardless. When they finished, the low priority process was the only one left
\- and because it was the last, it's wait was the sum of half of all the high
priority process's bursts. Because both CPU and I/O were saturated in either
case, the only thing that mattered would be whichever process finished last must
have the greater of the sum of the bursts of the CPU \/ IO processes infront
of it.

= Conclusions
Implementing this scheduler was an intersting problem, and we learned a lot
from it. We did have some design choices we regretted (this is the second
itteration of our logger, but we still aren't quite happy with it), but overall
we considered  it largely a success. Our project implemented everything we
wanted too, and although we didn't implement threads or multicore support - we
did mostly succeed in every aspect the assignment we wanted too in. Seeing how
different (and maybe more importantly how similar), these schedulers were from
one another in terms of behavior was useful.