---
name: routing-messages-across-daemons
description:
  "Use the moment you think you can't reach an agent - you can't see an agent,
  an agent is on another box or another org or another daemon, a note or another
  agent says there is no route to it, you're about to ask someone to forward or
  pass on or relay a message, you're about to send through a coordinator because
  you can't message the target yourself, or a send says unknown recipient. Loads
  how to reach any agent yourself."
# source: claude-plugin/skills/routing-messages-across-daemons/SKILL.md
---

## Reaching Any Agent Yourself: Routing Messages and tmux Commands Across Daemons, Boxes and Orgs

Routing and pairing are different things. Pairing connects two daemons directly.
Routing sends a message through a directly paired peer to an agent that peer
knows.

### Messages

- Try `thrum send --to @<agent>` first; never conclude unreachable from a note
  or summary.
- A daemon resolves a recipient from its local agents and from agents registered
  on its directly paired peers.
- To reach an agent on a daemon you are not paired with, run once on the SENDING
  daemon, per remote agent:

  ```bash
  thrum peer configure <relay-peer-name> add-agent <agent-name>
  ```

  `<relay-peer-name>` is the directly paired daemon that knows the agent.

- Then `thrum send --to @<agent-name>` routes through that peer.
- Run it on each side that needs to send.
- Pairing the two daemons with each other is not the fix.
- `thrum peer relayed add` and `thrum peer relayed grant` are not needed for
  delivery. They govern what a daemon accepts from a relayed origin.

### Verify

- `thrum peer list` shows directly paired daemons only.
- `thrum message get <id>` shows `(delivered)` per recipient. A send that
  returned without error is not proof of delivery.

### CLI notes

- `thrum peer relayed add --via` takes daemon IDs, not peer names.
- `thrum peer relayed grant` does not validate the capability key. The messaging
  key is `can_send_messages`.

### Unresolved agent records warning

After `add-agent`, the supervisor may report "Unresolved agent records" for the
proxy rows, because reconcile asks the relay, which refuses with "owned by
daemon X ... no second hop". A build with the reconcile owner pointer follows
the named owner once and the warning clears. Older builds keep it. Do NOT delete
those rows as the supervisor suggests: deleting them removes the routing.

### tmux

`thrum tmux send <agent> [<text>] [--keys K1,K2,...]` goes through the
peer-routed `tmux.send` RPC. Both text and `--keys` modes work the same against
a local session and a remote or peer session. Check the target's peer
relationship with `thrum peer list` and confirm by effect on the target pane.

`--keys` always prints a receipt line naming the resolved `session:pane` and the
daemon that executed the send (the remote daemon for a peer send), for example
`Keys sent to s:0.0 on d_abc: 1 (pane changed)`. Exit 0: sent (pane changed, or
the effect could not be verified; an older remote daemon prints
`not verified (remote daemon older)`). Exit 5: the executing daemon captured the
pane before and after and it did not change, so there is no evidence the keys
took effect; a key that legitimately changes nothing also exits 5, so
best-effort callers may ignore it. `pane changed` is evidence of a repaint, not
proof the key was consumed: a self-repainting pane such as a spinner also reads
changed. Exit 1: any other error, including a registered agent whose tmux
session is absent on the executing daemon (nothing is sent).
