-- SYNTHETIC demo data only. Invented institutions/merchants/amounts; safe to commit.
INSERT INTO categories(name) VALUES
  ('Groceries'),('Dining'),('Utilities'),('Housing'),('Transport'),('Income'),('Subscriptions')
ON CONFLICT DO NOTHING;

INSERT INTO accounts(name, institution, kind) VALUES
  ('Everyday Checking','Example Bank','checking'),
  ('Rewards Card','Example Card Co','credit_card')
ON CONFLICT DO NOTHING;

WITH a AS (SELECT id, name FROM accounts)
INSERT INTO transactions(account_id, posted_on, description, amount_cents, category, source_hash)
SELECT a.id, t.d::date, t.descr, t.cents, t.cat, 'synthetic-' || t.n
FROM (VALUES
  (1,'Everyday Checking','2026-09-01','PAYROLL EXAMPLE CORP', 650000,'Income'),
  (2,'Everyday Checking','2026-09-02','MORTGAGE PAYMENT',     -240000,'Housing'),
  (3,'Everyday Checking','2026-09-05','ELECTRIC UTILITY',      -14250,'Utilities'),
  (4,'Rewards Card','2026-09-03','FRESH MARKET #12',           -18734,'Groceries'),
  (5,'Rewards Card','2026-09-09','FRESH MARKET #12',           -22015,'Groceries'),
  (6,'Rewards Card','2026-09-11','PIZZA PLACE',                 -4850,'Dining'),
  (7,'Rewards Card','2026-09-14','STREAMING SERVICE',           -1599,'Subscriptions'),
  (8,'Rewards Card','2026-09-18','GAS STATION',                 -5120,'Transport'),
  (9,'Rewards Card','2026-09-21','MYSTERY MERCHANT 4411',       -3333,NULL)
) AS t(n, acct, d, descr, cents, cat)
JOIN a ON a.name = t.acct
ON CONFLICT (source_hash) DO NOTHING;
