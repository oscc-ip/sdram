use clap::Parser;
use common::CommonArgs;

pub mod dpi;
pub mod drive;

#[derive(Parser)]
pub(crate) struct OfflineArgs {
    #[command(flatten)]
    pub common_args: CommonArgs,

    #[cfg(feature = "trace")]
    #[arg(long)]
    pub wave_path: String,

    #[cfg(feature = "trace")]
    #[arg(long, default_value = "")]
    pub dump_range: String,

    #[arg(long, hide = true, default_value = env!("TIMEOUT"))]
    pub timeout: u64,
    
    #[arg(long, hide = true,default_value = env!("CLOCK_FLIP_TIME"))]
    clock_flip_time: u64,
}

pub const AXI_SIZE: u8 = 32;
