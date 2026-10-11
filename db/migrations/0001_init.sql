-- Cairn core schema. Money is stored as integer cents (bigint); negative = outflow / liability.

CREATE TABLE accounts (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name        text NOT NULL,
    institution text NOT NULL,
    kind        text NOT NULL CHECK (kind IN
                  ('checking','savings','credit_card','brokerage','retirement','loan','mortgage','other')),
    currency    text NOT NULL DEFAULT 'USD',
    created_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (institution, name)
);

CREATE TABLE categories (
    name text PRIMARY KEY
);

CREATE TABLE transactions (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id   uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    posted_on    date NOT NULL,
    description  text NOT NULL,
    amount_cents bigint NOT NULL,
    category     text REFERENCES categories(name),
    -- dedupe key for re-imported statements: hash of (account, date, amount, normalized description, ordinal)
    source_hash  text NOT NULL UNIQUE,
    created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX transactions_account_date_idx ON transactions (account_id, posted_on);
CREATE INDEX transactions_category_date_idx ON transactions (category, posted_on);
