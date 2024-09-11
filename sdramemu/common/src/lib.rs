use anyhow::Result;
use plusarg::PlusArgMatcher;
use tracing::Level;
use tracing_subscriber::{EnvFilter, FmtSubscriber};

pub mod rtl_config;
pub mod plusarg;

pub struct CommonArgs {

  /// Log level: trace, debug, info, warn, error
  pub log_level: String,

  /// vlen config
  pub vlen: u32,

  /// dlen config
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

    pub fn from_plusargs(matcher: &PlusArgMatcher) -> Self {
        Self {
            log_level: matcher.try_match("log-level").unwrap_or("info").into(),
            vlen:matcher.try_match("vlen").unwrap_or("32").parse().unwrap(),
            dlen:matcher.try_match("dlen").unwrap_or("32").parse().unwrap(),
        }
    }
}
