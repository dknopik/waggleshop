# Waggle workshop

A minimal libp2p node running [waggle](https://github.com/dknopik/waggle/tree/alternate-design),
ready for you to build on. It listens on QUIC, connects to the nodes you tell it to, and logs
what happens. Waggle is set up with its default config, but the node subscribes to nothing yet.
That part is up to you.

## Before the workshop

Install a recent stable Rust toolchain via [rustup](https://rustup.rs), then clone this repo
and build it once:

```sh
cargo build
```

The first build downloads and compiles libp2p, which takes a while. Please do it at home rather
than on the venue Wi-Fi.

## Running nodes

Start each node in its own terminal. `-l` sets the port to listen on, and `-c` names the nodes
to connect to:

```sh
cargo run -- -l 9000
cargo run -- -l 9001 -c 9000
cargo run -- -c 9000,9001
```

Both flags take either a port on localhost or a full multiaddr, for example
`-c /ip4/192.168.1.23/udp/9000/quic-v1` to reach a node on another machine. That node needs to
listen on a reachable interface, like `-l /ip4/0.0.0.0/udp/9000/quic-v1`.

Without `-l`, the node picks a free port and logs it. Set `RUST_LOG` for more detail, for
example `RUST_LOG=info,waggle=debug`.

### Starting many nodes at once

`start.sh` builds the node, then starts several of them on localhost, connected in a full mesh
or in a line. Their output is interleaved, with each line prefixed by its node's name.
Ctrl-C stops them all.

```sh
./start.sh mesh        # 4 nodes, every node connected to every other
./start.sh line 10     # 10 nodes, each connected to the one before it
./start.sh -p 9100 mesh 3   # 3 nodes, listening on ports 9100 and up
```

Arguments after `--` go to every node, which is handy once you add flags of your own:
`./start.sh line -- --my-flag`. The script needs bash. On Windows, run it from WSL or Git Bash.

## Where to start

Everything lives in `src/main.rs`. The waggle API is small:

- `swarm.behaviour_mut().subscribe(topic)` subscribes to a topic and returns a receiver of
  `TopicEvent`s: the pieces your peers send on that topic, plus the opening and closing of each
  peer's stream. Dropping the receiver unsubscribes.
- `Event::Subscribed` fires when a peer subscribes to a topic on your node. It carries a
  `PieceSender` for sending that peer `ObjectPieces`. Dropping the sender ends the peer's
  subscription.

Run `cargo doc --open -p waggle` to browse the full API docs.
