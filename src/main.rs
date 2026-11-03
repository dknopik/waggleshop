use std::{net::Ipv4Addr, time::Duration};

use anyhow::Result;
use clap::Parser;
use futures::StreamExt;
use libp2p::{Multiaddr, SwarmBuilder, multiaddr::Protocol, swarm::SwarmEvent};
use tracing::{info, warn};
use tracing_subscriber::EnvFilter;
use waggle::{
    behaviour::{Behaviour, Event},
    config::Config,
};

/// A libp2p node running waggle.
#[derive(Parser)]
struct Args {
    /// Where to listen: a port on localhost, or a multiaddr. Port 0 picks a
    /// free one.
    #[arg(short, long, value_name = "PORT|MULTIADDR", default_value = "0", value_parser = parse_addr)]
    listen: Multiaddr,

    /// Nodes to connect to: ports on localhost, or multiaddrs. Repeat the
    /// flag or separate them by commas.
    #[arg(short, long, value_name = "PORT|MULTIADDR", value_delimiter = ',', value_parser = parse_addr)]
    connect: Vec<Multiaddr>,
}

/// Parses an address given on the command line. A bare port means a node
/// on localhost.
fn parse_addr(s: &str) -> Result<Multiaddr, String> {
    match s.parse::<u16>() {
        Ok(port) => Ok(Multiaddr::empty()
            .with(Protocol::Ip4(Ipv4Addr::LOCALHOST))
            .with(Protocol::Udp(port))
            .with(Protocol::QuicV1)),
        Err(_) => s.parse().map_err(|e| format!("{e}")),
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();
    let args = Args::parse();

    let mut swarm = SwarmBuilder::with_new_identity()
        .with_tokio()
        .with_quic()
        .with_behaviour(|_| Behaviour::new(Config::default()))?
        // Waggle keeps a connection alive only while subscription streams are
        // open on it. Keep idle connections too, so nodes stay connected
        // before they subscribe to anything.
        .with_swarm_config(|config| {
            config.with_idle_connection_timeout(Duration::from_secs(u64::MAX))
        })
        .build();

    swarm.listen_on(args.listen)?;
    for addr in args.connect {
        swarm.dial(addr)?;
    }

    let mut state = State::default();

    // Subscribe to your topic(s) here.
    // let recv = swarm.behaviour_mut().subscribe("name".to_string().into_bytes());

    loop {
        tokio::select! {
            event = swarm.select_next_some() => on_swarm_event(event, &mut state),
            // Poll your topic receivers here, next to the swarm.
        }
    }
}

#[derive(Default)]
struct State {
    // Put the required state of your application here.
}

fn on_swarm_event(event: SwarmEvent<Event>, state: &mut State) {
    match event {
        SwarmEvent::NewListenAddr { address, .. } => info!(%address, "listening"),
        SwarmEvent::ConnectionEstablished {
            peer_id, endpoint, ..
        } => info!(%peer_id, address = %endpoint.get_remote_address(), "connected"),
        SwarmEvent::ConnectionClosed { peer_id, cause, .. } => {
            info!(%peer_id, ?cause, "disconnected")
        }
        SwarmEvent::OutgoingConnectionError { peer_id, error, .. } => {
            warn!(?peer_id, %error, "failed to connect")
        }
        SwarmEvent::Behaviour(event) => on_waggle_event(event, state),
        _ => {}
    }
}

fn on_waggle_event(event: Event, _state: &mut State) {
    match event {
        // Store `sender` to send the peer pieces on the topic. Dropping every
        // clone of it, as this does, ends the peer's subscription.
        Event::Subscribed {
            peer_id, topic_id, ..
        } => {
            info!(%peer_id, topic = %String::from_utf8_lossy(&topic_id), "peer subscribed");
        }
        Event::Unsubscribed {
            peer_id, topic_id, ..
        } => {
            info!(%peer_id, topic = %String::from_utf8_lossy(&topic_id), "peer unsubscribed");
        }
    }
}
