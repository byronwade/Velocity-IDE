//! Process lease — time-bounded ownership of a governor record.
pub const Lease = struct { process_id: u32 = 0, feature_id: []const u8 = "", expires_ms: u64 = 0 };
