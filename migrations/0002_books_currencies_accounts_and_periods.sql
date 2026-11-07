DO $verify_btree_gist$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_extension AS extension
        JOIN pg_catalog.pg_namespace AS extension_schema
            ON extension_schema.oid = extension.extnamespace
        WHERE extension.extname = 'btree_gist'
          AND extension_schema.nspname = 'jw_support'
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'BTREE_GIST_SCHEMA_INVALID';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_opclass AS operator_class
        JOIN pg_catalog.pg_namespace AS operator_schema
            ON operator_schema.oid = operator_class.opcnamespace
        JOIN pg_catalog.pg_am AS access_method
            ON access_method.oid = operator_class.opcmethod
        JOIN pg_catalog.pg_depend AS extension_dependency
            ON extension_dependency.classid = 'pg_catalog.pg_opclass'::regclass
           AND extension_dependency.objid = operator_class.oid
           AND extension_dependency.refclassid = 'pg_catalog.pg_extension'::regclass
           AND extension_dependency.deptype = 'e'
        JOIN pg_catalog.pg_extension AS extension
            ON extension.oid = extension_dependency.refobjid
        WHERE operator_schema.nspname = 'jw_support'
          AND operator_class.opcname = 'gist_uuid_ops'
          AND operator_class.opcintype = 'uuid'::regtype
          AND operator_class.opcdefault
          AND access_method.amname = 'gist'
          AND extension.extname = 'btree_gist'
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'BTREE_GIST_UUID_OPERATOR_CLASS_INVALID';
    END IF;
END
$verify_btree_gist$;

CREATE TABLE jw.books (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES jw.organizations (id) ON DELETE RESTRICT,
    code text NOT NULL,
    name text NOT NULL,
    state text NOT NULL,
    accounting_timezone text NOT NULL DEFAULT 'UTC',
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT books_code_shape CHECK (
        char_length(code) BETWEEN 1 AND 64
        AND code COLLATE "C" ~ '^[A-Z0-9][A-Z0-9_-]*$'
    ),
    CONSTRAINT books_name_length CHECK (char_length(name) BETWEEN 1 AND 160),
    CONSTRAINT books_name_safe CHECK (name !~ '[[:cntrl:]]'),
    CONSTRAINT books_state CHECK (state IN ('provisioning', 'active', 'restricted', 'closed')),
    CONSTRAINT books_accounting_timezone_supported CHECK (accounting_timezone = 'UTC'),
    CONSTRAINT books_version_positive CHECK (version > 0),
    CONSTRAINT books_id_organization_unique UNIQUE (id, organization_id),
    CONSTRAINT books_organization_code_unique UNIQUE (organization_id, code)
);
CREATE INDEX books_organization_state_idx ON jw.books (organization_id, state, id);

CREATE TABLE jw.book_financial_state (
    book_id uuid PRIMARY KEY,
    organization_id uuid NOT NULL,
    journal_sequence bigint NOT NULL DEFAULT 0,
    state_sequence bigint NOT NULL DEFAULT 0,
    projection_generation bigint NOT NULL DEFAULT 1,
    projection_status text NOT NULL DEFAULT 'current',
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT book_financial_state_sequences_nonnegative CHECK (
        journal_sequence >= 0 AND state_sequence >= 0
    ),
    CONSTRAINT book_financial_state_generation_positive CHECK (projection_generation > 0),
    CONSTRAINT book_financial_state_projection_status CHECK (
        projection_status IN ('current', 'rebuilding', 'divergent', 'unavailable')
    ),
    CONSTRAINT book_financial_state_scope_fk
        FOREIGN KEY (book_id, organization_id)
        REFERENCES jw.books (id, organization_id) ON DELETE RESTRICT
);

CREATE TABLE jw.book_evidence_state (
    book_id uuid PRIMARY KEY REFERENCES jw.books (id) ON DELETE RESTRICT,
    evidence_epoch bigint NOT NULL DEFAULT 0,
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT book_evidence_state_epoch_nonnegative CHECK (evidence_epoch >= 0),
    CONSTRAINT book_evidence_state_version_positive CHECK (version > 0)
);

CREATE TABLE jw.currency_definitions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code text NOT NULL,
    definition_version integer NOT NULL,
    exponent smallint NOT NULL,
    display_name text NOT NULL,
    state text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    retired_at timestamptz,
    CONSTRAINT currency_definitions_code_shape CHECK (code COLLATE "C" ~ '^[A-Z]{3}$'),
    CONSTRAINT currency_definitions_version_positive CHECK (definition_version > 0),
    CONSTRAINT currency_definitions_exponent_range CHECK (exponent BETWEEN 0 AND 6),
    CONSTRAINT currency_definitions_display_name_length CHECK (
        char_length(display_name) BETWEEN 1 AND 120
    ),
    CONSTRAINT currency_definitions_display_name_safe CHECK (display_name !~ '[[:cntrl:]]'),
    CONSTRAINT currency_definitions_state CHECK (state IN ('draft', 'active', 'retired')),
    CONSTRAINT currency_definitions_retired_time CHECK (
        (state = 'retired' AND retired_at IS NOT NULL)
        OR (state <> 'retired' AND retired_at IS NULL)
    ),
    CONSTRAINT currency_definitions_code_version_unique UNIQUE (code, definition_version),
    CONSTRAINT currency_definitions_id_code_version_unique UNIQUE (id, code, definition_version)
);

CREATE TABLE jw.currency_definition_defaults (
    code text PRIMARY KEY,
    definition_version integer NOT NULL,
    CONSTRAINT currency_definition_defaults_code_shape CHECK (code COLLATE "C" ~ '^[A-Z]{3}$'),
    CONSTRAINT currency_definition_defaults_definition_fk
        FOREIGN KEY (code, definition_version)
        REFERENCES jw.currency_definitions (code, definition_version) ON DELETE RESTRICT
);

-- Curated ledger examples exercise zero-, two-, and three-decimal units; provider support is separate.
INSERT INTO jw.currency_definitions (code, definition_version, exponent, display_name, state)
VALUES
    ('USD', 1, 2, 'US dollar', 'active'),
    ('EUR', 1, 2, 'Euro', 'active'),
    ('GBP', 1, 2, 'Pound sterling', 'active'),
    ('JPY', 1, 0, 'Japanese yen', 'active'),
    ('KWD', 1, 3, 'Kuwaiti dinar', 'active');

INSERT INTO jw.currency_definition_defaults (code, definition_version)
VALUES ('USD', 1), ('EUR', 1), ('GBP', 1), ('JPY', 1), ('KWD', 1);

CREATE TABLE jw.account_templates (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES jw.organizations (id) ON DELETE RESTRICT,
    name text NOT NULL,
    template_version integer NOT NULL,
    classification text NOT NULL,
    normal_side text NOT NULL,
    spend_policy text NOT NULL,
    state text NOT NULL,
    payload_sha256 bytea NOT NULL,
    created_by uuid NOT NULL,
    creator_kind text GENERATED ALWAYS AS ('human'::text) STORED,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT account_templates_name_length CHECK (char_length(name) BETWEEN 1 AND 120),
    CONSTRAINT account_templates_name_safe CHECK (name !~ '[[:cntrl:]]'),
    CONSTRAINT account_templates_version_positive CHECK (template_version > 0),
    CONSTRAINT account_templates_classification CHECK (
        classification IN ('asset', 'liability', 'equity', 'income', 'expense')
    ),
    CONSTRAINT account_templates_normal_side CHECK (normal_side IN ('debit', 'credit')),
    CONSTRAINT account_templates_spend_policy CHECK (
        spend_policy IN ('unrestricted_accounting', 'protected_customer_liability')
    ),
    CONSTRAINT account_templates_protected_liability CHECK (
        spend_policy <> 'protected_customer_liability'
        OR (classification = 'liability' AND normal_side = 'credit')
    ),
    CONSTRAINT account_templates_state CHECK (state IN ('draft', 'active', 'retired')),
    CONSTRAINT account_templates_hash_size CHECK (octet_length(payload_sha256) = 32),
    CONSTRAINT account_templates_id_version_organization_unique
        UNIQUE (id, template_version, organization_id),
    CONSTRAINT account_templates_id_version_organization_hash_unique
        UNIQUE (id, template_version, organization_id, payload_sha256),
    CONSTRAINT account_templates_id_version_accounting_identity_unique
        UNIQUE (id, template_version, organization_id, classification, normal_side, spend_policy),
    CONSTRAINT account_templates_creator_human_fk
        FOREIGN KEY (created_by, creator_kind)
        REFERENCES jw.principals (id, kind) ON DELETE RESTRICT
);
CREATE INDEX account_templates_organization_state_idx
    ON jw.account_templates (organization_id, state, name, id);

CREATE TABLE jw.account_template_currencies (
    template_id uuid NOT NULL,
    template_version integer NOT NULL,
    organization_id uuid NOT NULL,
    currency_definition_id uuid NOT NULL REFERENCES jw.currency_definitions (id) ON DELETE RESTRICT,
    CONSTRAINT account_template_currencies_pk
        PRIMARY KEY (template_id, template_version, currency_definition_id),
    CONSTRAINT account_template_currencies_template_fk
        FOREIGN KEY (template_id, template_version, organization_id)
        REFERENCES jw.account_templates (id, template_version, organization_id) ON DELETE RESTRICT,
    CONSTRAINT account_template_currencies_scope_unique
        UNIQUE (template_id, template_version, organization_id, currency_definition_id)
);

CREATE TABLE jw.accounts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    book_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    currency_definition_id uuid NOT NULL,
    template_id uuid NOT NULL,
    template_version integer NOT NULL,
    classification text NOT NULL,
    normal_side text NOT NULL,
    spend_policy text NOT NULL,
    state text NOT NULL DEFAULT 'pending',
    created_by uuid NOT NULL,
    creator_kind text GENERATED ALWAYS AS ('human'::text) STORED,
    activated_by uuid,
    activator_kind text GENERATED ALWAYS AS ('human'::text) STORED,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    closed_at timestamptz,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT accounts_code_shape CHECK (
        char_length(code) BETWEEN 1 AND 64
        AND code COLLATE "C" ~ '^[A-Z0-9][A-Z0-9_-]*$'
    ),
    CONSTRAINT accounts_name_length CHECK (char_length(name) BETWEEN 1 AND 160),
    CONSTRAINT accounts_name_safe CHECK (name !~ '[[:cntrl:]]'),
    CONSTRAINT accounts_template_version_positive CHECK (template_version > 0),
    CONSTRAINT accounts_classification CHECK (
        classification IN ('asset', 'liability', 'equity', 'income', 'expense')
    ),
    CONSTRAINT accounts_normal_side CHECK (normal_side IN ('debit', 'credit')),
    CONSTRAINT accounts_spend_policy CHECK (
        spend_policy IN ('unrestricted_accounting', 'protected_customer_liability')
    ),
    CONSTRAINT accounts_protected_liability CHECK (
        spend_policy <> 'protected_customer_liability'
        OR (classification = 'liability' AND normal_side = 'credit')
    ),
    CONSTRAINT accounts_state CHECK (state IN ('pending', 'active', 'frozen', 'closed')),
    CONSTRAINT accounts_lifecycle_metadata CHECK (
        (state = 'pending' AND activated_by IS NULL AND closed_at IS NULL)
        OR (state IN ('active', 'frozen') AND activated_by IS NOT NULL AND closed_at IS NULL)
        OR (state = 'closed' AND activated_by IS NOT NULL AND closed_at IS NOT NULL)
    ),
    CONSTRAINT accounts_version_positive CHECK (version > 0),
    CONSTRAINT accounts_scope_fk
        FOREIGN KEY (book_id, organization_id)
        REFERENCES jw.books (id, organization_id) ON DELETE RESTRICT,
    CONSTRAINT accounts_currency_fk
        FOREIGN KEY (currency_definition_id) REFERENCES jw.currency_definitions (id) ON DELETE RESTRICT,
    CONSTRAINT accounts_template_definition_fk
        FOREIGN KEY (template_id, template_version, organization_id)
        REFERENCES jw.account_templates (id, template_version, organization_id) ON DELETE RESTRICT,
    CONSTRAINT accounts_template_accounting_identity_fk
        FOREIGN KEY (
            template_id, template_version, organization_id,
            classification, normal_side, spend_policy
        )
        REFERENCES jw.account_templates (
            id, template_version, organization_id,
            classification, normal_side, spend_policy
        ) ON DELETE RESTRICT,
    CONSTRAINT accounts_template_currency_fk
        FOREIGN KEY (template_id, template_version, organization_id, currency_definition_id)
        REFERENCES jw.account_template_currencies
            (template_id, template_version, organization_id, currency_definition_id)
            ON DELETE RESTRICT,
    CONSTRAINT accounts_creator_human_fk
        FOREIGN KEY (created_by, creator_kind)
        REFERENCES jw.principals (id, kind) ON DELETE RESTRICT,
    CONSTRAINT accounts_activator_human_fk
        FOREIGN KEY (activated_by, activator_kind)
        REFERENCES jw.principals (id, kind) ON DELETE RESTRICT,
    CONSTRAINT accounts_book_code_unique UNIQUE (book_id, code),
    CONSTRAINT accounts_id_book_currency_unique UNIQUE (id, book_id, currency_definition_id)
);
CREATE INDEX accounts_book_state_code_idx ON jw.accounts (book_id, state, code);

CREATE TABLE jw.account_financial_state (
    account_id uuid PRIMARY KEY,
    book_id uuid NOT NULL,
    currency_definition_id uuid NOT NULL,
    debit_total numeric(38, 0) NOT NULL DEFAULT 0,
    credit_total numeric(38, 0) NOT NULL DEFAULT 0,
    active_reserved_total numeric(38, 0) NOT NULL DEFAULT 0,
    restriction_amount numeric(38, 0) NOT NULL DEFAULT 0,
    last_journal_sequence bigint NOT NULL DEFAULT 0,
    last_state_sequence bigint NOT NULL DEFAULT 0,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT account_financial_state_totals_nonnegative CHECK (
        debit_total >= 0
        AND credit_total >= 0
        AND active_reserved_total >= 0
        AND restriction_amount >= 0
    ),
    CONSTRAINT account_financial_state_sequences_nonnegative CHECK (
        last_journal_sequence >= 0 AND last_state_sequence >= 0
    ),
    CONSTRAINT account_financial_state_version_positive CHECK (version > 0),
    CONSTRAINT account_financial_state_account_scope_fk
        FOREIGN KEY (account_id, book_id, currency_definition_id)
        REFERENCES jw.accounts (id, book_id, currency_definition_id) ON DELETE RESTRICT
);

CREATE TABLE jw.accounting_periods (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    book_id uuid NOT NULL REFERENCES jw.books (id) ON DELETE RESTRICT,
    starts_on date NOT NULL,
    ends_before date NOT NULL,
    state text NOT NULL DEFAULT 'open',
    closing_version bigint NOT NULL DEFAULT 1,
    closed_at timestamptz,
    closed_by uuid,
    closer_kind text GENERATED ALWAYS AS ('human'::text) STORED,
    close_snapshot_id uuid,
    CONSTRAINT accounting_periods_date_range CHECK (starts_on < ends_before),
    CONSTRAINT accounting_periods_state CHECK (state IN ('open', 'closing', 'closed')),
    CONSTRAINT accounting_periods_closing_version_positive CHECK (closing_version > 0),
    CONSTRAINT accounting_periods_close_metadata CHECK (
        (state = 'closed' AND closed_at IS NOT NULL AND closed_by IS NOT NULL AND close_snapshot_id IS NOT NULL)
        OR (state <> 'closed' AND closed_at IS NULL AND closed_by IS NULL AND close_snapshot_id IS NULL)
    ),
    CONSTRAINT accounting_periods_id_book_unique UNIQUE (id, book_id),
    CONSTRAINT accounting_periods_closer_human_fk
        FOREIGN KEY (closed_by, closer_kind)
        REFERENCES jw.principals (id, kind) ON DELETE RESTRICT,
    CONSTRAINT accounting_periods_no_overlap EXCLUDE USING gist (
        book_id jw_support.gist_uuid_ops WITH =,
        daterange(starts_on, ends_before, '[)') WITH &&
    )
);
CREATE INDEX accounting_periods_book_state_start_idx
    ON jw.accounting_periods (book_id, state, starts_on);

CREATE TABLE jw.book_role_assignments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    book_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    membership_id uuid NOT NULL,
    role text NOT NULL,
    state text NOT NULL,
    granted_by uuid NOT NULL,
    grantor_kind text GENERATED ALWAYS AS ('human'::text) STORED,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    expires_at timestamptz,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT book_role_assignments_role CHECK (
        role IN ('finance_operator', 'finance_reviewer', 'integration_operator', 'auditor')
    ),
    CONSTRAINT book_role_assignments_state CHECK (state IN ('active', 'revoked')),
    CONSTRAINT book_role_assignments_expiry CHECK (expires_at IS NULL OR expires_at > created_at),
    CONSTRAINT book_role_assignments_version_positive CHECK (version > 0),
    CONSTRAINT book_role_assignments_book_scope_fk
        FOREIGN KEY (book_id, organization_id)
        REFERENCES jw.books (id, organization_id) ON DELETE RESTRICT,
    CONSTRAINT book_role_assignments_membership_scope_fk
        FOREIGN KEY (membership_id, organization_id)
        REFERENCES jw.organization_memberships (id, organization_id) ON DELETE RESTRICT,
    CONSTRAINT book_role_assignments_grantor_human_fk
        FOREIGN KEY (granted_by, grantor_kind)
        REFERENCES jw.principals (id, kind) ON DELETE RESTRICT
);
CREATE UNIQUE INDEX book_role_assignments_active_role_uq
    ON jw.book_role_assignments (book_id, membership_id, role)
    WHERE state = 'active';
CREATE INDEX book_role_assignments_scope_state_idx
    ON jw.book_role_assignments (organization_id, book_id, state, membership_id);

CREATE TABLE jw.book_setup_candidates (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    book_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    candidate_kind text NOT NULL,
    manifest_version bigint NOT NULL,
    manifest_payload jsonb NOT NULL,
    payload_sha256 bytea NOT NULL,
    created_by uuid NOT NULL,
    creator_kind text GENERATED ALWAYS AS ('human'::text) STORED,
    state text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT book_setup_candidates_kind CHECK (candidate_kind IN ('setup', 'book_close')),
    CONSTRAINT book_setup_candidates_manifest_version_positive CHECK (manifest_version > 0),
    CONSTRAINT book_setup_candidates_payload_object CHECK (
        jsonb_typeof(manifest_payload) = 'object'
        AND octet_length(manifest_payload::text) <= 1048576
    ),
    CONSTRAINT book_setup_candidates_hash_size CHECK (octet_length(payload_sha256) = 32),
    CONSTRAINT book_setup_candidates_state CHECK (
        state IN ('draft', 'validated', 'approved', 'activated')
    ),
    CONSTRAINT book_setup_candidates_version_positive CHECK (version > 0),
    CONSTRAINT book_setup_candidates_book_scope_fk
        FOREIGN KEY (book_id, organization_id)
        REFERENCES jw.books (id, organization_id) ON DELETE RESTRICT,
    CONSTRAINT book_setup_candidates_creator_human_fk
        FOREIGN KEY (created_by, creator_kind)
        REFERENCES jw.principals (id, kind) ON DELETE RESTRICT,
    CONSTRAINT book_setup_candidates_id_book_unique UNIQUE (id, book_id),
    CONSTRAINT book_setup_candidates_id_book_hash_unique UNIQUE (id, book_id, payload_sha256),
    CONSTRAINT book_setup_candidates_book_kind_manifest_unique
        UNIQUE (book_id, candidate_kind, manifest_version)
);
CREATE INDEX book_setup_candidates_state_idx
    ON jw.book_setup_candidates (book_id, candidate_kind, state, created_at DESC);

CREATE TABLE jw.book_setup_approvals (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_id uuid NOT NULL,
    book_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    payload_sha256 bytea NOT NULL,
    reviewer_principal_id uuid NOT NULL,
    reviewer_kind text GENERATED ALWAYS AS ('human'::text) STORED,
    state text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    expires_at timestamptz NOT NULL,
    reviewer_membership_version bigint NOT NULL,
    CONSTRAINT book_setup_approvals_hash_size CHECK (octet_length(payload_sha256) = 32),
    CONSTRAINT book_setup_approvals_state CHECK (state IN ('approved', 'revoked')),
    CONSTRAINT book_setup_approvals_expiry CHECK (
        expires_at > created_at
        AND expires_at <= created_at + interval '15 minutes'
    ),
    CONSTRAINT book_setup_approvals_membership_version_positive CHECK (
        reviewer_membership_version > 0
    ),
    CONSTRAINT book_setup_approvals_candidate_hash_fk
        FOREIGN KEY (candidate_id, book_id, payload_sha256)
        REFERENCES jw.book_setup_candidates (id, book_id, payload_sha256) ON DELETE RESTRICT,
    CONSTRAINT book_setup_approvals_book_scope_fk
        FOREIGN KEY (book_id, organization_id)
        REFERENCES jw.books (id, organization_id) ON DELETE RESTRICT,
    CONSTRAINT book_setup_approvals_reviewer_membership_fk
        FOREIGN KEY (organization_id, reviewer_principal_id)
        REFERENCES jw.organization_memberships (organization_id, principal_id) ON DELETE RESTRICT,
    CONSTRAINT book_setup_approvals_reviewer_human_fk
        FOREIGN KEY (reviewer_principal_id, reviewer_kind)
        REFERENCES jw.principals (id, kind) ON DELETE RESTRICT,
    CONSTRAINT book_setup_approvals_reviewer_candidate_unique
        UNIQUE (candidate_id, reviewer_principal_id)
);

CREATE TABLE jw.book_account_template_approvals (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    book_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    account_template_id uuid NOT NULL,
    template_version integer NOT NULL,
    payload_sha256 bytea NOT NULL,
    reviewer_principal_id uuid NOT NULL,
    reviewer_kind text GENERATED ALWAYS AS ('human'::text) STORED,
    reviewer_membership_version bigint NOT NULL,
    state text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT book_account_template_approvals_template_version_positive CHECK (
        template_version > 0
    ),
    CONSTRAINT book_account_template_approvals_hash_size CHECK (octet_length(payload_sha256) = 32),
    CONSTRAINT book_account_template_approvals_membership_version_positive CHECK (
        reviewer_membership_version > 0
    ),
    CONSTRAINT book_account_template_approvals_state CHECK (state IN ('approved', 'revoked')),
    CONSTRAINT book_account_template_approvals_version_positive CHECK (version > 0),
    CONSTRAINT book_account_template_approvals_book_scope_fk
        FOREIGN KEY (book_id, organization_id)
        REFERENCES jw.books (id, organization_id) ON DELETE RESTRICT,
    CONSTRAINT book_account_template_approvals_template_definition_fk
        FOREIGN KEY (account_template_id, template_version, organization_id, payload_sha256)
        REFERENCES jw.account_templates
            (id, template_version, organization_id, payload_sha256) ON DELETE RESTRICT,
    CONSTRAINT book_account_template_approvals_reviewer_membership_fk
        FOREIGN KEY (organization_id, reviewer_principal_id)
        REFERENCES jw.organization_memberships (organization_id, principal_id) ON DELETE RESTRICT,
    CONSTRAINT book_account_template_approvals_reviewer_human_fk
        FOREIGN KEY (reviewer_principal_id, reviewer_kind)
        REFERENCES jw.principals (id, kind) ON DELETE RESTRICT,
    CONSTRAINT book_account_template_approvals_reviewer_version_unique
        UNIQUE (book_id, account_template_id, template_version, reviewer_principal_id)
);

CREATE TABLE jw.book_lifecycle_restrictions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    book_id uuid NOT NULL REFERENCES jw.books (id) ON DELETE RESTRICT,
    source text NOT NULL,
    state text NOT NULL,
    reason_code text NOT NULL,
    created_by uuid NOT NULL,
    creator_kind text GENERATED ALWAYS AS ('human'::text) STORED,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    released_by uuid,
    releaser_kind text GENERATED ALWAYS AS ('human'::text) STORED,
    released_at timestamptz,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT book_lifecycle_restrictions_source CHECK (
        source IN ('owner_governance', 'finance_security')
    ),
    CONSTRAINT book_lifecycle_restrictions_state CHECK (state IN ('active', 'released')),
    CONSTRAINT book_lifecycle_restrictions_reason_shape CHECK (
        char_length(reason_code) BETWEEN 1 AND 64
        AND reason_code ~ '^[a-z][a-z0-9_.-]*$'
    ),
    CONSTRAINT book_lifecycle_restrictions_release_shape CHECK (
        (state = 'active' AND released_by IS NULL AND released_at IS NULL)
        OR (state = 'released' AND released_by IS NOT NULL AND released_at IS NOT NULL)
    ),
    CONSTRAINT book_lifecycle_restrictions_release_after_create CHECK (
        released_at IS NULL OR released_at >= created_at
    ),
    CONSTRAINT book_lifecycle_restrictions_version_positive CHECK (version > 0),
    CONSTRAINT book_lifecycle_restrictions_creator_human_fk
        FOREIGN KEY (created_by, creator_kind)
        REFERENCES jw.principals (id, kind) ON DELETE RESTRICT,
    CONSTRAINT book_lifecycle_restrictions_releaser_human_fk
        FOREIGN KEY (released_by, releaser_kind)
        REFERENCES jw.principals (id, kind) ON DELETE RESTRICT
);
CREATE UNIQUE INDEX book_lifecycle_restrictions_active_source_uq
    ON jw.book_lifecycle_restrictions (book_id, source)
    WHERE state = 'active';

CREATE FUNCTION jw_private.keep_book_identity_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $book_identity$
BEGIN
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
       OR NEW.code IS DISTINCT FROM OLD.code
       OR NEW.accounting_timezone IS DISTINCT FROM OLD.accounting_timezone THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'BOOK_IDENTITY_IMMUTABLE';
    END IF;
    RETURN NEW;
END
$book_identity$;
REVOKE ALL ON FUNCTION jw_private.keep_book_identity_v1() FROM PUBLIC;

CREATE TRIGGER books_identity_immutable
BEFORE UPDATE ON jw.books
FOR EACH ROW EXECUTE FUNCTION jw_private.keep_book_identity_v1();

CREATE FUNCTION jw_private.keep_currency_definition_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $currency_definition$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CURRENCY_DEFINITION_RETAINED';
    END IF;

    IF OLD.state <> 'draft' THEN
        IF NEW.id IS DISTINCT FROM OLD.id
           OR NEW.code IS DISTINCT FROM OLD.code
           OR NEW.definition_version IS DISTINCT FROM OLD.definition_version
           OR NEW.exponent IS DISTINCT FROM OLD.exponent
           OR NEW.display_name IS DISTINCT FROM OLD.display_name
           OR NEW.created_at IS DISTINCT FROM OLD.created_at
           OR (OLD.state = 'retired' AND NEW.state <> 'retired')
           OR (OLD.state = 'active' AND NEW.state NOT IN ('active', 'retired')) THEN
            RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CURRENCY_DEFINITION_IMMUTABLE';
        END IF;

        IF OLD.state = 'active'
           AND NEW.state = 'retired'
           AND EXISTS (
               SELECT 1
               FROM jw.currency_definition_defaults AS default_pointer
               WHERE default_pointer.code = OLD.code
                 AND default_pointer.definition_version = OLD.definition_version
           ) THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'CURRENCY_DEFAULT_MUST_MOVE_FIRST';
        END IF;
    END IF;

    RETURN NEW;
END
$currency_definition$;
REVOKE ALL ON FUNCTION jw_private.keep_currency_definition_v1() FROM PUBLIC;

CREATE TRIGGER currency_definitions_immutable_meaning
BEFORE UPDATE OR DELETE ON jw.currency_definitions
FOR EACH ROW EXECUTE FUNCTION jw_private.keep_currency_definition_v1();

CREATE FUNCTION jw_private.require_active_currency_default_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $currency_default$
DECLARE
    definition_state text;
BEGIN
    SELECT definition.state
    INTO definition_state
    FROM jw.currency_definitions AS definition
    WHERE definition.code = NEW.code
      AND definition.definition_version = NEW.definition_version;

    IF definition_state IS DISTINCT FROM 'active' THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'CURRENCY_DEFAULT_NOT_ACTIVE';
    END IF;

    RETURN NEW;
END
$currency_default$;
REVOKE ALL ON FUNCTION jw_private.require_active_currency_default_v1() FROM PUBLIC;

CREATE TRIGGER currency_defaults_require_active_definition
BEFORE INSERT OR UPDATE ON jw.currency_definition_defaults
FOR EACH ROW EXECUTE FUNCTION jw_private.require_active_currency_default_v1();

CREATE FUNCTION jw_private.keep_active_account_template_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $account_template$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.state <> 'draft' THEN
            RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ACCOUNT_TEMPLATE_RETAINED';
        END IF;
        RETURN OLD;
    END IF;

    IF OLD.state IN ('active', 'retired') THEN
        IF NEW.id IS DISTINCT FROM OLD.id
           OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
           OR NEW.name IS DISTINCT FROM OLD.name
           OR NEW.template_version IS DISTINCT FROM OLD.template_version
           OR NEW.classification IS DISTINCT FROM OLD.classification
           OR NEW.normal_side IS DISTINCT FROM OLD.normal_side
           OR NEW.spend_policy IS DISTINCT FROM OLD.spend_policy
           OR NEW.payload_sha256 IS DISTINCT FROM OLD.payload_sha256
           OR NEW.created_by IS DISTINCT FROM OLD.created_by
           OR NEW.created_at IS DISTINCT FROM OLD.created_at
           OR (OLD.state = 'retired' AND NEW.state <> 'retired')
           OR (OLD.state = 'active' AND NEW.state NOT IN ('active', 'retired')) THEN
            RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ACCOUNT_TEMPLATE_IMMUTABLE';
        END IF;
    END IF;

    RETURN NEW;
END
$account_template$;
REVOKE ALL ON FUNCTION jw_private.keep_active_account_template_v1() FROM PUBLIC;

CREATE TRIGGER account_templates_immutable_after_publication
BEFORE UPDATE OR DELETE ON jw.account_templates
FOR EACH ROW EXECUTE FUNCTION jw_private.keep_active_account_template_v1();

CREATE FUNCTION jw_private.keep_draft_account_template_currencies_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $template_currencies$
DECLARE
    old_state text;
    new_state text;
BEGIN
    IF TG_OP <> 'INSERT' THEN
        SELECT template.state
        INTO old_state
        FROM jw.account_templates AS template
        WHERE template.id = OLD.template_id
          AND template.template_version = OLD.template_version
          AND template.organization_id = OLD.organization_id;
        IF old_state IS DISTINCT FROM 'draft' THEN
            RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ACCOUNT_TEMPLATE_CURRENCIES_IMMUTABLE';
        END IF;
    END IF;

    IF TG_OP <> 'DELETE' THEN
        SELECT template.state
        INTO new_state
        FROM jw.account_templates AS template
        WHERE template.id = NEW.template_id
          AND template.template_version = NEW.template_version
          AND template.organization_id = NEW.organization_id;
        IF new_state IS DISTINCT FROM 'draft' THEN
            RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ACCOUNT_TEMPLATE_CURRENCIES_IMMUTABLE';
        END IF;
        RETURN NEW;
    END IF;

    RETURN OLD;
END
$template_currencies$;
REVOKE ALL ON FUNCTION jw_private.keep_draft_account_template_currencies_v1() FROM PUBLIC;

CREATE TRIGGER account_template_currencies_draft_only
BEFORE INSERT OR UPDATE OR DELETE ON jw.account_template_currencies
FOR EACH ROW EXECUTE FUNCTION jw_private.keep_draft_account_template_currencies_v1();

CREATE FUNCTION jw_private.keep_account_identity_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $account_identity$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ACCOUNT_IDENTITY_RETAINED';
    END IF;

    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.book_id IS DISTINCT FROM OLD.book_id
       OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
       OR NEW.code IS DISTINCT FROM OLD.code THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ACCOUNT_IDENTITY_IMMUTABLE';
    END IF;

    IF (OLD.state <> 'pending' OR NEW.state <> 'pending')
       AND (
           NEW.currency_definition_id IS DISTINCT FROM OLD.currency_definition_id
           OR NEW.template_id IS DISTINCT FROM OLD.template_id
           OR NEW.template_version IS DISTINCT FROM OLD.template_version
           OR NEW.classification IS DISTINCT FROM OLD.classification
           OR NEW.normal_side IS DISTINCT FROM OLD.normal_side
           OR NEW.spend_policy IS DISTINCT FROM OLD.spend_policy
       ) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ACCOUNT_ACCOUNTING_IDENTITY_IMMUTABLE';
    END IF;

    IF (OLD.state = 'pending' AND NEW.state NOT IN ('pending', 'active'))
       OR (OLD.state = 'active' AND NEW.state NOT IN ('active', 'frozen', 'closed'))
       OR (OLD.state = 'frozen' AND NEW.state NOT IN ('frozen', 'active', 'closed'))
       OR (OLD.state = 'closed' AND NEW.state <> 'closed') THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'ACCOUNT_STATE_TRANSITION_INVALID';
    END IF;

    RETURN NEW;
END
$account_identity$;
REVOKE ALL ON FUNCTION jw_private.keep_account_identity_v1() FROM PUBLIC;

CREATE TRIGGER accounts_identity_retained
BEFORE UPDATE OR DELETE ON jw.accounts
FOR EACH ROW EXECUTE FUNCTION jw_private.keep_account_identity_v1();

CREATE FUNCTION jw_private.keep_book_role_history_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $book_role$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'BOOK_ROLE_HISTORY_RETAINED';
    END IF;

    IF ROW(NEW.id, NEW.book_id, NEW.organization_id, NEW.membership_id, NEW.role,
           NEW.granted_by, NEW.created_at, NEW.expires_at)
       IS DISTINCT FROM
       ROW(OLD.id, OLD.book_id, OLD.organization_id, OLD.membership_id, OLD.role,
           OLD.granted_by, OLD.created_at, OLD.expires_at)
       OR (OLD.state = 'revoked' AND NEW.state <> 'revoked')
       OR (OLD.state = 'active' AND NEW.state NOT IN ('active', 'revoked'))
       OR (NEW.state <> OLD.state AND NEW.version <> OLD.version + 1)
       OR (NEW.state = OLD.state AND NEW.version <> OLD.version) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'BOOK_ROLE_ASSIGNMENT_IMMUTABLE';
    END IF;

    RETURN NEW;
END
$book_role$;
REVOKE ALL ON FUNCTION jw_private.keep_book_role_history_v1() FROM PUBLIC;

CREATE TRIGGER book_role_assignments_append_only
BEFORE UPDATE OR DELETE ON jw.book_role_assignments
FOR EACH ROW EXECUTE FUNCTION jw_private.keep_book_role_history_v1();

CREATE FUNCTION jw_private.keep_setup_candidate_history_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $setup_candidate$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'SETUP_CANDIDATE_RETAINED';
    END IF;

    IF ROW(NEW.id, NEW.book_id, NEW.organization_id, NEW.candidate_kind,
           NEW.manifest_version, NEW.manifest_payload, NEW.payload_sha256,
           NEW.created_by, NEW.created_at)
       IS DISTINCT FROM
       ROW(OLD.id, OLD.book_id, OLD.organization_id, OLD.candidate_kind,
           OLD.manifest_version, OLD.manifest_payload, OLD.payload_sha256,
           OLD.created_by, OLD.created_at)
       OR (OLD.state = 'draft' AND NEW.state NOT IN ('draft', 'validated'))
       OR (OLD.state = 'validated' AND NEW.state NOT IN ('validated', 'approved'))
       OR (OLD.state = 'approved' AND NEW.state NOT IN ('approved', 'activated'))
       OR (OLD.state = 'activated' AND NEW.state <> 'activated')
       OR (NEW.state <> OLD.state AND NEW.version <> OLD.version + 1)
       OR (NEW.state = OLD.state AND NEW.version <> OLD.version) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'SETUP_CANDIDATE_VERSION_IMMUTABLE';
    END IF;

    RETURN NEW;
END
$setup_candidate$;
REVOKE ALL ON FUNCTION jw_private.keep_setup_candidate_history_v1() FROM PUBLIC;

CREATE TRIGGER book_setup_candidates_versioned_history
BEFORE UPDATE OR DELETE ON jw.book_setup_candidates
FOR EACH ROW EXECUTE FUNCTION jw_private.keep_setup_candidate_history_v1();

CREATE FUNCTION jw_private.keep_book_setup_approval_history_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $setup_approval$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'SETUP_APPROVAL_RETAINED';
    END IF;

    IF ROW(NEW.id, NEW.candidate_id, NEW.book_id, NEW.organization_id,
           NEW.payload_sha256, NEW.reviewer_principal_id, NEW.created_at, NEW.expires_at,
           NEW.reviewer_membership_version)
       IS DISTINCT FROM
       ROW(OLD.id, OLD.candidate_id, OLD.book_id, OLD.organization_id,
           OLD.payload_sha256, OLD.reviewer_principal_id, OLD.created_at, OLD.expires_at,
           OLD.reviewer_membership_version)
       OR (OLD.state = 'revoked' AND NEW.state <> 'revoked')
       OR (OLD.state = 'approved' AND NEW.state NOT IN ('approved', 'revoked')) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'SETUP_APPROVAL_IMMUTABLE';
    END IF;

    RETURN NEW;
END
$setup_approval$;
REVOKE ALL ON FUNCTION jw_private.keep_book_setup_approval_history_v1() FROM PUBLIC;

CREATE TRIGGER book_setup_approvals_append_only
BEFORE UPDATE OR DELETE ON jw.book_setup_approvals
FOR EACH ROW EXECUTE FUNCTION jw_private.keep_book_setup_approval_history_v1();

CREATE FUNCTION jw_private.keep_book_template_approval_history_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $template_approval$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'TEMPLATE_APPROVAL_RETAINED';
    END IF;

    IF ROW(NEW.id, NEW.book_id, NEW.organization_id, NEW.account_template_id,
           NEW.template_version, NEW.payload_sha256, NEW.reviewer_principal_id,
           NEW.reviewer_membership_version, NEW.created_at)
       IS DISTINCT FROM
       ROW(OLD.id, OLD.book_id, OLD.organization_id, OLD.account_template_id,
           OLD.template_version, OLD.payload_sha256, OLD.reviewer_principal_id,
           OLD.reviewer_membership_version, OLD.created_at)
       OR (OLD.state = 'revoked' AND NEW.state <> 'revoked')
       OR (OLD.state = 'approved' AND NEW.state NOT IN ('approved', 'revoked'))
       OR (NEW.state <> OLD.state AND NEW.version <> OLD.version + 1)
       OR (NEW.state = OLD.state AND NEW.version <> OLD.version) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'TEMPLATE_APPROVAL_IMMUTABLE';
    END IF;

    RETURN NEW;
END
$template_approval$;
REVOKE ALL ON FUNCTION jw_private.keep_book_template_approval_history_v1() FROM PUBLIC;

CREATE TRIGGER book_account_template_approvals_append_only
BEFORE UPDATE OR DELETE ON jw.book_account_template_approvals
FOR EACH ROW EXECUTE FUNCTION jw_private.keep_book_template_approval_history_v1();

CREATE FUNCTION jw_private.keep_book_restriction_history_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $book_restriction$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'BOOK_RESTRICTION_RETAINED';
    END IF;

    IF ROW(NEW.id, NEW.book_id, NEW.source, NEW.reason_code, NEW.created_by, NEW.created_at)
       IS DISTINCT FROM
       ROW(OLD.id, OLD.book_id, OLD.source, OLD.reason_code, OLD.created_by, OLD.created_at)
       OR (OLD.state = 'released' AND NEW.state <> 'released')
       OR (OLD.state = 'released' AND (
           NEW.released_by IS DISTINCT FROM OLD.released_by
           OR NEW.released_at IS DISTINCT FROM OLD.released_at
       ))
       OR (OLD.state = 'active' AND NEW.state = 'active' AND (
           NEW.released_by IS DISTINCT FROM OLD.released_by
           OR NEW.released_at IS DISTINCT FROM OLD.released_at
       ))
       OR (OLD.state = 'active' AND NEW.state NOT IN ('active', 'released'))
       OR (NEW.state <> OLD.state AND NEW.version <> OLD.version + 1)
       OR (NEW.state = OLD.state AND NEW.version <> OLD.version) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'BOOK_RESTRICTION_IMMUTABLE';
    END IF;

    RETURN NEW;
END
$book_restriction$;
REVOKE ALL ON FUNCTION jw_private.keep_book_restriction_history_v1() FROM PUBLIC;

CREATE TRIGGER book_lifecycle_restrictions_append_only
BEFORE UPDATE OR DELETE ON jw.book_lifecycle_restrictions
FOR EACH ROW EXECUTE FUNCTION jw_private.keep_book_restriction_history_v1();

REVOKE ALL ON ALL TABLES IN SCHEMA jw FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA jw_api FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA jw_private FROM PUBLIC;
REVOKE CREATE ON SCHEMA jw, jw_api, jw_private, jw_support, public
    FROM PUBLIC, journalwick_runtime, journalwick_worker, journalwick_reporter;
