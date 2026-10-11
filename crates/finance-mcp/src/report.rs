//! Pure report logic (no I/O) so it is unit-tested without a database.

use finance_core::Money;
use serde::Serialize;

#[derive(Debug, Serialize, PartialEq, Eq)]
pub struct CategorySpend {
    pub category: String,
    pub spent_cents: i64,
    pub spent: String,
}

#[derive(Debug, Serialize, PartialEq, Eq)]
pub struct SpendingReport {
    pub start: String,
    pub end: String,
    pub total_spent_cents: i64,
    pub total_spent: String,
    pub categories: Vec<CategorySpend>,
}

/// Validate a `YYYY-MM-DD` date string (calendar-aware, no external crates).
pub fn validate_date(s: &str) -> Result<(), String> {
    let bad = || format!("invalid date {s:?}; expected YYYY-MM-DD");
    let b = s.as_bytes();
    if b.len() != 10 || b[4] != b'-' || b[7] != b'-' {
        return Err(bad());
    }
    let num = |r: std::ops::Range<usize>| s[r].parse::<u32>().map_err(|_| bad());
    let (y, m, d) = (num(0..4)?, num(5..7)?, num(8..10)?);
    let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
    let dim = match m {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 => {
            if leap {
                29
            } else {
                28
            }
        }
        _ => return Err(bad()),
    };
    if d == 0 || d > dim || y < 1900 {
        return Err(bad());
    }
    Ok(())
}

/// `rows` are (category, signed cents summed over the period). Only net outflows count as spending;
/// results are sorted by spend descending, ties by name. Uncategorized rows are labelled explicitly.
pub fn build_report(start: &str, end: &str, rows: Vec<(Option<String>, i64)>) -> SpendingReport {
    let mut categories: Vec<CategorySpend> = rows
        .into_iter()
        .filter(|(_, cents)| *cents < 0)
        .map(|(cat, cents)| CategorySpend {
            category: cat.unwrap_or_else(|| "Uncategorized".to_string()),
            spent_cents: -cents,
            spent: (-Money::from_cents(cents)).to_string(),
        })
        .collect();
    categories.sort_by(|a, b| {
        b.spent_cents
            .cmp(&a.spent_cents)
            .then(a.category.cmp(&b.category))
    });
    let total: i64 = categories.iter().map(|c| c.spent_cents).sum();
    SpendingReport {
        start: start.to_string(),
        end: end.to_string(),
        total_spent_cents: total,
        total_spent: Money::from_cents(total).to_string(),
        categories,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dates_are_validated() {
        assert!(validate_date("2026-09-30").is_ok());
        assert!(validate_date("2024-02-29").is_ok());
        assert!(validate_date("2026-02-29").is_err());
        assert!(validate_date("2026-13-01").is_err());
        assert!(validate_date("2026-9-1").is_err());
        assert!(validate_date("'; DROP TABLE x;--").is_err());
    }

    #[test]
    fn report_sums_exactly_and_sorts() {
        let rows = vec![
            (Some("Groceries".into()), -18_734 - 22_015),
            (Some("Dining".into()), -4_850),
            (None, -3_333),
            (Some("Income".into()), 650_000), // inflow: not spending
        ];
        let r = build_report("2026-09-01", "2026-09-30", rows);
        assert_eq!(r.categories[0].category, "Groceries");
        assert_eq!(r.categories[0].spent, "$407.49");
        assert_eq!(r.categories[2].category, "Uncategorized");
        assert_eq!(r.total_spent_cents, 40_749 + 4_850 + 3_333);
        assert_eq!(r.total_spent, "$489.32");
        assert!(r.categories.iter().all(|c| c.category != "Income"));
    }
}
