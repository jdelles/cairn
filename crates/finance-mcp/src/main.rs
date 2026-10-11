//! Cairn finance MCP server (streamable HTTP at /mcp). All numbers come from SQL integer sums and
//! `finance-core`; the LLM only chooses tools and explains results.

mod report;

use std::{env, net::SocketAddr, time::Duration};

use anyhow::Context;
use rmcp::{
    handler::server::wrapper::Parameters,
    schemars, tool, tool_router,
    transport::streamable_http_server::{
        StreamableHttpServerConfig, StreamableHttpService, session::local::LocalSessionManager,
    },
};
use serde::{Deserialize, Serialize};
use sqlx::{PgPool, Row, postgres::PgPoolOptions};

#[derive(Clone)]
struct FinanceMcp {
    pool: PgPool,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct SpendingParams {
    /// Inclusive start date, YYYY-MM-DD
    start: String,
    /// Inclusive end date, YYYY-MM-DD
    end: String,
}

#[derive(Debug, Serialize)]
struct AccountRow {
    name: String,
    institution: String,
    kind: String,
    transactions: i64,
    net_cents: i64,
}

#[tool_router(server_handler)]
impl FinanceMcp {
    #[tool(description = "List all accounts with transaction counts and net cash flow in cents.")]
    async fn list_accounts(&self) -> Result<String, String> {
        let q = "SELECT a.name, a.institution, a.kind, COUNT(t.id)::bigint AS n, \
                 COALESCE(SUM(t.amount_cents),0)::bigint AS net \
                 FROM accounts a LEFT JOIN transactions t ON t.account_id = a.id \
                 GROUP BY a.id ORDER BY a.institution, a.name";
        match sqlx::query(q).fetch_all(&self.pool).await {
            Ok(rows) => {
                let out: Vec<AccountRow> = rows
                    .iter()
                    .map(|r| AccountRow {
                        name: r.get("name"),
                        institution: r.get("institution"),
                        kind: r.get("kind"),
                        transactions: r.get("n"),
                        net_cents: r.get("net"),
                    })
                    .collect();
                serde_json::to_string(&out).map_err(|e| e.to_string())
            }
            Err(e) => Err(e.to_string()),
        }
    }

    #[tool(
        description = "Total spending by category between two dates (inclusive). Amounts are exact; \
                       only net outflows count as spending. Uncategorized spend is reported explicitly."
    )]
    async fn spending_by_category(
        &self,
        Parameters(p): Parameters<SpendingParams>,
    ) -> Result<String, String> {
        report::validate_date(&p.start).and_then(|_| report::validate_date(&p.end))?;
        if p.start > p.end {
            return Err("start must be on or before end".to_string());
        }
        let q = "SELECT category, SUM(amount_cents)::bigint AS cents FROM transactions \
                 WHERE posted_on BETWEEN $1::date AND $2::date GROUP BY category";
        match sqlx::query(q)
            .bind(&p.start)
            .bind(&p.end)
            .fetch_all(&self.pool)
            .await
        {
            Ok(rows) => {
                let data = rows
                    .iter()
                    .map(|r| {
                        (
                            r.get::<Option<String>, _>("category"),
                            r.get::<i64, _>("cents"),
                        )
                    })
                    .collect();
                let rep = report::build_report(&p.start, &p.end, data);
                serde_json::to_string(&rep).map_err(|e| e.to_string())
            }
            Err(e) => Err(e.to_string()),
        }
    }
}

async fn connect() -> anyhow::Result<PgPool> {
    let url = env::var("DATABASE_URL").context("DATABASE_URL is not set")?;
    let mut last = None;
    for attempt in 1..=30 {
        match PgPoolOptions::new().max_connections(5).connect(&url).await {
            Ok(pool) => return Ok(pool),
            Err(e) => {
                tracing::warn!(attempt, error = %e, "database not ready, retrying");
                last = Some(e);
                tokio::time::sleep(Duration::from_secs(2)).await;
            }
        }
    }
    Err(last
        .map(anyhow::Error::from)
        .unwrap_or_else(|| anyhow::anyhow!("no attempts")))
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();
    let pool = connect().await?;
    let server = FinanceMcp { pool };

    // DNS-rebinding protection stays ON: only these Host headers are accepted. The defaults cover local
    // runs and the in-cluster Service names the gateway uses; override with ALLOWED_HOSTS (comma-separated).
    let allowed_hosts: Vec<String> = env::var("ALLOWED_HOSTS")
        .unwrap_or_else(|_| {
            "localhost,127.0.0.1,::1,finance-mcp,finance-mcp.cairn,finance-mcp.cairn.svc,\
             finance-mcp.cairn.svc.cluster.local"
                .into()
        })
        .split(',')
        .map(|h| h.trim().to_string())
        .filter(|h| !h.is_empty())
        .collect();
    tracing::info!(?allowed_hosts, "accepting Host headers");
    let service = StreamableHttpService::new(
        move || Ok(server.clone()),
        LocalSessionManager::default().into(),
        StreamableHttpServerConfig::default().with_allowed_hosts(allowed_hosts),
    );
    let app = axum::Router::new()
        .route("/healthz", axum::routing::get(|| async { "ok" }))
        .nest_service("/mcp", service);

    let addr: SocketAddr = env::var("LISTEN_ADDR")
        .unwrap_or_else(|_| "0.0.0.0:8080".into())
        .parse()?;
    tracing::info!(%addr, "finance-mcp listening");
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app)
        .with_graceful_shutdown(async {
            let _ = tokio::signal::ctrl_c().await;
        })
        .await?;
    Ok(())
}
