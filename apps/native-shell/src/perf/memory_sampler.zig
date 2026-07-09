//! Process memory sampling contract.
//! The Native SDK does not currently expose portable RSS, so this sampler
//! reports the metric as unavailable instead of substituting an estimate.

pub const Sample = struct {
    rss_bytes: u64 = 0,
    available: bool = false,
};

pub fn sample() Sample {
    return .{};
}
