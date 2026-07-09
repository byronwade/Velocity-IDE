//! LSP broker boundary stub.
//! Shell → broker → external language server processes.
//! Does not depend on VS Code extension host.

pub const BrokerState = enum { idle, starting, ready, failed };

pub const Broker = struct {
    state: BrokerState = .idle,
    active_servers: u32 = 0,
};
