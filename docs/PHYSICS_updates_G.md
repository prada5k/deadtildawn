### 6.v Why did I lose: splitting the gap by cause (`sim/breakdown.py`)

Game design (Spire): after every race, show where Faba gained and lost time
and why, so the player knows what to build. This is analysis of two runs'
telemetry, not a model change: the sim's results are untouched.

**Bookkeeping.** Both cars run on the same distance grid. The gap at node $i$
is $g_i = t_{them}(s_i) - t_{me}(s_i)$ ($> 0$: Faba got there first). Each
interval adds $\Delta g_i = \Delta t_{them,i} - \Delta t_{me,i}$, so

$$g_{final} = g_0 + \sum_i \Delta g_i$$

exactly (a telescoping sum). $g_0$ is the difference in launch reactions (6.z).
Every $\Delta g_i$ goes in one bucket, so **the buckets always add up to the
final gap** (tested: within 3-decimal rounding).

| bucket | where |
|---|---|
| launch | $g_0$ |
| corner | inside a corner |
| mistake | inside a corner where either driver ran wide, plus the exit lost on the straight after it |
| braking | either car on the brakes |
| exit / accel | the rest of each straight, split below |

**Exit vs acceleration (work-energy theorem).** On a straight, is Faba losing
because he came out of the last corner slower, or because the other car pulls
harder? Net force per kg $a(s)$ does work: $d(v^2/2) = a\,ds$. If both cars had
the same $a(s)$ from the start of the straight at $s_a$, their $v^2$ would
differ by the same constant all the way:

$$v'(s)^2 = v_{them}(s)^2 + \left(v_{me}(s_a)^2 - v_{them}(s_a)^2\right)$$

$v'$ is a what-if Faba: his exit speed, their acceleration. The time the
what-if gains on them is **exit**; the rest of the real gain is **accel**
(power-to-weight, traction, gearing). Note the speed advantage itself fades as
both speed up ($\Delta v \approx \Delta(v^2)/2v$), which is why a good exit
matters most on the straights right after slow corners.

**Hand calcs (tests/test_breakdown.py)**, 100 m straight:

- Constant 25 vs 20 m/s: $100/20 - 100/25 = 1.0$ s, all exit (neither accelerates).
- Same entry 20 m/s, $a$ = 3 vs 2 m/s$^2$, $t = (v - v_0)/a$: $(\sqrt{800}-20)/2 - (\sqrt{1000}-20)/3 = 4.1421 - 3.8743 = 0.268$ s, all accel.
- Same $a$ = 2, entry 22 vs 20: $(\sqrt{800}-20)/2 - (\sqrt{884}-22)/2 = 4.1421 - 3.8661 = 0.276$ s, all exit (the what-if IS Faba's run).
- Corner, 50 m at 20 vs 18 m/s: $50/18 - 50/20 = 0.278$ s in the corner bucket; if they ran wide and left at 18 instead of 20 m/s (both 2 m/s$^2$ after), the 50 m exit adds $0.198$ s, and all $0.476$ s is the mistake.
- Real runs: identical runs give zero everywhere; a car 250 kg lighter (theoretical limit) wins mostly on acceleration; reaction difference = launch bucket.

**A bug the tests caught.** The what-if speed is floored so $v'^2$ can't go
negative. A floor of 0.5 m/s also applied at the start line, where both cars
are at 0, making identical runs show a fake "exit" gain. The floor now only
applies where $v_{them}^2 + c$ would really drop below it.

**Sections** (the replay's split captions and the results map): one per
corner, from the previous corner's exit to this one's, plus the run to the
line. A section's `top_cause` is its biggest bucket by size.

**Verdict** (Faba's line): the bucket with the biggest loss if he lost, the
biggest gain if he won; "crash" / "their_crash" if a crash decided it (the
breakdown then covers only the distance both cars drove).
