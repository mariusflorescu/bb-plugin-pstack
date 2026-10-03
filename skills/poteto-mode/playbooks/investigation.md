### Investigation

**You own the answer. Plan, route, write.**

Investigation requests are read-only. They produce a cited explanation or a recommendation, not a code change.

Size the task first, per the size lanes in poteto-mode's Playbooks section. The lane decides which steps below run, and a step it drops stays as `skip: size <size>`.

1. Route through the **how** skill. For motivation questions, also route through the **why** skill. Before an open-ended research fan-out, state the underlying goal in one line. If the request does not say why, ask the user one question first.
2. Throughput checkpoint stays one line: `throughput checkpoint: n/a, read-only investigation`.
3. Produce the `how`-shaped output (Overview / Key Concepts / How It Works / Where Things Live / Gotchas), or a recommendation with a tradeoffs table if the request is a decision between alternatives.
4. Apply the **unslop** skill to the reply.

No PR, no babysit, no `architect` unless the investigation precedes a code change. If it does, hand back to the user and re-route to Bug fix or Feature. An `/architect` request that says "no code" takes the **architect** skill's report-only exit in Phase C instead. It stops after Phase B's synthesis and delivers the design report.

**Reply:** the investigation output. For "are we sure?" answers, include your real judgment with reasons. Push back if the premise is wrong (see Autonomy).
