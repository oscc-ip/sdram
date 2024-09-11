use common::{plusarg::PlusArgMatcher,  CommonArgs};

pub mod dpi;
pub mod drive;

pub(crate) struct OfflineArgs {
    pub common_args: CommonArgs,

    #[cfg(feature = "trace")]
    pub wave_path: String,

    #[cfg(feature = "trace")]
    pub dump_range: String,
}

pub const AXI_SIZE: u8 = 32;

impl OfflineArgs {
    pub fn from_plusargs(matcher: &PlusArgMatcher) -> Self {
        Self {
            common_args: CommonArgs::from_plusargs(matcher),
            #[cfg(feature = "trace")]
            dump_range: matcher.match_("dump-range").into(),
            #[cfg(feature = "trace")]
            wave_path: matcher.match_("wave-path").into(),
        }
    }
}
