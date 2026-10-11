//! Cairn core: deterministic finance math.
//!
//! Design rule: the LLM never does arithmetic. Everything numeric lives here
//! (and in crates built on it), and is exposed to agents as MCP tools.

pub mod money;

pub use money::{Money, MoneyError};
