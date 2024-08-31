use anyhow::Result;
use clap::Parser;
use tracing::Level;
use tracing_subscriber::{EnvFilter, FmtSubscriber};

pub mod rtl_config;

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
pub struct CommonArgs {

  /// Log level: trace, debug, info, warn, error
  #[arg(long, default_value = "info")]
  pub log_level: String,

  /// vlen config
  #[arg(long, default_value = "32")]
  pub vlen: u32,

  /// dlen config
  #[arg(long, default_value = "32")]
  pub dlen: u32,

}

pub static MEM_SIZE: usize = 1usize << 32;

impl CommonArgs {

  pub fn setup_logger(&self) -> Result<()> {
    // setup log
    let log_level: Level = self.log_level.parse()?;
    let global_logger = FmtSubscriber::builder()
      .with_env_filter(EnvFilter::from_default_env())
      .with_max_level(log_level)
      .without_time()
      .with_target(false)
      .with_ansi(true)
      .compact()
      .finish();
    tracing::subscriber::set_global_default(global_logger)
      .expect("internal error: fail to setup log subscriber");
    Ok(())
  }
}
