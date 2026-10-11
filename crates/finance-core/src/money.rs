//! Exact money arithmetic in integer minor units (cents). No floating point.

use std::fmt;
use std::ops::{Add, Neg, Sub};

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum MoneyError {
    #[error("invalid amount: {0:?}")]
    Invalid(String),
    #[error("amount out of range")]
    Overflow,
}

/// USD amount in cents. Negative values are outflows / liabilities.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Default)]
pub struct Money(i64);

impl Money {
    pub const ZERO: Money = Money(0);

    pub const fn from_cents(cents: i64) -> Self {
        Money(cents)
    }

    pub const fn cents(self) -> i64 {
        self.0
    }

    /// Parse strings like `"1234.56"`, `"-0.05"`, `"$1,234.5"`, `"(12.00)"` (accounting negative).
    pub fn parse(input: &str) -> Result<Self, MoneyError> {
        let err = || MoneyError::Invalid(input.to_string());
        let mut s = input.trim().replace([',', '$'], "");
        let mut negative = false;
        if s.starts_with('(') && s.ends_with(')') {
            negative = true;
            s = s[1..s.len() - 1].to_string();
        }
        if let Some(rest) = s.strip_prefix('-') {
            negative = !negative;
            s = rest.to_string();
        }
        let (whole, frac) = match s.split_once('.') {
            Some((w, f)) => (w, f),
            None => (s.as_str(), ""),
        };
        if whole.is_empty() && frac.is_empty() {
            return Err(err());
        }
        if frac.len() > 2
            || !whole.chars().all(|c| c.is_ascii_digit())
            || !frac.chars().all(|c| c.is_ascii_digit())
        {
            return Err(err());
        }
        let whole_v: i64 = if whole.is_empty() {
            0
        } else {
            whole.parse().map_err(|_| err())?
        };
        let frac_v: i64 = match frac.len() {
            0 => 0,
            1 => frac.parse::<i64>().map_err(|_| err())? * 10,
            _ => frac.parse().map_err(|_| err())?,
        };
        let cents = whole_v
            .checked_mul(100)
            .and_then(|c| c.checked_add(frac_v))
            .ok_or(MoneyError::Overflow)?;
        Ok(Money(if negative { -cents } else { cents }))
    }
}

impl Add for Money {
    type Output = Money;
    fn add(self, rhs: Money) -> Money {
        Money(self.0 + rhs.0)
    }
}

impl Sub for Money {
    type Output = Money;
    fn sub(self, rhs: Money) -> Money {
        Money(self.0 - rhs.0)
    }
}

impl Neg for Money {
    type Output = Money;
    fn neg(self) -> Money {
        Money(-self.0)
    }
}

impl fmt::Display for Money {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let sign = if self.0 < 0 { "-" } else { "" };
        let abs = self.0.unsigned_abs();
        write!(f, "{sign}${}.{:02}", abs / 100, abs % 100)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_common_formats() {
        assert_eq!(Money::parse("1234.56").unwrap().cents(), 123_456);
        assert_eq!(Money::parse("$1,234.5").unwrap().cents(), 123_450);
        assert_eq!(Money::parse("-0.05").unwrap().cents(), -5);
        assert_eq!(Money::parse("(12.00)").unwrap().cents(), -1_200);
        assert_eq!(Money::parse("7").unwrap().cents(), 700);
    }

    #[test]
    fn rejects_garbage_and_sub_cent_precision() {
        assert!(Money::parse("").is_err());
        assert!(Money::parse("abc").is_err());
        assert!(Money::parse("1.234").is_err());
        assert!(Money::parse("1.2.3").is_err());
    }

    #[test]
    fn arithmetic_is_exact() {
        // 0.10 + 0.20 must equal 0.30 exactly (the classic float failure)
        let sum = Money::parse("0.10").unwrap() + Money::parse("0.20").unwrap();
        assert_eq!(sum, Money::parse("0.30").unwrap());
        assert_eq!((-sum).to_string(), "-$0.30");
    }
}
