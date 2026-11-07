DO $verify_pgcrypto$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_extension AS extension
        JOIN pg_catalog.pg_namespace AS extension_schema
            ON extension_schema.oid = extension.extnamespace
        WHERE extension.extname = 'pgcrypto'
          AND extension_schema.nspname = 'jw_support'
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'PGCRYPTO_SCHEMA_INVALID';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_proc AS digest_function
        JOIN pg_catalog.pg_namespace AS function_schema
            ON function_schema.oid = digest_function.pronamespace
        JOIN pg_catalog.pg_depend AS extension_dependency
            ON extension_dependency.classid = 'pg_catalog.pg_proc'::regclass
           AND extension_dependency.objid = digest_function.oid
           AND extension_dependency.refclassid = 'pg_catalog.pg_extension'::regclass
           AND extension_dependency.deptype = 'e'
        JOIN pg_catalog.pg_extension AS extension
            ON extension.oid = extension_dependency.refobjid
        WHERE digest_function.oid = 'jw_support.digest(bytea,text)'::regprocedure
          AND function_schema.nspname = 'jw_support'
          AND extension.extname = 'pgcrypto'
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'PGCRYPTO_SHA256_INTERFACE_INVALID';
    END IF;
END
$verify_pgcrypto$;

ALTER TABLE jw.business_operations
    ADD COLUMN intent_facts jsonb NOT NULL DEFAULT '{}'::jsonb,
    ADD CONSTRAINT business_operations_intent_facts_object CHECK (
        jsonb_typeof(intent_facts) = 'object'
        AND octet_length(intent_facts::text) <= 65536
    );

CREATE OR REPLACE FUNCTION jw_private.keep_business_operation_identity_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $business_operation$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'BUSINESS_OPERATION_RETAINED';
    END IF;

    IF ROW(NEW.id, NEW.book_id, NEW.organization_id, NEW.family, NEW.family_version,
           NEW.origin_namespace, NEW.business_key, NEW.request_sha256, NEW.intent_facts,
           NEW.primary_currency_definition_id, NEW.requested_amount, NEW.created_by, NEW.created_at)
       IS DISTINCT FROM
       ROW(OLD.id, OLD.book_id, OLD.organization_id, OLD.family, OLD.family_version,
           OLD.origin_namespace, OLD.business_key, OLD.request_sha256, OLD.intent_facts,
           OLD.primary_currency_definition_id, OLD.requested_amount, OLD.created_by, OLD.created_at)
       OR NEW.version <> OLD.version + 1
       OR NEW.updated_at < OLD.updated_at THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'BUSINESS_OPERATION_IDENTITY_IMMUTABLE';
    END IF;

    RETURN NEW;
END
$business_operation$;

CREATE FUNCTION jw_private.sha256_v1(p_payload bytea)
RETURNS bytea
LANGUAGE sql
IMMUTABLE
STRICT
PARALLEL SAFE
SET search_path = pg_catalog, pg_temp
AS $sha256$
    SELECT jw_support.digest(p_payload, 'sha256')
$sha256$;
REVOKE ALL ON FUNCTION jw_private.sha256_v1(bytea) FROM PUBLIC;

CREATE FUNCTION jw_private.canonical_request_sha256_v1(
    p_command_family text,
    p_schema_version integer,
    p_book_id uuid,
    p_operation_id uuid,
    p_step_id uuid,
    p_request jsonb
)
RETURNS bytea
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog, pg_temp
AS $canonical_request$
DECLARE
    canonical_payload jsonb;
BEGIN
    IF p_command_family IS NULL
       OR p_schema_version IS NULL
       OR p_book_id IS NULL
       OR p_request IS NULL
       OR p_command_family COLLATE "C" !~ '^[a-z][a-z0-9_.-]{0,79}$'
       OR p_schema_version < 1
       OR jsonb_typeof(p_request) <> 'object'
       OR octet_length(p_request::text) > 65536 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'CANONICAL_REQUEST_INVALID';
    END IF;

    canonical_payload := jsonb_build_array(
        'journalwick.command.v1',
        p_command_family,
        p_schema_version,
        p_book_id,
        p_operation_id,
        p_step_id,
        p_request
    );

    RETURN jw_private.sha256_v1(convert_to(canonical_payload::text, 'UTF8'));
END
$canonical_request$;
REVOKE ALL ON FUNCTION jw_private.canonical_request_sha256_v1(text, integer, uuid, uuid, uuid, jsonb)
    FROM PUBLIC;

CREATE FUNCTION jw_private.wallet_transfer_step_sha256_v1(
    p_book_id uuid,
    p_operation_id uuid,
    p_step_key text,
    p_operation_request_sha256 bytea
)
RETURNS bytea
LANGUAGE plpgsql
IMMUTABLE
STRICT
SET search_path = pg_catalog, pg_temp
AS $wallet_transfer_step$
BEGIN
    IF char_length(p_step_key) NOT BETWEEN 1 AND 100
       OR p_step_key COLLATE "C" !~ '^[A-Za-z0-9][A-Za-z0-9_.:-]*$'
       OR octet_length(p_operation_request_sha256) <> 32 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'OPERATION_STEP_IDENTITY_INVALID';
    END IF;

    RETURN jw_private.sha256_v1(convert_to(
        jsonb_build_array(
            'journalwick.wallet-transfer-step.v1',
            p_book_id,
            p_operation_id,
            p_step_key,
            encode(p_operation_request_sha256, 'hex')
        )::text,
        'UTF8'
    ));
END
$wallet_transfer_step$;
REVOKE ALL ON FUNCTION jw_private.wallet_transfer_step_sha256_v1(uuid, uuid, text, bytea)
    FROM PUBLIC;

CREATE FUNCTION jw_private.posting_template_payload_sha256_v1(
    p_template_id uuid,
    p_version integer,
    p_book_id uuid,
    p_payload jsonb
)
RETURNS bytea
LANGUAGE plpgsql
IMMUTABLE
STRICT
SET search_path = pg_catalog, pg_temp
AS $template_payload$
DECLARE
    canonical_payload jsonb;
BEGIN
    IF p_version < 1
       OR jsonb_typeof(p_payload) <> 'object'
       OR octet_length(p_payload::text) > 65536 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'POSTING_TEMPLATE_PAYLOAD_INVALID';
    END IF;

    canonical_payload := jsonb_build_array(
        'journalwick.posting-template.v1',
        p_template_id,
        p_version,
        p_book_id,
        p_payload
    );
    RETURN jw_private.sha256_v1(convert_to(canonical_payload::text, 'UTF8'));
END
$template_payload$;
REVOKE ALL ON FUNCTION jw_private.posting_template_payload_sha256_v1(uuid, integer, uuid, jsonb)
    FROM PUBLIC;

CREATE FUNCTION jw_private.posting_proposal_payload_sha256_v1(
    p_proposal_id uuid,
    p_version bigint,
    p_book_id uuid,
    p_template_id uuid,
    p_template_version integer,
    p_effective_date date,
    p_period_id uuid,
    p_canonical_lines jsonb,
    p_evidence_references jsonb
)
RETURNS bytea
LANGUAGE plpgsql
IMMUTABLE
STRICT
SET search_path = pg_catalog, pg_temp
AS $proposal_payload$
DECLARE
    canonical_payload jsonb;
BEGIN
    IF p_version < 1
       OR p_template_version < 1
       OR jsonb_typeof(p_canonical_lines) <> 'array'
       OR jsonb_array_length(p_canonical_lines) NOT BETWEEN 2 AND 200
       OR jsonb_typeof(p_evidence_references) <> 'array'
       OR octet_length(p_canonical_lines::text) > 262144
       OR octet_length(p_evidence_references::text) > 65536 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'POSTING_PROPOSAL_PAYLOAD_INVALID';
    END IF;

    canonical_payload := jsonb_build_array(
        'journalwick.posting-proposal.v1',
        p_proposal_id,
        p_version,
        p_book_id,
        p_template_id,
        p_template_version,
        p_effective_date,
        p_period_id,
        p_canonical_lines,
        p_evidence_references
    );
    RETURN jw_private.sha256_v1(convert_to(canonical_payload::text, 'UTF8'));
END
$proposal_payload$;
REVOKE ALL ON FUNCTION jw_private.posting_proposal_payload_sha256_v1(
    uuid, bigint, uuid, uuid, integer, date, uuid, jsonb, jsonb
) FROM PUBLIC;

CREATE FUNCTION jw_private.parse_positive_amount_v1(p_amount text)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
STRICT
SET search_path = pg_catalog, pg_temp
AS $positive_amount$
BEGIN
    IF char_length(p_amount) NOT BETWEEN 1 AND 30
       OR p_amount COLLATE "C" !~ '^[1-9][0-9]{0,29}$' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'AMOUNT_FORMAT_INVALID';
    END IF;

    RETURN p_amount::numeric(38, 0);
END
$positive_amount$;
REVOKE ALL ON FUNCTION jw_private.parse_positive_amount_v1(text) FROM PUBLIC;

CREATE FUNCTION jw_private.validate_canonical_lines_v1(p_lines jsonb)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
STRICT
SET search_path = pg_catalog, pg_temp
AS $canonical_lines$
DECLARE
    line jsonb;
    line_count integer;
    field_name text;
    allowed_fields constant text[] := ARRAY[
        'account_id', 'amount', 'currency_definition_id', 'safe_description', 'side', 'template_role'
    ];
    required_fields constant text[] := ARRAY[
        'account_id', 'amount', 'currency_definition_id', 'side', 'template_role'
    ];
    amount_text text;
    account_id uuid;
    currency_definition_id uuid;
    description text;
BEGIN
    IF jsonb_typeof(p_lines) <> 'array' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'POSTING_LINES_INVALID';
    END IF;

    line_count := jsonb_array_length(p_lines);
    IF line_count NOT BETWEEN 2 AND 200 OR octet_length(p_lines::text) > 262144 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'POSTING_LINES_INVALID';
    END IF;

    FOR line IN SELECT value FROM jsonb_array_elements(p_lines)
    LOOP
        IF jsonb_typeof(line) <> 'object'
           OR NOT (line ?& required_fields)
           OR EXISTS (
               SELECT 1
               FROM jsonb_object_keys(line) AS fields(field_name)
               WHERE fields.field_name <> ALL (allowed_fields)
           )
           OR jsonb_typeof(line -> 'account_id') <> 'string'
           OR jsonb_typeof(line -> 'currency_definition_id') <> 'string'
           OR jsonb_typeof(line -> 'amount') <> 'string'
           OR jsonb_typeof(line -> 'side') <> 'string'
           OR jsonb_typeof(line -> 'template_role') <> 'string' THEN
            RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'POSTING_LINE_SHAPE_INVALID';
        END IF;

        BEGIN
            account_id := (line ->> 'account_id')::uuid;
            currency_definition_id := (line ->> 'currency_definition_id')::uuid;
        EXCEPTION WHEN invalid_text_representation THEN
            RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'POSTING_LINE_ID_INVALID';
        END;

        amount_text := line ->> 'amount';
        PERFORM jw_private.parse_positive_amount_v1(amount_text);

        IF line ->> 'side' NOT IN ('debit', 'credit')
           OR char_length(line ->> 'template_role') NOT BETWEEN 1 AND 80
           OR (line ->> 'template_role') COLLATE "C" !~ '^[A-Za-z][A-Za-z0-9_.-]*$' THEN
            RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'POSTING_LINE_SEMANTICS_INVALID';
        END IF;

        IF line ? 'safe_description' THEN
            IF jsonb_typeof(line -> 'safe_description') NOT IN ('string', 'null') THEN
                RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'POSTING_LINE_DESCRIPTION_INVALID';
            END IF;
            description := line ->> 'safe_description';
            IF description IS NOT NULL
               AND (char_length(description) > 200 OR description ~ '[[:cntrl:]]') THEN
                RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'POSTING_LINE_DESCRIPTION_INVALID';
            END IF;
        END IF;
    END LOOP;

    RETURN line_count;
END
$canonical_lines$;
REVOKE ALL ON FUNCTION jw_private.validate_canonical_lines_v1(jsonb) FROM PUBLIC;

CREATE TABLE jw.journals (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    book_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    journal_sequence bigint NOT NULL,
    state_sequence bigint NOT NULL,
    operation_id uuid NOT NULL,
    operation_step_id uuid NOT NULL,
    proposal_id uuid,
    accepted_proposal_version bigint,
    accepted_proposal_sha256 bytea,
    template_id uuid NOT NULL,
    template_version integer NOT NULL,
    effective_date date NOT NULL,
    period_id uuid NOT NULL,
    posted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    source_kind text NOT NULL,
    source_reference_id uuid,
    reversal_of uuid,
    payload_sha256 bytea NOT NULL,
    created_by uuid NOT NULL REFERENCES jw.principals (id) ON DELETE RESTRICT,
    CONSTRAINT journals_sequence_positive CHECK (journal_sequence > 0),
    CONSTRAINT journals_state_sequence_positive CHECK (state_sequence > 0),
    CONSTRAINT journals_template_version_positive CHECK (template_version > 0),
    CONSTRAINT journals_proposal_reference_shape CHECK (
        (proposal_id IS NULL AND accepted_proposal_version IS NULL AND accepted_proposal_sha256 IS NULL)
        OR (
            proposal_id IS NOT NULL
            AND accepted_proposal_version IS NOT NULL
            AND accepted_proposal_version > 0
            AND accepted_proposal_sha256 IS NOT NULL
            AND octet_length(accepted_proposal_sha256) = 32
        )
    ),
    CONSTRAINT journals_source_kind_shape CHECK (
        char_length(source_kind) BETWEEN 1 AND 80
        AND source_kind COLLATE "C" ~ '^[a-z][a-z0-9_.-]*$'
    ),
    CONSTRAINT journals_reversal_not_self CHECK (reversal_of IS NULL OR reversal_of <> id),
    CONSTRAINT journals_payload_hash_size CHECK (octet_length(payload_sha256) = 32),
    CONSTRAINT journals_book_scope_fk
        FOREIGN KEY (book_id, organization_id)
        REFERENCES jw.books (id, organization_id) ON DELETE RESTRICT,
    CONSTRAINT journals_operation_scope_fk
        FOREIGN KEY (operation_id, book_id)
        REFERENCES jw.business_operations (id, book_id) ON DELETE RESTRICT,
    CONSTRAINT journals_operation_step_scope_fk
        FOREIGN KEY (operation_step_id, operation_id, book_id)
        REFERENCES jw.operation_steps (id, operation_id, book_id) ON DELETE RESTRICT,
    CONSTRAINT journals_proposal_version_scope_fk
        FOREIGN KEY (proposal_id, accepted_proposal_version, book_id, accepted_proposal_sha256)
        REFERENCES jw.posting_proposal_versions
            (proposal_id, proposal_version, book_id, payload_sha256) ON DELETE RESTRICT,
    CONSTRAINT journals_template_version_scope_fk
        FOREIGN KEY (template_id, template_version, book_id)
        REFERENCES jw.posting_template_versions (template_id, version, book_id) ON DELETE RESTRICT,
    CONSTRAINT journals_period_scope_fk
        FOREIGN KEY (period_id, book_id)
        REFERENCES jw.accounting_periods (id, book_id) ON DELETE RESTRICT,
    CONSTRAINT journals_reversal_scope_fk
        FOREIGN KEY (reversal_of, book_id)
        REFERENCES jw.journals (id, book_id) ON DELETE RESTRICT,
    CONSTRAINT journals_book_sequence_unique UNIQUE (book_id, journal_sequence),
    CONSTRAINT journals_one_per_operation_step UNIQUE (operation_step_id),
    CONSTRAINT journals_id_book_unique UNIQUE (id, book_id),
    CONSTRAINT journals_id_step_book_unique UNIQUE (id, operation_step_id, book_id),
    CONSTRAINT journals_id_book_sequence_unique UNIQUE (id, book_id, journal_sequence)
);
CREATE INDEX journals_book_effective_date_idx
    ON jw.journals (book_id, effective_date, journal_sequence, id);
CREATE INDEX journals_book_operation_idx
    ON jw.journals (book_id, operation_id, journal_sequence, id);
CREATE INDEX journals_book_proposal_idx
    ON jw.journals (book_id, proposal_id, accepted_proposal_version)
    WHERE proposal_id IS NOT NULL;

CREATE TABLE jw.postings (
    journal_id uuid NOT NULL,
    line_number integer NOT NULL,
    book_id uuid NOT NULL,
    account_id uuid NOT NULL,
    currency_definition_id uuid NOT NULL,
    side text NOT NULL,
    amount numeric(38, 0) NOT NULL,
    template_role text NOT NULL,
    safe_description text,
    CONSTRAINT postings_pk PRIMARY KEY (journal_id, line_number),
    CONSTRAINT postings_line_number_range CHECK (line_number BETWEEN 1 AND 200),
    CONSTRAINT postings_side CHECK (side IN ('debit', 'credit')),
    CONSTRAINT postings_amount_range CHECK (
        amount > 0 AND amount < 1000000000000000000000000000000
    ),
    CONSTRAINT postings_template_role_shape CHECK (
        char_length(template_role) BETWEEN 1 AND 80
        AND template_role COLLATE "C" ~ '^[A-Za-z][A-Za-z0-9_.-]*$'
    ),
    CONSTRAINT postings_safe_description_shape CHECK (
        safe_description IS NULL
        OR (char_length(safe_description) <= 200 AND safe_description !~ '[[:cntrl:]]')
    ),
    CONSTRAINT postings_journal_scope_fk
        FOREIGN KEY (journal_id, book_id)
        REFERENCES jw.journals (id, book_id) ON DELETE RESTRICT
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT postings_account_currency_scope_fk
        FOREIGN KEY (account_id, book_id, currency_definition_id)
        REFERENCES jw.accounts (id, book_id, currency_definition_id) ON DELETE RESTRICT,
    CONSTRAINT postings_id_book_line_unique UNIQUE (journal_id, book_id, line_number),
    CONSTRAINT postings_id_book_line_amount_unique UNIQUE (journal_id, book_id, line_number, amount),
    CONSTRAINT postings_id_book_line_detail_unique
        UNIQUE (journal_id, book_id, line_number, amount, side, account_id, currency_definition_id)
);
CREATE INDEX postings_account_journal_line_idx
    ON jw.postings (account_id, journal_id, line_number);
CREATE INDEX postings_book_currency_journal_idx
    ON jw.postings (book_id, currency_definition_id, journal_id, line_number);

CREATE FUNCTION jw_private.reject_posting_after_journal_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $posting_header_guard$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM jw.journals AS journal
        WHERE journal.id = NEW.journal_id
          AND journal.book_id = NEW.book_id
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'POSTING_HEADER_ALREADY_ACCEPTED';
    END IF;
    RETURN NEW;
END
$posting_header_guard$;
REVOKE ALL ON FUNCTION jw_private.reject_posting_after_journal_v1() FROM PUBLIC;

CREATE TRIGGER postings_require_header_last_order
BEFORE INSERT ON jw.postings
FOR EACH ROW EXECUTE FUNCTION jw_private.reject_posting_after_journal_v1();

CREATE FUNCTION jw_private.verify_journal_posting_batch_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $journal_batch$
DECLARE
    line_count bigint;
    minimum_line integer;
    maximum_line integer;
BEGIN
    SELECT count(*), min(line_number), max(line_number)
    INTO line_count, minimum_line, maximum_line
    FROM jw.postings
    WHERE journal_id = NEW.id
      AND book_id = NEW.book_id;

    IF line_count NOT BETWEEN 2 AND 200
       OR minimum_line <> 1
       OR maximum_line <> line_count THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'JOURNAL_POSTING_BATCH_INVALID';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM jw.postings AS posting
        WHERE posting.journal_id = NEW.id
          AND posting.book_id = NEW.book_id
        GROUP BY posting.currency_definition_id
        HAVING coalesce(sum(posting.amount) FILTER (WHERE posting.side = 'debit'), 0)
            <> coalesce(sum(posting.amount) FILTER (WHERE posting.side = 'credit'), 0)
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'JOURNAL_CURRENCY_IMBALANCE';
    END IF;

    RETURN NEW;
END
$journal_batch$;
REVOKE ALL ON FUNCTION jw_private.verify_journal_posting_batch_v1() FROM PUBLIC;

CREATE CONSTRAINT TRIGGER journals_require_balanced_batch
AFTER INSERT ON jw.journals
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION jw_private.verify_journal_posting_batch_v1();

CREATE TRIGGER journals_immutable_rows
BEFORE UPDATE OR DELETE ON jw.journals
FOR EACH ROW EXECUTE FUNCTION jw_private.reject_immutable_row_v1();
CREATE TRIGGER journals_immutable_truncate
BEFORE TRUNCATE ON jw.journals
FOR EACH STATEMENT EXECUTE FUNCTION jw_private.reject_immutable_row_v1();
CREATE TRIGGER postings_immutable_rows
BEFORE UPDATE OR DELETE ON jw.postings
FOR EACH ROW EXECUTE FUNCTION jw_private.reject_immutable_row_v1();
CREATE TRIGGER postings_immutable_truncate
BEFORE TRUNCATE ON jw.postings
FOR EACH STATEMENT EXECUTE FUNCTION jw_private.reject_immutable_row_v1();

ALTER TABLE jw.posting_proposals
    ADD CONSTRAINT posting_proposals_id_step_book_unique
    UNIQUE (id, operation_step_id, book_id);

ALTER TABLE jw.journals
    ADD CONSTRAINT journals_proposal_step_scope_fk
    FOREIGN KEY (proposal_id, operation_step_id, book_id)
    REFERENCES jw.posting_proposals (id, operation_step_id, book_id) ON DELETE RESTRICT;

ALTER TABLE jw.operation_steps
    ADD CONSTRAINT operation_steps_result_journal_scope_fk
    FOREIGN KEY (result_journal_id, id, book_id)
    REFERENCES jw.journals (id, operation_step_id, book_id) ON DELETE RESTRICT
    DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE jw.economic_recognitions
    ADD CONSTRAINT economic_recognitions_journal_step_scope_fk
    FOREIGN KEY (journal_id, operation_step_id, book_id)
    REFERENCES jw.journals (id, operation_step_id, book_id) ON DELETE RESTRICT
    DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE jw.journal_correction_limits (
    original_journal_id uuid PRIMARY KEY,
    book_id uuid NOT NULL,
    policy_version text NOT NULL,
    state text NOT NULL DEFAULT 'eligible',
    full_reversal_journal_id uuid,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT journal_correction_limits_policy_shape CHECK (
        char_length(policy_version) BETWEEN 1 AND 80
        AND policy_version COLLATE "C" ~ '^[A-Za-z0-9][A-Za-z0-9_.:-]*$'
    ),
    CONSTRAINT journal_correction_limits_state CHECK (
        state IN ('eligible', 'partially_corrected', 'fully_corrected', 'restricted')
    ),
    CONSTRAINT journal_correction_limits_full_reversal_state CHECK (
        full_reversal_journal_id IS NULL OR state = 'fully_corrected'
    ),
    CONSTRAINT journal_correction_limits_full_reversal_not_self CHECK (
        full_reversal_journal_id IS NULL OR full_reversal_journal_id <> original_journal_id
    ),
    CONSTRAINT journal_correction_limits_version_positive CHECK (version > 0),
    CONSTRAINT journal_correction_limits_updated_time CHECK (updated_at >= created_at),
    CONSTRAINT journal_correction_limits_original_scope_fk
        FOREIGN KEY (original_journal_id, book_id)
        REFERENCES jw.journals (id, book_id) ON DELETE RESTRICT,
    CONSTRAINT journal_correction_limits_full_reversal_scope_fk
        FOREIGN KEY (full_reversal_journal_id, book_id)
        REFERENCES jw.journals (id, book_id) ON DELETE RESTRICT,
    CONSTRAINT journal_correction_limits_id_scope_unique UNIQUE (original_journal_id, book_id)
);
CREATE UNIQUE INDEX journal_correction_limits_full_reversal_uq
    ON jw.journal_correction_limits (full_reversal_journal_id)
    WHERE full_reversal_journal_id IS NOT NULL;

CREATE FUNCTION jw_private.validate_full_reversal_journal_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $full_reversal$
DECLARE
    referenced_journal uuid;
BEGIN
    IF NEW.full_reversal_journal_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT journal.reversal_of
    INTO referenced_journal
    FROM jw.journals AS journal
    WHERE journal.id = NEW.full_reversal_journal_id
      AND journal.book_id = NEW.book_id;

    IF referenced_journal IS DISTINCT FROM NEW.original_journal_id
       OR NEW.state <> 'fully_corrected' THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'FULL_REVERSAL_JOURNAL_INVALID';
    END IF;

    RETURN NEW;
END
$full_reversal$;
REVOKE ALL ON FUNCTION jw_private.validate_full_reversal_journal_v1() FROM PUBLIC;

CREATE TRIGGER journal_correction_limits_full_reversal_binding
BEFORE INSERT OR UPDATE ON jw.journal_correction_limits
FOR EACH ROW EXECUTE FUNCTION jw_private.validate_full_reversal_journal_v1();

CREATE TABLE jw.journal_line_correction_state (
    original_journal_id uuid NOT NULL,
    original_line_number integer NOT NULL,
    book_id uuid NOT NULL,
    original_amount numeric(38, 0) NOT NULL,
    corrected_amount numeric(38, 0) NOT NULL DEFAULT 0,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT journal_line_correction_state_pk
        PRIMARY KEY (original_journal_id, original_line_number),
    CONSTRAINT journal_line_correction_state_original_amount CHECK (
        original_amount > 0 AND original_amount < 1000000000000000000000000000000
    ),
    CONSTRAINT journal_line_correction_state_corrected_range CHECK (
        corrected_amount >= 0 AND corrected_amount <= original_amount
    ),
    CONSTRAINT journal_line_correction_state_version_positive CHECK (version > 0),
    CONSTRAINT journal_line_correction_state_original_posting_fk
        FOREIGN KEY (original_journal_id, book_id, original_line_number, original_amount)
        REFERENCES jw.postings (journal_id, book_id, line_number, amount) ON DELETE RESTRICT,
    CONSTRAINT journal_line_correction_state_limit_scope_fk
        FOREIGN KEY (original_journal_id, book_id)
        REFERENCES jw.journal_correction_limits (original_journal_id, book_id) ON DELETE RESTRICT
);

CREATE TABLE jw.journal_correction_allocations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    book_id uuid NOT NULL,
    original_journal_id uuid NOT NULL,
    original_line_number integer NOT NULL,
    correction_step_id uuid NOT NULL,
    correction_journal_id uuid NOT NULL,
    correction_line_number integer NOT NULL,
    amount numeric(38, 0) NOT NULL,
    reason_code text NOT NULL,
    proposal_id uuid NOT NULL,
    proposal_version bigint NOT NULL,
    proposal_payload_sha256 bytea NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT journal_correction_allocations_amount_range CHECK (
        amount > 0 AND amount < 1000000000000000000000000000000
    ),
    CONSTRAINT journal_correction_allocations_reason_shape CHECK (
        char_length(reason_code) BETWEEN 1 AND 64
        AND reason_code COLLATE "C" ~ '^[a-z][a-z0-9_.-]*$'
    ),
    CONSTRAINT journal_correction_allocations_proposal_version_positive CHECK (
        proposal_version > 0
    ),
    CONSTRAINT journal_correction_allocations_proposal_hash_size CHECK (
        octet_length(proposal_payload_sha256) = 32
    ),
    CONSTRAINT journal_correction_allocations_original_line_fk
        FOREIGN KEY (original_journal_id, book_id, original_line_number)
        REFERENCES jw.postings (journal_id, book_id, line_number) ON DELETE RESTRICT,
    CONSTRAINT journal_correction_allocations_correction_line_fk
        FOREIGN KEY (correction_journal_id, book_id, correction_line_number, amount)
        REFERENCES jw.postings (journal_id, book_id, line_number, amount) ON DELETE RESTRICT,
    CONSTRAINT journal_correction_allocations_step_scope_fk
        FOREIGN KEY (correction_step_id, book_id)
        REFERENCES jw.operation_steps (id, book_id) ON DELETE RESTRICT,
    CONSTRAINT journal_correction_allocations_proposal_step_scope_fk
        FOREIGN KEY (proposal_id, correction_step_id, book_id)
        REFERENCES jw.posting_proposals (id, operation_step_id, book_id) ON DELETE RESTRICT,
    CONSTRAINT journal_correction_allocations_proposal_version_fk
        FOREIGN KEY (proposal_id, proposal_version, book_id, proposal_payload_sha256)
        REFERENCES jw.posting_proposal_versions
            (proposal_id, proposal_version, book_id, payload_sha256) ON DELETE RESTRICT,
    CONSTRAINT journal_correction_allocations_one_line_per_step
        UNIQUE (correction_step_id, original_journal_id, original_line_number),
    CONSTRAINT journal_correction_allocations_one_source_per_correction_line
        UNIQUE (correction_journal_id, book_id, correction_line_number)
);
CREATE INDEX journal_correction_allocations_original_line_idx
    ON jw.journal_correction_allocations (book_id, original_journal_id, original_line_number);

CREATE FUNCTION jw_private.validate_journal_correction_allocation_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $correction_allocation$
DECLARE
    original_side text;
    original_account_id uuid;
    original_currency_id uuid;
    correction_side text;
    correction_account_id uuid;
    correction_currency_id uuid;
    proposal_hash bytea;
    accepted_proposal_id uuid;
    accepted_proposal_version bigint;
    accepted_proposal_hash bytea;
    reversal_target uuid;
    step_operation uuid;
    step_kind text;
BEGIN
    SELECT side, account_id, currency_definition_id
    INTO original_side, original_account_id, original_currency_id
    FROM jw.postings
    WHERE journal_id = NEW.original_journal_id
      AND book_id = NEW.book_id
      AND line_number = NEW.original_line_number;

    SELECT side, account_id, currency_definition_id
    INTO correction_side, correction_account_id, correction_currency_id
    FROM jw.postings
    WHERE journal_id = NEW.correction_journal_id
      AND book_id = NEW.book_id
      AND line_number = NEW.correction_line_number
      AND amount = NEW.amount;

    IF original_side IS NULL
       OR correction_side IS NULL
       OR original_account_id IS DISTINCT FROM correction_account_id
       OR original_currency_id IS DISTINCT FROM correction_currency_id
       OR original_side = correction_side THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'CORRECTION_LINE_BINDING_INVALID';
    END IF;

    SELECT proposal.payload_sha256
    INTO proposal_hash
    FROM jw.posting_proposal_versions AS proposal
    WHERE proposal.proposal_id = NEW.proposal_id
      AND proposal.proposal_version = NEW.proposal_version
      AND proposal.book_id = NEW.book_id;

    SELECT journal.proposal_id, journal.accepted_proposal_version,
           journal.accepted_proposal_sha256, journal.reversal_of
    INTO accepted_proposal_id, accepted_proposal_version, accepted_proposal_hash, reversal_target
    FROM jw.journals AS journal
    WHERE journal.id = NEW.correction_journal_id
      AND journal.book_id = NEW.book_id;

    SELECT operation_step.operation_id, operation_step.step_kind
    INTO step_operation, step_kind
    FROM jw.operation_steps AS operation_step
    WHERE operation_step.id = NEW.correction_step_id
      AND operation_step.book_id = NEW.book_id;

    IF step_kind NOT IN ('reverse', 'adjust') THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'CORRECTION_STEP_KIND_INVALID';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM jw.journals AS correction_journal
        WHERE correction_journal.id = NEW.correction_journal_id
          AND correction_journal.book_id = NEW.book_id
          AND correction_journal.operation_id = step_operation
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'CORRECTION_OPERATION_BINDING_INVALID';
    END IF;

    IF proposal_hash IS DISTINCT FROM NEW.proposal_payload_sha256
       OR accepted_proposal_id IS DISTINCT FROM NEW.proposal_id
       OR accepted_proposal_version IS DISTINCT FROM NEW.proposal_version
       OR accepted_proposal_hash IS DISTINCT FROM NEW.proposal_payload_sha256
       OR reversal_target IS DISTINCT FROM NEW.original_journal_id THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'CORRECTION_PROPOSAL_BINDING_INVALID';
    END IF;

    RETURN NEW;
END
$correction_allocation$;
REVOKE ALL ON FUNCTION jw_private.validate_journal_correction_allocation_v1() FROM PUBLIC;

CREATE TRIGGER journal_correction_allocations_validate_binding
BEFORE INSERT ON jw.journal_correction_allocations
FOR EACH ROW EXECUTE FUNCTION jw_private.validate_journal_correction_allocation_v1();
CREATE TRIGGER journal_correction_allocations_append_only
BEFORE UPDATE OR DELETE ON jw.journal_correction_allocations
FOR EACH ROW EXECUTE FUNCTION jw_private.reject_immutable_row_v1();
CREATE TRIGGER journal_correction_allocations_no_truncate
BEFORE TRUNCATE ON jw.journal_correction_allocations
FOR EACH STATEMENT EXECUTE FUNCTION jw_private.reject_immutable_row_v1();

CREATE FUNCTION jw_private.verify_journal_correction_total_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $correction_total$
DECLARE
    expected_corrected numeric(38, 0);
    allocated_total numeric(38, 0);
BEGIN
    SELECT state.corrected_amount
    INTO expected_corrected
    FROM jw.journal_line_correction_state AS state
    WHERE state.original_journal_id = NEW.original_journal_id
      AND state.original_line_number = NEW.original_line_number
      AND state.book_id = NEW.book_id;

    SELECT coalesce(sum(allocation.amount), 0)
    INTO allocated_total
    FROM jw.journal_correction_allocations AS allocation
    WHERE allocation.original_journal_id = NEW.original_journal_id
      AND allocation.original_line_number = NEW.original_line_number
      AND allocation.book_id = NEW.book_id;

    IF expected_corrected IS DISTINCT FROM allocated_total THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'CORRECTION_ALLOCATION_TOTAL_MISMATCH';
    END IF;

    RETURN NEW;
END
$correction_total$;
REVOKE ALL ON FUNCTION jw_private.verify_journal_correction_total_v1() FROM PUBLIC;

CREATE CONSTRAINT TRIGGER correction_state_matches_allocations
AFTER INSERT OR UPDATE ON jw.journal_line_correction_state
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION jw_private.verify_journal_correction_total_v1();
CREATE CONSTRAINT TRIGGER correction_allocations_match_state
AFTER INSERT ON jw.journal_correction_allocations
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION jw_private.verify_journal_correction_total_v1();

CREATE FUNCTION jw_private.verify_journal_correction_policy_state_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $correction_policy_state$
DECLARE
    original_id uuid;
    book_scope uuid;
    limit_state text;
    full_reversal_id uuid;
    original_line_count bigint;
    correction_line_count bigint;
    line_state_count bigint;
    changed_line_count bigint;
    fully_corrected_line_count bigint;
BEGIN
    original_id := NEW.original_journal_id;
    book_scope := NEW.book_id;

    SELECT limits.state, limits.full_reversal_journal_id
    INTO limit_state, full_reversal_id
    FROM jw.journal_correction_limits AS limits
    WHERE limits.original_journal_id = original_id
      AND limits.book_id = book_scope;

    IF limit_state IS NULL OR limit_state = 'restricted' THEN
        RETURN NEW;
    END IF;

    SELECT count(*)
    INTO original_line_count
    FROM jw.postings AS posting
    WHERE posting.journal_id = original_id
      AND posting.book_id = book_scope;

    SELECT count(*),
           count(*) FILTER (WHERE state.corrected_amount > 0),
           count(*) FILTER (WHERE state.corrected_amount = state.original_amount)
    INTO line_state_count, changed_line_count, fully_corrected_line_count
    FROM jw.journal_line_correction_state AS state
    WHERE state.original_journal_id = original_id
      AND state.book_id = book_scope;

    IF line_state_count <> original_line_count THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'CORRECTION_LINE_STATE_INCOMPLETE';
    END IF;

    IF (limit_state = 'eligible' AND changed_line_count <> 0)
       OR (
           limit_state = 'partially_corrected'
           AND (changed_line_count = 0 OR fully_corrected_line_count = original_line_count)
       )
       OR (
           limit_state = 'fully_corrected'
           AND fully_corrected_line_count <> original_line_count
       ) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'CORRECTION_LIMIT_STATE_MISMATCH';
    END IF;

    IF full_reversal_id IS NOT NULL THEN
        SELECT count(*)
        INTO correction_line_count
        FROM jw.postings AS posting
        WHERE posting.journal_id = full_reversal_id
          AND posting.book_id = book_scope;

        IF correction_line_count <> original_line_count
           OR EXISTS (
               SELECT 1
               FROM jw.journal_line_correction_state AS state
               LEFT JOIN (
                   SELECT allocation.original_journal_id,
                          allocation.original_line_number,
                          sum(allocation.amount) AS allocated_amount
                   FROM jw.journal_correction_allocations AS allocation
                   WHERE allocation.correction_journal_id = full_reversal_id
                     AND allocation.book_id = book_scope
                   GROUP BY allocation.original_journal_id, allocation.original_line_number
               ) AS reversal_allocations
                 ON reversal_allocations.original_journal_id = state.original_journal_id
                AND reversal_allocations.original_line_number = state.original_line_number
               WHERE state.original_journal_id = original_id
                 AND state.book_id = book_scope
                 AND coalesce(reversal_allocations.allocated_amount, 0) <> state.original_amount
           ) THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'FULL_REVERSAL_ALLOCATION_INCOMPLETE';
        END IF;
    END IF;

    RETURN NEW;
END
$correction_policy_state$;
REVOKE ALL ON FUNCTION jw_private.verify_journal_correction_policy_state_v1() FROM PUBLIC;

CREATE CONSTRAINT TRIGGER correction_limit_state_complete
AFTER INSERT OR UPDATE ON jw.journal_correction_limits
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION jw_private.verify_journal_correction_policy_state_v1();
CREATE CONSTRAINT TRIGGER correction_line_state_complete
AFTER INSERT OR UPDATE ON jw.journal_line_correction_state
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION jw_private.verify_journal_correction_policy_state_v1();

CREATE FUNCTION jw_private.keep_journal_correction_state_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $correction_state$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CORRECTION_STATE_RETAINED';
    END IF;

    IF ROW(NEW.original_journal_id, NEW.original_line_number, NEW.book_id, NEW.original_amount)
       IS DISTINCT FROM
       ROW(OLD.original_journal_id, OLD.original_line_number, OLD.book_id, OLD.original_amount)
       OR NEW.corrected_amount < OLD.corrected_amount
       OR NEW.version <> OLD.version + 1 THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CORRECTION_STATE_TRANSITION_INVALID';
    END IF;

    RETURN NEW;
END
$correction_state$;
REVOKE ALL ON FUNCTION jw_private.keep_journal_correction_state_v1() FROM PUBLIC;

CREATE TRIGGER journal_line_correction_state_monotonic
BEFORE UPDATE OR DELETE ON jw.journal_line_correction_state
FOR EACH ROW EXECUTE FUNCTION jw_private.keep_journal_correction_state_v1();
CREATE TRIGGER journal_line_correction_state_no_truncate
BEFORE TRUNCATE ON jw.journal_line_correction_state
FOR EACH STATEMENT EXECUTE FUNCTION jw_private.reject_immutable_row_v1();

CREATE FUNCTION jw_private.keep_journal_correction_limit_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $correction_limit$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CORRECTION_LIMIT_RETAINED';
    END IF;

    IF ROW(NEW.original_journal_id, NEW.book_id, NEW.policy_version, NEW.created_at)
       IS DISTINCT FROM
       ROW(OLD.original_journal_id, OLD.book_id, OLD.policy_version, OLD.created_at)
       OR NEW.version <> OLD.version + 1
       OR NEW.updated_at < OLD.updated_at
       OR (OLD.state = 'fully_corrected' AND NEW.state <> 'fully_corrected')
       OR (OLD.state = 'fully_corrected'
           AND NEW.full_reversal_journal_id IS DISTINCT FROM OLD.full_reversal_journal_id)
       OR (OLD.full_reversal_journal_id IS NOT NULL
           AND NEW.full_reversal_journal_id IS DISTINCT FROM OLD.full_reversal_journal_id)
       OR (OLD.state = 'restricted' AND NEW.state NOT IN ('restricted', 'eligible'))
       OR (OLD.state = 'eligible' AND NEW.state NOT IN ('eligible', 'partially_corrected', 'fully_corrected', 'restricted'))
       OR (OLD.state = 'partially_corrected' AND NEW.state NOT IN ('partially_corrected', 'fully_corrected', 'restricted')) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CORRECTION_LIMIT_TRANSITION_INVALID';
    END IF;

    RETURN NEW;
END
$correction_limit$;
REVOKE ALL ON FUNCTION jw_private.keep_journal_correction_limit_v1() FROM PUBLIC;

CREATE TRIGGER journal_correction_limits_versioned_history
BEFORE UPDATE OR DELETE ON jw.journal_correction_limits
FOR EACH ROW EXECUTE FUNCTION jw_private.keep_journal_correction_limit_v1();
CREATE TRIGGER journal_correction_limits_no_truncate
BEFORE TRUNCATE ON jw.journal_correction_limits
FOR EACH STATEMENT EXECUTE FUNCTION jw_private.reject_immutable_row_v1();

REVOKE ALL ON ALL TABLES IN SCHEMA jw FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA jw_api FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA jw_private FROM PUBLIC;
REVOKE CREATE ON SCHEMA jw, jw_api, jw_private, jw_support, public
    FROM PUBLIC, journalwick_runtime, journalwick_worker, journalwick_reporter;

CREATE FUNCTION jw_api.admit_operation_v1(
    p_book_id uuid,
    p_actor_id uuid,
    p_session_token_sha256 bytea,
    p_command_key_sha256 bytea,
    p_request jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $admit_operation$
DECLARE
    required_fields constant text[] := ARRAY[
        'schema_version', 'origin_namespace', 'business_key', 'family', 'family_version',
        'primary_currency_definition_id', 'requested_amount', 'intent_facts'
    ];
    allowed_fact_fields constant text[] := ARRAY[
        'source_account_id', 'target_account_id', 'safe_purpose_code'
    ];
    v_request_hash bytea;
    v_book_organization_id uuid;
    v_book_state text;
    v_principal_state text;
    v_human_state text;
    v_membership_id uuid;
    v_membership_state text;
    v_gate_mode text;
    v_normal_admission boolean;
    v_projection_status text;
    v_source_account_id uuid;
    v_target_account_id uuid;
    v_primary_currency_id uuid;
    v_source_currency_id uuid;
    v_target_currency_id uuid;
    v_source_classification text;
    v_target_classification text;
    v_source_normal_side text;
    v_target_normal_side text;
    v_source_spend_policy text;
    v_target_spend_policy text;
    v_requested_amount numeric(38, 0);
    v_origin_namespace text;
    v_business_key text;
    v_intent_facts jsonb;
    v_existing_receipt jw.command_receipts%ROWTYPE;
    v_existing_operation jw.business_operations%ROWTYPE;
    v_operation_id uuid;
    v_receipt_id uuid;
    v_reused boolean := false;
    v_read_allowed boolean;
BEGIN
    IF session_user <> 'journalwick_runtime' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'API_RUNTIME_IDENTITY_REQUIRED';
    END IF;
    IF p_book_id IS NULL
       OR p_actor_id IS NULL
       OR p_session_token_sha256 IS NULL
       OR octet_length(p_session_token_sha256) <> 32
       OR p_command_key_sha256 IS NULL
       OR octet_length(p_command_key_sha256) <> 32
       OR p_request IS NULL
       OR jsonb_typeof(p_request) <> 'object'
       OR octet_length(p_request::text) > 65536
       OR NOT (p_request ?& required_fields) THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'OPERATION_REQUEST_INVALID';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM jsonb_object_keys(p_request) AS fields(field_name)
        WHERE fields.field_name <> ALL (required_fields)
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'OPERATION_REQUEST_FIELD_UNSUPPORTED';
    END IF;

    IF jsonb_typeof(p_request -> 'schema_version') <> 'number'
       OR p_request ->> 'schema_version' <> '1'
       OR jsonb_typeof(p_request -> 'family') <> 'string'
       OR p_request ->> 'family' <> 'wallet_transfer'
       OR jsonb_typeof(p_request -> 'family_version') <> 'number'
       OR p_request ->> 'family_version' <> '1'
       OR jsonb_typeof(p_request -> 'origin_namespace') <> 'string'
       OR p_request ->> 'origin_namespace' <> 'console.wallet-transfer'
       OR jsonb_typeof(p_request -> 'business_key') <> 'string'
       OR char_length(p_request ->> 'business_key') NOT BETWEEN 1 AND 160
       OR (p_request ->> 'business_key') ~ '[[:cntrl:]]'
       OR jsonb_typeof(p_request -> 'primary_currency_definition_id') <> 'string'
       OR jsonb_typeof(p_request -> 'requested_amount') <> 'string'
       OR jsonb_typeof(p_request -> 'intent_facts') <> 'object' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'OPERATION_REQUEST_UNSUPPORTED';
    END IF;

    v_origin_namespace := p_request ->> 'origin_namespace';
    v_business_key := p_request ->> 'business_key';
    v_intent_facts := p_request -> 'intent_facts';
    v_requested_amount := jw_private.parse_positive_amount_v1(p_request ->> 'requested_amount');
    v_request_hash := jw_private.canonical_request_sha256_v1(
        'operation.admit', 1, p_book_id, NULL, NULL, p_request
    );

    IF NOT (v_intent_facts ?& ARRAY['source_account_id', 'target_account_id'])
       OR EXISTS (
           SELECT 1
           FROM jsonb_object_keys(v_intent_facts) AS fields(field_name)
           WHERE fields.field_name <> ALL (allowed_fact_fields)
       )
       OR jsonb_typeof(v_intent_facts -> 'source_account_id') <> 'string'
       OR jsonb_typeof(v_intent_facts -> 'target_account_id') <> 'string' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'WALLET_TRANSFER_INTENT_INVALID';
    END IF;

    IF v_intent_facts ? 'safe_purpose_code' THEN
        IF jsonb_typeof(v_intent_facts -> 'safe_purpose_code') <> 'string'
           OR char_length(v_intent_facts ->> 'safe_purpose_code') NOT BETWEEN 1 AND 64
           OR (v_intent_facts ->> 'safe_purpose_code') COLLATE "C" !~ '^[a-z][a-z0-9_.-]*$' THEN
            RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'WALLET_TRANSFER_PURPOSE_INVALID';
        END IF;
    END IF;

    BEGIN
        v_source_account_id := (v_intent_facts ->> 'source_account_id')::uuid;
        v_target_account_id := (v_intent_facts ->> 'target_account_id')::uuid;
        v_primary_currency_id := (p_request ->> 'primary_currency_definition_id')::uuid;
    EXCEPTION WHEN invalid_text_representation THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'OPERATION_REFERENCE_INVALID';
    END;

    IF v_source_account_id = v_target_account_id THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'WALLET_TRANSFER_ACCOUNTS_MUST_DIFFER';
    END IF;

    SELECT book.organization_id, book.state
    INTO v_book_organization_id, v_book_state
    FROM jw.books AS book
    WHERE book.id = p_book_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'BOOK_NOT_FOUND';
    END IF;

    SELECT principal.state, human.state
    INTO v_principal_state, v_human_state
    FROM jw.principals AS principal
    JOIN jw.human_users AS human ON human.principal_id = principal.id
    JOIN jw.native_sessions AS native_session
      ON native_session.principal_id = principal.id
     AND native_session.token_digest = p_session_token_sha256
    WHERE principal.id = p_actor_id
      AND native_session.state = 'active'
      AND native_session.authentication_method = 'passkey'
      AND native_session.principal_epoch = principal.authority_epoch
      AND native_session.absolute_expires_at > clock_timestamp()
      AND native_session.idle_expires_at > clock_timestamp();
    IF NOT FOUND
       OR v_principal_state <> 'active'
       OR v_human_state <> 'active' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CURRENT_SESSION_UNAVAILABLE';
    END IF;

    SELECT membership.id, membership.state
    INTO v_membership_id, v_membership_state
    FROM jw.organization_memberships AS membership
    WHERE membership.organization_id = v_book_organization_id
      AND membership.principal_id = p_actor_id;
    IF NOT FOUND OR v_membership_state <> 'active' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CURRENT_BOOK_AUTHORITY_REQUIRED';
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM jw.book_role_assignments AS assignment
        WHERE assignment.book_id = p_book_id
          AND assignment.organization_id = v_book_organization_id
          AND assignment.membership_id = v_membership_id
          AND assignment.state = 'active'
          AND assignment.role IN ('finance_operator', 'finance_reviewer', 'integration_operator', 'auditor')
          AND (assignment.expires_at IS NULL OR assignment.expires_at > clock_timestamp())
    )
    INTO v_read_allowed;
    IF NOT v_read_allowed THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CURRENT_BOOK_READ_AUTHORITY_REQUIRED';
    END IF;

    SELECT *
    INTO v_existing_receipt
    FROM jw.command_receipts AS receipt
    WHERE receipt.book_id = p_book_id
      AND receipt.actor_principal_id = p_actor_id
      AND receipt.command_family = 'operation.admit'
      AND receipt.command_key_sha256 = p_command_key_sha256;
    IF FOUND THEN
        SELECT principal.state, human.state
        INTO v_principal_state, v_human_state
        FROM jw.principals AS principal
        JOIN jw.human_users AS human ON human.principal_id = principal.id
        JOIN jw.native_sessions AS native_session
          ON native_session.principal_id = principal.id
         AND native_session.token_digest = p_session_token_sha256
        WHERE principal.id = p_actor_id
          AND native_session.state = 'active'
          AND native_session.authentication_method = 'passkey'
          AND native_session.principal_epoch = principal.authority_epoch
          AND native_session.absolute_expires_at > clock_timestamp()
          AND native_session.idle_expires_at > clock_timestamp()
        FOR SHARE OF principal, human, native_session;
        IF NOT FOUND
           OR v_principal_state <> 'active'
           OR v_human_state <> 'active' THEN
            RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CURRENT_SESSION_UNAVAILABLE';
        END IF;

        PERFORM 1
        FROM jw.organization_memberships AS membership
        WHERE membership.organization_id = v_book_organization_id
          AND membership.principal_id = p_actor_id
          AND membership.state = 'active'
        FOR SHARE;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CURRENT_BOOK_READ_AUTHORITY_REQUIRED';
        END IF;

        PERFORM 1
        FROM jw.book_role_assignments AS assignment
        WHERE assignment.book_id = p_book_id
          AND assignment.organization_id = v_book_organization_id
          AND assignment.membership_id = v_membership_id
          AND assignment.state = 'active'
          AND assignment.role IN ('finance_operator', 'finance_reviewer', 'integration_operator', 'auditor')
          AND (assignment.expires_at IS NULL OR assignment.expires_at > clock_timestamp())
        FOR SHARE;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CURRENT_BOOK_READ_AUTHORITY_REQUIRED';
        END IF;

        IF v_existing_receipt.canonical_request_sha256 <> v_request_hash THEN
            RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'IDEMPOTENCY_CONFLICT';
        END IF;
        IF v_existing_receipt.state <> 'accepted'
           OR v_existing_receipt.result_kind <> 'operation' THEN
            RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'OPERATION_RESULT_UNAVAILABLE';
        END IF;

        SELECT *
        INTO v_existing_operation
        FROM jw.business_operations AS operation
        WHERE operation.id = v_existing_receipt.result_id
          AND operation.book_id = p_book_id
        FOR SHARE;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'OPERATION_RESULT_UNAVAILABLE';
        END IF;

        RETURN jsonb_build_object(
            'command_receipt_id', v_existing_receipt.id,
            'operation_id', v_existing_operation.id,
            'execution_state', v_existing_operation.execution_state,
            'financial_status', v_existing_operation.financial_status,
            'version', v_existing_operation.version,
            'reused', true
        );
    END IF;

    SELECT mode, normal_financial_admission
    INTO v_gate_mode, v_normal_admission
    FROM jw.installation_operating_state
    WHERE singleton = true
    FOR SHARE;
    IF NOT FOUND OR v_gate_mode <> 'normal' OR NOT v_normal_admission THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FINANCIAL_ADMISSION_CLOSED';
    END IF;

    SELECT principal.state, human.state
    INTO v_principal_state, v_human_state
    FROM jw.principals AS principal
    JOIN jw.human_users AS human ON human.principal_id = principal.id
    JOIN jw.native_sessions AS native_session
      ON native_session.principal_id = principal.id
     AND native_session.token_digest = p_session_token_sha256
    WHERE principal.id = p_actor_id
      AND native_session.state = 'active'
      AND native_session.authentication_method = 'passkey'
      AND native_session.principal_epoch = principal.authority_epoch
      AND native_session.absolute_expires_at > clock_timestamp()
      AND native_session.idle_expires_at > clock_timestamp()
    FOR SHARE OF principal, human, native_session;
    IF NOT FOUND
       OR v_principal_state <> 'active'
       OR v_human_state <> 'active' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CURRENT_SESSION_UNAVAILABLE';
    END IF;

    SELECT membership.id, membership.state
    INTO v_membership_id, v_membership_state
    FROM jw.organization_memberships AS membership
    WHERE membership.organization_id = v_book_organization_id
      AND membership.principal_id = p_actor_id
    FOR SHARE;
    IF NOT FOUND OR v_membership_state <> 'active' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CURRENT_BOOK_AUTHORITY_REQUIRED';
    END IF;

    PERFORM 1
    FROM jw.book_role_assignments AS assignment
    WHERE assignment.book_id = p_book_id
      AND assignment.organization_id = v_book_organization_id
      AND assignment.membership_id = v_membership_id
      AND assignment.role = 'finance_operator'
      AND assignment.state = 'active'
      AND (assignment.expires_at IS NULL OR assignment.expires_at > clock_timestamp())
    FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'FINANCE_OPERATOR_REQUIRED';
    END IF;

    SELECT projection_status
    INTO v_projection_status
    FROM jw.book_financial_state
    WHERE book_id = p_book_id
      AND organization_id = v_book_organization_id
    FOR UPDATE;
    IF NOT FOUND OR v_projection_status <> 'current' THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'BOOK_PROJECTION_UNAVAILABLE';
    END IF;

    SELECT book.state
    INTO v_book_state
    FROM jw.books AS book
    WHERE book.id = p_book_id
      AND book.organization_id = v_book_organization_id;
    IF v_book_state <> 'active'
       OR EXISTS (
           SELECT 1
           FROM jw.book_lifecycle_restrictions AS restriction
           WHERE restriction.book_id = p_book_id
             AND restriction.state = 'active'
       ) THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'BOOK_FINANCIAL_ADMISSION_DENIED';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM jw.currency_definitions AS currency
        WHERE currency.id = v_primary_currency_id
          AND currency.state = 'active'
    ) THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'CURRENCY_DEFINITION_UNAVAILABLE';
    END IF;

    SELECT currency_definition_id, classification, normal_side, spend_policy
    INTO v_source_currency_id, v_source_classification, v_source_normal_side, v_source_spend_policy
    FROM jw.accounts
    WHERE id = v_source_account_id
      AND book_id = p_book_id
      AND state = 'active';
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'SOURCE_ACCOUNT_UNAVAILABLE';
    END IF;

    SELECT currency_definition_id, classification, normal_side, spend_policy
    INTO v_target_currency_id, v_target_classification, v_target_normal_side, v_target_spend_policy
    FROM jw.accounts
    WHERE id = v_target_account_id
      AND book_id = p_book_id
      AND state = 'active';
    IF NOT FOUND
       OR v_source_currency_id <> v_target_currency_id
       OR v_source_currency_id <> v_primary_currency_id
       OR v_source_classification <> 'liability'
       OR v_target_classification <> 'liability'
       OR v_source_normal_side <> 'credit'
       OR v_target_normal_side <> 'credit'
       OR v_source_spend_policy <> 'protected_customer_liability'
       OR v_target_spend_policy <> 'protected_customer_liability' THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'WALLET_TRANSFER_ACCOUNT_SCOPE_INVALID';
    END IF;

    SELECT *
    INTO v_existing_receipt
    FROM jw.command_receipts AS receipt
    WHERE receipt.book_id = p_book_id
      AND receipt.actor_principal_id = p_actor_id
      AND receipt.command_family = 'operation.admit'
      AND receipt.command_key_sha256 = p_command_key_sha256
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing_receipt.canonical_request_sha256 <> v_request_hash THEN
            RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'IDEMPOTENCY_CONFLICT';
        END IF;
        IF v_existing_receipt.state <> 'accepted'
           OR v_existing_receipt.result_kind <> 'operation' THEN
            RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'OPERATION_RESULT_UNAVAILABLE';
        END IF;

        SELECT *
        INTO v_existing_operation
        FROM jw.business_operations AS operation
        WHERE operation.id = v_existing_receipt.result_id
          AND operation.book_id = p_book_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'OPERATION_RESULT_UNAVAILABLE';
        END IF;

        RETURN jsonb_build_object(
            'command_receipt_id', v_existing_receipt.id,
            'operation_id', v_existing_operation.id,
            'execution_state', v_existing_operation.execution_state,
            'financial_status', v_existing_operation.financial_status,
            'version', v_existing_operation.version,
            'reused', true
        );
    END IF;

    SELECT *
    INTO v_existing_operation
    FROM jw.business_operations AS operation
    WHERE operation.book_id = p_book_id
      AND operation.origin_namespace = v_origin_namespace
      AND operation.business_key = v_business_key
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing_operation.request_sha256 <> v_request_hash THEN
            RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'BUSINESS_IDENTITY_CONFLICT';
        END IF;
        v_operation_id := v_existing_operation.id;
        v_reused := true;
    ELSE
        INSERT INTO jw.business_operations (
            book_id,
            organization_id,
            family,
            family_version,
            origin_namespace,
            business_key,
            request_sha256,
            primary_currency_definition_id,
            requested_amount,
            intent_facts,
            created_by
        )
        VALUES (
            p_book_id,
            v_book_organization_id,
            'wallet_transfer',
            1,
            v_origin_namespace,
            v_business_key,
            v_request_hash,
            v_primary_currency_id,
            v_requested_amount,
            v_intent_facts,
            p_actor_id
        )
        RETURNING id INTO v_operation_id;
    END IF;

    INSERT INTO jw.command_receipts (
        book_id,
        actor_principal_id,
        command_family,
        command_key_sha256,
        canonical_request_sha256,
        operation_id,
        result_kind,
        result_id,
        state,
        accepted_at
    )
    VALUES (
        p_book_id,
        p_actor_id,
        'operation.admit',
        p_command_key_sha256,
        v_request_hash,
        v_operation_id,
        'operation',
        v_operation_id,
        'accepted',
        clock_timestamp()
    )
    RETURNING id INTO v_receipt_id;

    INSERT INTO jw.audit_events (
        organization_id,
        book_id,
        actor_principal_id,
        actor_kind,
        action,
        target_kind,
        target_id,
        outcome,
        request_id,
        command_receipt_id,
        event_schema_version,
        safe_payload
    )
    VALUES (
        v_book_organization_id,
        p_book_id,
        p_actor_id,
        'human',
        CASE WHEN v_reused THEN 'operation.identity_reused' ELSE 'operation.admit' END,
        'business_operation',
        v_operation_id,
        'accepted',
        gen_random_uuid()::text,
        v_receipt_id,
        1,
        jsonb_build_object(
            'family', 'wallet_transfer',
            'family_version', 1,
            'origin_namespace', v_origin_namespace,
            'business_key', v_business_key,
            'reused', v_reused
        )
    );

    SELECT *
    INTO v_existing_operation
    FROM jw.business_operations AS operation
    WHERE operation.id = v_operation_id
      AND operation.book_id = p_book_id;

    RETURN jsonb_build_object(
        'command_receipt_id', v_receipt_id,
        'operation_id', v_existing_operation.id,
        'execution_state', v_existing_operation.execution_state,
        'financial_status', v_existing_operation.financial_status,
        'version', v_existing_operation.version,
        'reused', v_reused
    );
END
$admit_operation$;
REVOKE ALL ON FUNCTION jw_api.admit_operation_v1(uuid, uuid, bytea, bytea, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION jw_api.admit_operation_v1(uuid, uuid, bytea, bytea, jsonb)
    TO journalwick_runtime;

CREATE FUNCTION jw_private.jsonb_object_count_v1(p_value jsonb)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog, pg_temp
AS $jsonb_object_count$
BEGIN
    IF p_value IS NULL OR jsonb_typeof(p_value) <> 'object' THEN
        RETURN -1;
    END IF;

    RETURN (SELECT count(*)::integer FROM jsonb_object_keys(p_value));
END
$jsonb_object_count$;
REVOKE ALL ON FUNCTION jw_private.jsonb_object_count_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION jw_private.expand_wallet_transfer_v1(
    p_book_id uuid,
    p_operation_id uuid,
    p_template_id uuid,
    p_template_version integer,
    p_proposed_lines jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
AS $wallet_template$
DECLARE
    v_operation jw.business_operations%ROWTYPE;
    v_template_version jw.posting_template_versions%ROWTYPE;
    v_payload jsonb;
    v_source_role jsonb;
    v_target_role jsonb;
    v_parameter jsonb;
    v_line jsonb;
    v_source_id uuid;
    v_target_id uuid;
    v_currency_id uuid;
    v_source_state text;
    v_target_state text;
    v_source_classification text;
    v_target_classification text;
    v_source_normal_side text;
    v_target_normal_side text;
    v_source_spend_policy text;
    v_target_spend_policy text;
    v_minimum numeric(38, 0);
    v_maximum numeric(38, 0);
    v_expected_lines jsonb;
    v_proposed_without_descriptions jsonb;
    v_payload_fields constant text[] := ARRAY[
        'schema_version', 'operation_family', 'currency_roles', 'account_roles',
        'parameters', 'evidence_policy', 'approval_class', 'lines', 'execution_constraints'
    ];
    v_account_role_fields constant text[] := ARRAY[
        'currency_role', 'classification', 'normal_side', 'spend_policy', 'selector', 'allowed_states'
    ];
BEGIN
    SELECT *
    INTO v_operation
    FROM jw.business_operations AS operation
    WHERE operation.id = p_operation_id
      AND operation.book_id = p_book_id;
    IF NOT FOUND
       OR v_operation.family <> 'wallet_transfer'
       OR v_operation.family_version <> 1 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'POSTING_TEMPLATE_FAMILY_UNSUPPORTED';
    END IF;

    SELECT template_version.*
    INTO v_template_version
    FROM jw.posting_template_versions AS template_version
    JOIN jw.posting_templates AS posting_template
      ON posting_template.id = template_version.template_id
     AND posting_template.book_id = template_version.book_id
    WHERE template_version.template_id = p_template_id
      AND template_version.version = p_template_version
      AND template_version.book_id = p_book_id
      AND posting_template.state = 'active';
    IF NOT FOUND
       OR v_template_version.approved_at IS NULL
       OR v_template_version.payload_schema_version <> 1 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'POSTING_TEMPLATE_VERSION_UNAVAILABLE';
    END IF;

    IF v_template_version.payload_sha256 IS DISTINCT FROM
       jw_private.posting_template_payload_sha256_v1(
           p_template_id,
           p_template_version,
           p_book_id,
           v_template_version.payload
       ) THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'POSTING_TEMPLATE_HASH_MISMATCH';
    END IF;

    v_payload := v_template_version.payload;
    IF jsonb_typeof(v_payload -> 'parameters') IS DISTINCT FROM 'array'
       OR jsonb_typeof(v_payload -> 'lines') IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'WALLET_TRANSFER_TEMPLATE_UNSUPPORTED';
    END IF;
    IF jw_private.jsonb_object_count_v1(v_payload) <> cardinality(v_payload_fields)
       OR EXISTS (
           SELECT 1
           FROM jsonb_object_keys(v_payload) AS fields(field_name)
           WHERE fields.field_name <> ALL (v_payload_fields)
       )
       OR NOT (v_payload ?& v_payload_fields)
       OR jsonb_typeof(v_payload -> 'schema_version') <> 'number'
       OR v_payload ->> 'schema_version' IS DISTINCT FROM '1'
       OR v_payload ->> 'operation_family' IS DISTINCT FROM 'wallet_transfer'
       OR v_payload ->> 'approval_class' IS DISTINCT FROM 'manual_distinct_reviewer'
       OR v_payload -> 'evidence_policy' <> '{"kind":"authorized_internal_intent"}'::jsonb
       OR v_payload -> 'currency_roles'
            <> '{"payment":{"source":"operation_primary_currency"}}'::jsonb
       OR jw_private.jsonb_object_count_v1(v_payload -> 'account_roles') <> 2
       OR NOT ((v_payload -> 'account_roles') ?& ARRAY['source_wallet', 'target_wallet'])
       OR jsonb_array_length(v_payload -> 'parameters') <> 1
       OR jsonb_array_length(v_payload -> 'lines') <> 2
       OR v_payload -> 'execution_constraints'
            <> '{"distinct_account_roles":[["source_wallet","target_wallet"]],"requires_active_book":true,"requires_current_projection":true}'::jsonb THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'WALLET_TRANSFER_TEMPLATE_UNSUPPORTED';
    END IF;

    v_source_role := v_payload -> 'account_roles' -> 'source_wallet';
    v_target_role := v_payload -> 'account_roles' -> 'target_wallet';
    IF jsonb_typeof(v_source_role) IS DISTINCT FROM 'object'
       OR jsonb_typeof(v_target_role) IS DISTINCT FROM 'object' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'WALLET_TRANSFER_ACCOUNT_ROLES_UNSUPPORTED';
    END IF;
    IF jw_private.jsonb_object_count_v1(v_source_role) <> cardinality(v_account_role_fields)
       OR jw_private.jsonb_object_count_v1(v_target_role) <> cardinality(v_account_role_fields)
       OR EXISTS (
           SELECT 1
           FROM jsonb_object_keys(v_source_role) AS fields(field_name)
           WHERE fields.field_name <> ALL (v_account_role_fields)
       )
       OR EXISTS (
           SELECT 1
           FROM jsonb_object_keys(v_target_role) AS fields(field_name)
           WHERE fields.field_name <> ALL (v_account_role_fields)
       )
       OR v_source_role ->> 'currency_role' IS DISTINCT FROM 'payment'
       OR v_target_role ->> 'currency_role' IS DISTINCT FROM 'payment'
       OR v_source_role ->> 'classification' IS DISTINCT FROM 'liability'
       OR v_target_role ->> 'classification' IS DISTINCT FROM 'liability'
       OR v_source_role ->> 'normal_side' IS DISTINCT FROM 'credit'
       OR v_target_role ->> 'normal_side' IS DISTINCT FROM 'credit'
       OR v_source_role ->> 'spend_policy' IS DISTINCT FROM 'protected_customer_liability'
       OR v_target_role ->> 'spend_policy' IS DISTINCT FROM 'protected_customer_liability'
       OR v_source_role -> 'allowed_states' <> '["active"]'::jsonb
       OR v_target_role -> 'allowed_states' <> '["active"]'::jsonb
       OR v_source_role -> 'selector'
            <> '{"kind":"intent_account","field":"source_account_id"}'::jsonb
       OR v_target_role -> 'selector'
            <> '{"kind":"intent_account","field":"target_account_id"}'::jsonb THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'WALLET_TRANSFER_ACCOUNT_ROLES_UNSUPPORTED';
    END IF;

    v_parameter := v_payload -> 'parameters' -> 0;
    IF jsonb_typeof(v_parameter) IS DISTINCT FROM 'object' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'WALLET_TRANSFER_PARAMETER_UNSUPPORTED';
    END IF;
    IF jw_private.jsonb_object_count_v1(v_parameter) <> 6
       OR EXISTS (
           SELECT 1
           FROM jsonb_object_keys(v_parameter) AS fields(field_name)
           WHERE fields.field_name <> ALL (
               ARRAY['name', 'type', 'currency_role', 'minimum', 'maximum', 'trusted_source']
           )
       )
       OR v_parameter ->> 'name' IS DISTINCT FROM 'transfer_amount'
       OR v_parameter ->> 'type' IS DISTINCT FROM 'amount'
       OR v_parameter ->> 'currency_role' IS DISTINCT FROM 'payment'
       OR v_parameter ->> 'trusted_source' IS DISTINCT FROM 'operation_amount'
       OR jsonb_typeof(v_parameter -> 'minimum') <> 'string'
       OR jsonb_typeof(v_parameter -> 'maximum') <> 'string' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'WALLET_TRANSFER_PARAMETER_UNSUPPORTED';
    END IF;

    v_minimum := jw_private.parse_positive_amount_v1(v_parameter ->> 'minimum');
    v_maximum := jw_private.parse_positive_amount_v1(v_parameter ->> 'maximum');
    IF v_minimum > v_maximum
       OR v_operation.requested_amount < v_minimum
       OR v_operation.requested_amount > v_maximum THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'OPERATION_AMOUNT_OUTSIDE_TEMPLATE_LIMIT';
    END IF;

    FOR v_line IN SELECT value FROM jsonb_array_elements(v_payload -> 'lines')
    LOOP
        IF jsonb_typeof(v_line) IS DISTINCT FROM 'object' THEN
            RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'WALLET_TRANSFER_LINE_TEMPLATE_INVALID';
        END IF;
        IF jw_private.jsonb_object_count_v1(v_line) <> 4
           OR EXISTS (
               SELECT 1
               FROM jsonb_object_keys(v_line) AS fields(field_name)
               WHERE fields.field_name <> ALL (ARRAY['role', 'side', 'amount', 'omit_if_zero'])
           )
           OR jsonb_typeof(v_line -> 'amount') <> 'object'
           OR v_line -> 'amount' <> '{"op":"amount_param","name":"transfer_amount"}'::jsonb
           OR jsonb_typeof(v_line -> 'omit_if_zero') <> 'boolean'
           OR v_line ->> 'omit_if_zero' IS DISTINCT FROM 'false' THEN
            RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'WALLET_TRANSFER_LINE_TEMPLATE_INVALID';
        END IF;
    END LOOP;

    IF v_payload -> 'lines' -> 0 ->> 'role' IS DISTINCT FROM 'source_wallet'
       OR v_payload -> 'lines' -> 0 ->> 'side' IS DISTINCT FROM 'debit'
       OR v_payload -> 'lines' -> 1 ->> 'role' IS DISTINCT FROM 'target_wallet'
       OR v_payload -> 'lines' -> 1 ->> 'side' IS DISTINCT FROM 'credit' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'WALLET_TRANSFER_LINE_TEMPLATE_INVALID';
    END IF;

    BEGIN
        v_source_id := (v_operation.intent_facts ->> 'source_account_id')::uuid;
        v_target_id := (v_operation.intent_facts ->> 'target_account_id')::uuid;
    EXCEPTION WHEN invalid_text_representation THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'WALLET_TRANSFER_INTENT_INVALID';
    END;

    IF v_source_id = v_target_id THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'WALLET_TRANSFER_ACCOUNTS_MUST_DIFFER';
    END IF;

    SELECT account.state, account.classification, account.normal_side,
           account.spend_policy, account.currency_definition_id
    INTO v_source_state, v_source_classification, v_source_normal_side,
         v_source_spend_policy, v_currency_id
    FROM jw.accounts AS account
    WHERE account.id = v_source_id
      AND account.book_id = p_book_id;
    IF NOT FOUND
       OR v_source_state <> 'active'
       OR v_source_classification <> 'liability'
       OR v_source_normal_side <> 'credit'
       OR v_source_spend_policy <> 'protected_customer_liability'
       OR v_currency_id <> v_operation.primary_currency_definition_id THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'WALLET_TRANSFER_SOURCE_ACCOUNT_INVALID';
    END IF;

    SELECT account.state, account.classification, account.normal_side,
           account.spend_policy, account.currency_definition_id
    INTO v_target_state, v_target_classification, v_target_normal_side,
         v_target_spend_policy, v_currency_id
    FROM jw.accounts AS account
    WHERE account.id = v_target_id
      AND account.book_id = p_book_id;
    IF NOT FOUND
       OR v_target_state <> 'active'
       OR v_target_classification <> 'liability'
       OR v_target_normal_side <> 'credit'
       OR v_target_spend_policy <> 'protected_customer_liability'
       OR v_currency_id <> v_operation.primary_currency_definition_id THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'WALLET_TRANSFER_TARGET_ACCOUNT_INVALID';
    END IF;

    v_expected_lines := jsonb_build_array(
        jsonb_build_object(
            'account_id', v_source_id,
            'currency_definition_id', v_operation.primary_currency_definition_id,
            'side', 'debit',
            'amount', v_operation.requested_amount::text,
            'template_role', 'source_wallet'
        ),
        jsonb_build_object(
            'account_id', v_target_id,
            'currency_definition_id', v_operation.primary_currency_definition_id,
            'side', 'credit',
            'amount', v_operation.requested_amount::text,
            'template_role', 'target_wallet'
        )
    );

    PERFORM jw_private.validate_canonical_lines_v1(p_proposed_lines);
    SELECT jsonb_agg(line.value - 'safe_description' ORDER BY line.ordinality)
    INTO v_proposed_without_descriptions
    FROM jsonb_array_elements(p_proposed_lines) WITH ORDINALITY AS line(value, ordinality);
    IF v_proposed_without_descriptions IS DISTINCT FROM v_expected_lines THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'PROPOSAL_LINES_DO_NOT_MATCH_TEMPLATE';
    END IF;

    RETURN v_expected_lines;
END
$wallet_template$;
REVOKE ALL ON FUNCTION jw_private.expand_wallet_transfer_v1(uuid, uuid, uuid, integer, jsonb)
    FROM PUBLIC;

CREATE FUNCTION jw_api.post_proposal_v1(
    p_book_id uuid,
    p_actor_id uuid,
    p_session_token_sha256 bytea,
    p_command_key_sha256 bytea,
    p_request jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $post_proposal$
DECLARE
    required_fields constant text[] := ARRAY[
        'schema_version', 'operation_id', 'step_key', 'proposal_id', 'proposal_version',
        'payload_sha256', 'expected_operation_version', 'expected_proposal_envelope_version'
    ];
    v_operation_id uuid;
    v_step_key text;
    v_step_id uuid;
    v_proposal_id uuid;
    v_proposal_version bigint;
    v_expected_operation_version bigint;
    v_expected_proposal_version bigint;
    v_payload_hash bytea;
    v_request_hash bytea;
    v_book_organization_id uuid;
    v_book_state text;
    v_operation jw.business_operations%ROWTYPE;
    v_step jw.operation_steps%ROWTYPE;
    v_proposal jw.posting_proposals%ROWTYPE;
    v_proposal_payload jw.posting_proposal_versions%ROWTYPE;
    v_template_id uuid;
    v_template_version integer;
    v_template_payload_sha256 bytea;
    v_template_state text;
    v_proposal_creator uuid;
    v_approval_id uuid;
    v_reviewer_id uuid;
    v_reviewer_membership_version bigint;
    v_authority_ids uuid[];
    v_membership_ids uuid[];
    v_membership record;
    v_assignment record;
    v_approval jw.proposal_approvals%ROWTYPE;
    v_template_version_row jw.posting_template_versions%ROWTYPE;
    v_locked_principal_id uuid;
    v_locked_account_id uuid;
    v_locked_count integer := 0;
    v_actor_membership_id uuid;
    v_actor_membership_version bigint;
    v_reviewer_membership_id uuid;
    v_reviewer_current_membership_version bigint;
    v_actor_has_operator boolean := false;
    v_reviewer_has_role boolean := false;
    v_session_recent_uv_at timestamptz;
    v_session_operation_sha256 bytea;
    v_gate_mode text;
    v_financial_admission boolean;
    v_projection_status text;
    v_book_journal_sequence bigint;
    v_book_state_sequence bigint;
    v_journal_sequence bigint;
    v_state_sequence bigint;
    v_period_id uuid;
    v_effective_date date;
    v_period_state text;
    v_period_starts_on date;
    v_period_ends_before date;
    v_approved_reviewers uuid[];
    v_current_reviewers uuid[];
    v_expected_lines jsonb;
    v_proposed_without_descriptions jsonb;
    v_account_ids uuid[];
    v_account_record record;
    v_account_locked_count integer := 0;
    v_financial_locked_count integer := 0;
    v_debit_delta numeric(38, 0);
    v_credit_delta numeric(38, 0);
    v_debit_after numeric;
    v_credit_after numeric;
    v_available_after numeric;
    v_line jsonb;
    v_original_line jsonb;
    v_line_number integer;
    v_amount numeric(38, 0);
    v_journal_id uuid;
    v_receipt_id uuid;
    v_receipt jw.command_receipts%ROWTYPE;
    v_result_journal_sequence bigint;
    v_result_state_sequence bigint;
    v_result_operation_version bigint;
BEGIN
    IF session_user <> 'journalwick_runtime' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'API_RUNTIME_IDENTITY_REQUIRED';
    END IF;
    IF p_book_id IS NULL
       OR p_actor_id IS NULL
       OR p_session_token_sha256 IS NULL
       OR octet_length(p_session_token_sha256) <> 32
       OR p_command_key_sha256 IS NULL
       OR octet_length(p_command_key_sha256) <> 32
       OR p_request IS NULL
       OR jsonb_typeof(p_request) <> 'object'
       OR octet_length(p_request::text) > 65536
       OR NOT (p_request ?& required_fields) THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'POST_PROPOSAL_REQUEST_INVALID';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM jsonb_object_keys(p_request) AS fields(field_name)
        WHERE fields.field_name <> ALL (required_fields)
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'POST_PROPOSAL_FIELD_UNSUPPORTED';
    END IF;

    IF jsonb_typeof(p_request -> 'schema_version') <> 'number'
       OR p_request ->> 'schema_version' <> '1'
       OR jsonb_typeof(p_request -> 'operation_id') <> 'string'
       OR jsonb_typeof(p_request -> 'step_key') <> 'string'
       OR jsonb_typeof(p_request -> 'proposal_id') <> 'string'
       OR jsonb_typeof(p_request -> 'proposal_version') <> 'number'
       OR jsonb_typeof(p_request -> 'payload_sha256') <> 'string'
       OR jsonb_typeof(p_request -> 'expected_operation_version') <> 'number'
       OR jsonb_typeof(p_request -> 'expected_proposal_envelope_version') <> 'number'
       OR p_request ->> 'proposal_version' COLLATE "C" !~ '^[1-9][0-9]{0,17}$'
       OR p_request ->> 'expected_operation_version' COLLATE "C" !~ '^[1-9][0-9]{0,17}$'
       OR p_request ->> 'expected_proposal_envelope_version' COLLATE "C" !~ '^[1-9][0-9]{0,17}$'
       OR p_request ->> 'payload_sha256' COLLATE "C" !~ '^[0-9a-f]{64}$'
       OR char_length(p_request ->> 'step_key') NOT BETWEEN 1 AND 100
       OR (p_request ->> 'step_key') COLLATE "C" !~ '^[A-Za-z0-9][A-Za-z0-9_.:-]*$' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'POST_PROPOSAL_REQUEST_UNSUPPORTED';
    END IF;

    BEGIN
        v_operation_id := (p_request ->> 'operation_id')::uuid;
        v_proposal_id := (p_request ->> 'proposal_id')::uuid;
        v_payload_hash := decode(p_request ->> 'payload_sha256', 'hex');
        v_proposal_version := (p_request ->> 'proposal_version')::bigint;
        v_expected_operation_version := (p_request ->> 'expected_operation_version')::bigint;
        v_expected_proposal_version := (p_request ->> 'expected_proposal_envelope_version')::bigint;
    EXCEPTION WHEN invalid_text_representation THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'POST_PROPOSAL_REFERENCE_INVALID';
    END;
    v_step_key := p_request ->> 'step_key';

    PERFORM 1
    FROM jw.principals AS principal
    JOIN jw.human_users AS human ON human.principal_id = principal.id
    JOIN jw.native_sessions AS native_session
      ON native_session.principal_id = principal.id
     AND native_session.token_digest = p_session_token_sha256
    WHERE principal.id = p_actor_id
      AND principal.state = 'active'
      AND human.state = 'active'
      AND native_session.state = 'active'
      AND native_session.authentication_method = 'passkey'
      AND native_session.principal_epoch = principal.authority_epoch
      AND native_session.absolute_expires_at > clock_timestamp()
      AND native_session.idle_expires_at > clock_timestamp();
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CURRENT_SESSION_UNAVAILABLE';
    END IF;

    SELECT book.organization_id
    INTO v_book_organization_id
    FROM jw.books AS book
    WHERE book.id = p_book_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CURRENT_BOOK_READ_AUTHORITY_REQUIRED';
    END IF;

    SELECT membership.id
    INTO v_actor_membership_id
    FROM jw.organization_memberships AS membership
    WHERE membership.organization_id = v_book_organization_id
      AND membership.principal_id = p_actor_id
      AND membership.state = 'active';
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CURRENT_BOOK_AUTHORITY_REQUIRED';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM jw.book_role_assignments AS assignment
        WHERE assignment.book_id = p_book_id
          AND assignment.organization_id = v_book_organization_id
          AND assignment.membership_id = v_actor_membership_id
          AND assignment.state = 'active'
          AND assignment.role IN ('finance_operator', 'finance_reviewer', 'integration_operator', 'auditor')
          AND (assignment.expires_at IS NULL OR assignment.expires_at > clock_timestamp())
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CURRENT_BOOK_READ_AUTHORITY_REQUIRED';
    END IF;

    SELECT step.id
    INTO v_step_id
    FROM jw.operation_steps AS step
    WHERE step.operation_id = v_operation_id
      AND step.book_id = p_book_id
      AND step.step_key = v_step_key;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'OPERATION_STEP_NOT_FOUND';
    END IF;

    v_request_hash := jw_private.canonical_request_sha256_v1(
        'journal.post', 1, p_book_id, v_operation_id, v_step_id, p_request
    );

    SELECT *
    INTO v_receipt
    FROM jw.command_receipts AS receipt
    WHERE receipt.book_id = p_book_id
      AND receipt.actor_principal_id = p_actor_id
      AND receipt.command_family = 'journal.post'
      AND receipt.command_key_sha256 = p_command_key_sha256;
    IF FOUND THEN
        PERFORM 1
        FROM jw.principals AS principal
        JOIN jw.human_users AS human ON human.principal_id = principal.id
        JOIN jw.native_sessions AS native_session
          ON native_session.principal_id = principal.id
         AND native_session.token_digest = p_session_token_sha256
        WHERE principal.id = p_actor_id
          AND principal.state = 'active'
          AND human.state = 'active'
          AND native_session.state = 'active'
          AND native_session.authentication_method = 'passkey'
          AND native_session.principal_epoch = principal.authority_epoch
          AND native_session.absolute_expires_at > clock_timestamp()
          AND native_session.idle_expires_at > clock_timestamp()
        FOR SHARE OF principal, human, native_session;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CURRENT_SESSION_UNAVAILABLE';
        END IF;

        PERFORM 1
        FROM jw.organization_memberships AS membership
        WHERE membership.id = v_actor_membership_id
          AND membership.state = 'active'
        FOR SHARE;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CURRENT_BOOK_READ_AUTHORITY_REQUIRED';
        END IF;
        PERFORM 1
        FROM jw.book_role_assignments AS assignment
        WHERE assignment.book_id = p_book_id
          AND assignment.organization_id = v_book_organization_id
          AND assignment.membership_id = v_actor_membership_id
          AND assignment.state = 'active'
          AND assignment.role IN ('finance_operator', 'finance_reviewer', 'integration_operator', 'auditor')
          AND (assignment.expires_at IS NULL OR assignment.expires_at > clock_timestamp())
        FOR SHARE;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CURRENT_BOOK_READ_AUTHORITY_REQUIRED';
        END IF;

        IF v_receipt.canonical_request_sha256 <> v_request_hash THEN
            RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'IDEMPOTENCY_CONFLICT';
        END IF;
        IF v_receipt.state <> 'accepted'
           OR v_receipt.result_kind <> 'journal' THEN
            RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'JOURNAL_RESULT_UNAVAILABLE';
        END IF;

        SELECT journal.journal_sequence, journal.state_sequence
        INTO v_result_journal_sequence, v_result_state_sequence
        FROM jw.journals AS journal
        WHERE journal.id = v_receipt.result_id
          AND journal.book_id = p_book_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'JOURNAL_RESULT_UNAVAILABLE';
        END IF;
        RETURN jsonb_build_object(
            'command_receipt_id', v_receipt.id,
            'operation_id', v_receipt.operation_id,
            'step_id', v_receipt.step_id,
            'result_kind', 'journal',
            'result_id', v_receipt.result_id,
            'journal_sequence', v_result_journal_sequence,
            'state_sequence', v_result_state_sequence,
            'reused', true
        );
    END IF;

    SELECT mode, normal_financial_admission
    INTO v_gate_mode, v_financial_admission
    FROM jw.installation_operating_state
    WHERE singleton = true
    FOR SHARE;
    IF NOT FOUND OR v_gate_mode <> 'normal' OR NOT v_financial_admission THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FINANCIAL_ADMISSION_CLOSED';
    END IF;

    SELECT operation.*
    INTO v_operation
    FROM jw.business_operations AS operation
    WHERE operation.id = v_operation_id
      AND operation.book_id = p_book_id;
    SELECT proposal.*
    INTO v_proposal
    FROM jw.posting_proposals AS proposal
    WHERE proposal.id = v_proposal_id
      AND proposal.book_id = p_book_id
      AND proposal.operation_step_id = v_step_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'POSTING_PROPOSAL_NOT_FOUND';
    END IF;

    SELECT proposal_version.*
    INTO v_proposal_payload
    FROM jw.posting_proposal_versions AS proposal_version
    WHERE proposal_version.proposal_id = v_proposal_id
      AND proposal_version.proposal_version = v_proposal_version
      AND proposal_version.book_id = p_book_id;
    IF NOT FOUND
       OR v_proposal_payload.payload_sha256 IS DISTINCT FROM v_payload_hash
       OR v_proposal.current_version <> v_proposal_version
       OR v_proposal.version <> v_expected_proposal_version
       OR v_proposal.state <> 'approved'
       OR v_operation.version <> v_expected_operation_version
       OR v_operation.family <> 'wallet_transfer'
       OR v_operation.execution_state <> 'admitted'
       OR v_operation.financial_status <> 'unrecognized' THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'PROPOSAL_OR_OPERATION_STALE';
    END IF;

    SELECT template_version.template_id, template_version.version, template_version.payload_sha256,
           posting_template.state
    INTO v_template_id, v_template_version, v_template_payload_sha256, v_template_state
    FROM jw.posting_template_versions AS template_version
    JOIN jw.posting_templates AS posting_template
      ON posting_template.id = template_version.template_id
     AND posting_template.book_id = template_version.book_id
    WHERE template_version.template_id = v_proposal_payload.posting_template_id
      AND template_version.version = v_proposal_payload.posting_template_version
      AND template_version.book_id = p_book_id
      AND template_version.approved_at IS NOT NULL;
    IF NOT FOUND
       OR v_template_state <> 'active'
       OR v_template_payload_sha256 IS DISTINCT FROM jw_private.posting_template_payload_sha256_v1(
           v_template_id, v_template_version, p_book_id,
           (SELECT payload FROM jw.posting_template_versions
            WHERE template_id = v_template_id AND version = v_template_version AND book_id = p_book_id)
       ) THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'POSTING_TEMPLATE_UNAVAILABLE';
    END IF;

    SELECT coalesce(
        array_agg(DISTINCT approval.reviewer_principal_id ORDER BY approval.reviewer_principal_id),
        ARRAY[]::uuid[]
    )
    INTO v_approved_reviewers
    FROM jw.proposal_approvals AS approval
    WHERE approval.proposal_id = v_proposal_id
      AND approval.proposal_version = v_proposal_version
      AND approval.book_id = p_book_id
      AND approval.payload_sha256 = v_payload_hash
      AND approval.approval_class = 'manual_distinct_reviewer'
      AND approval.state = 'approved'
      AND approval.revoked_at IS NULL
      AND approval.expires_at > clock_timestamp()
      AND approval.reviewer_principal_id <> v_proposal.created_by;
    IF cardinality(v_approved_reviewers) = 0 THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'APPROVAL_REQUIRED';
    END IF;

    SELECT approval.id, approval.reviewer_principal_id, approval.reviewer_membership_version
    INTO v_approval_id, v_reviewer_id, v_reviewer_membership_version
    FROM jw.proposal_approvals AS approval
    WHERE approval.proposal_id = v_proposal_id
      AND approval.proposal_version = v_proposal_version
      AND approval.book_id = p_book_id
      AND approval.payload_sha256 = v_payload_hash
      AND approval.approval_class = 'manual_distinct_reviewer'
      AND approval.state = 'approved'
      AND approval.revoked_at IS NULL
      AND approval.expires_at > clock_timestamp()
      AND approval.reviewer_principal_id <> v_proposal.created_by
    ORDER BY approval.created_at, approval.id
    LIMIT 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'APPROVAL_REQUIRED';
    END IF;

    SELECT array_agg(DISTINCT authority.principal_id ORDER BY authority.principal_id)
    INTO v_authority_ids
    FROM (
        SELECT p_actor_id AS principal_id
        UNION
        SELECT v_proposal.created_by
        UNION
        SELECT unnest(v_approved_reviewers)
    ) AS authority;

    v_locked_count := 0;
    FOR v_locked_principal_id IN
        SELECT principal.id
        FROM jw.principals AS principal
        JOIN jw.human_users AS human ON human.principal_id = principal.id
        WHERE principal.id = ANY(v_authority_ids)
        ORDER BY principal.id
        FOR SHARE OF principal, human
    LOOP
        v_locked_count := v_locked_count + 1;
    END LOOP;
    IF v_locked_count <> cardinality(v_authority_ids)
       OR EXISTS (
           SELECT 1 FROM jw.principals AS principal
           JOIN jw.human_users AS human ON human.principal_id = principal.id
           WHERE principal.id = ANY(v_authority_ids)
             AND (principal.state <> 'active' OR human.state <> 'active')
       ) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CURRENT_PRINCIPAL_AUTHORITY_REQUIRED';
    END IF;

    SELECT recent_uv_at, recent_operation_sha256
    INTO v_session_recent_uv_at, v_session_operation_sha256
    FROM jw.native_sessions AS session
    JOIN jw.principals AS principal ON principal.id = session.principal_id
    WHERE session.token_digest = p_session_token_sha256
      AND session.principal_id = p_actor_id
      AND session.state = 'active'
      AND session.authentication_method = 'passkey'
      AND session.principal_epoch = principal.authority_epoch
      AND session.absolute_expires_at > clock_timestamp()
      AND session.idle_expires_at > clock_timestamp()
    FOR SHARE OF session;
    IF NOT FOUND
       OR v_session_recent_uv_at IS NULL
       OR v_session_recent_uv_at <= clock_timestamp() - interval '5 minutes'
       OR v_session_recent_uv_at > clock_timestamp()
       OR v_session_operation_sha256 IS DISTINCT FROM v_request_hash THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'RECENT_OPERATION_BOUND_UV_REQUIRED';
    END IF;

    v_locked_count := 0;
    FOR v_membership IN
        SELECT membership.id, membership.principal_id, membership.state, membership.version
        FROM jw.organization_memberships AS membership
        WHERE membership.organization_id = v_book_organization_id
          AND membership.principal_id = ANY(v_authority_ids)
        ORDER BY membership.id
        FOR SHARE
    LOOP
        v_locked_count := v_locked_count + 1;
        IF v_membership.state <> 'active' THEN
            RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CURRENT_MEMBERSHIP_AUTHORITY_REQUIRED';
        END IF;
        IF v_membership.principal_id = p_actor_id THEN
            v_actor_membership_id := v_membership.id;
            v_actor_membership_version := v_membership.version;
        END IF;
        IF v_membership.principal_id = v_reviewer_id THEN
            v_reviewer_membership_id := v_membership.id;
            v_reviewer_current_membership_version := v_membership.version;
        END IF;
        v_membership_ids := array_append(v_membership_ids, v_membership.id);
    END LOOP;
    IF v_locked_count <> cardinality(v_authority_ids)
       OR v_actor_membership_id IS NULL
       OR v_reviewer_membership_id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CURRENT_MEMBERSHIP_AUTHORITY_REQUIRED';
    END IF;

    v_actor_has_operator := false;
    v_reviewer_has_role := false;
    FOR v_assignment IN
        SELECT assignment.id, assignment.membership_id, assignment.role
        FROM jw.book_role_assignments AS assignment
        WHERE assignment.book_id = p_book_id
          AND assignment.organization_id = v_book_organization_id
          AND assignment.membership_id = ANY(v_membership_ids)
          AND assignment.state = 'active'
          AND (assignment.expires_at IS NULL OR assignment.expires_at > clock_timestamp())
        ORDER BY assignment.id
        FOR SHARE
    LOOP
        IF v_assignment.membership_id = v_actor_membership_id
           AND v_assignment.role = 'finance_operator' THEN
            v_actor_has_operator := true;
        END IF;
        IF v_assignment.membership_id = v_reviewer_membership_id
           AND v_assignment.role = 'finance_reviewer' THEN
            v_reviewer_has_role := true;
        END IF;
    END LOOP;
    IF NOT v_actor_has_operator OR NOT v_reviewer_has_role THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CURRENT_FINANCIAL_ROLE_REQUIRED';
    END IF;

    SELECT journal_sequence, state_sequence, projection_status
    INTO v_book_journal_sequence, v_book_state_sequence, v_projection_status
    FROM jw.book_financial_state
    WHERE book_id = p_book_id
      AND organization_id = v_book_organization_id
    FOR UPDATE;
    IF NOT FOUND
       OR v_projection_status <> 'current'
       OR v_book_journal_sequence = 9223372036854775807
       OR v_book_state_sequence = 9223372036854775807 THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'BOOK_FINANCIAL_STATE_UNAVAILABLE';
    END IF;

    SELECT book.state
    INTO v_book_state
    FROM jw.books AS book
    WHERE book.id = p_book_id
      AND book.organization_id = v_book_organization_id;
    IF v_book_state <> 'active'
       OR EXISTS (
           SELECT 1 FROM jw.book_lifecycle_restrictions AS restriction
           WHERE restriction.book_id = p_book_id AND restriction.state = 'active'
       ) THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'BOOK_FINANCIAL_ADMISSION_DENIED';
    END IF;

    SELECT *
    INTO v_receipt
    FROM jw.command_receipts AS receipt
    WHERE receipt.book_id = p_book_id
      AND receipt.actor_principal_id = p_actor_id
      AND receipt.command_family = 'journal.post'
      AND receipt.command_key_sha256 = p_command_key_sha256
    FOR UPDATE;
    IF FOUND THEN
        IF v_receipt.canonical_request_sha256 <> v_request_hash THEN
            RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'IDEMPOTENCY_CONFLICT';
        END IF;
        IF v_receipt.state <> 'accepted' OR v_receipt.result_kind <> 'journal' THEN
            RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'JOURNAL_RESULT_UNAVAILABLE';
        END IF;
        SELECT journal.journal_sequence, journal.state_sequence
        INTO v_result_journal_sequence, v_result_state_sequence
        FROM jw.journals AS journal
        WHERE journal.id = v_receipt.result_id AND journal.book_id = p_book_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'JOURNAL_RESULT_UNAVAILABLE';
        END IF;
        RETURN jsonb_build_object(
            'command_receipt_id', v_receipt.id,
            'operation_id', v_receipt.operation_id,
            'step_id', v_receipt.step_id,
            'result_kind', 'journal',
            'result_id', v_receipt.result_id,
            'journal_sequence', v_result_journal_sequence,
            'state_sequence', v_result_state_sequence,
            'reused', true
        );
    END IF;

    SELECT * INTO v_operation
    FROM jw.business_operations AS operation
    WHERE operation.id = v_operation_id
      AND operation.book_id = p_book_id
    FOR UPDATE;
    IF NOT FOUND
       OR v_operation.version <> v_expected_operation_version
       OR v_operation.family <> 'wallet_transfer'
       OR v_operation.family_version <> 1
       OR v_operation.execution_state <> 'admitted'
       OR v_operation.financial_status <> 'unrecognized' THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'OPERATION_STATE_STALE';
    END IF;

    SELECT * INTO v_step
    FROM jw.operation_steps AS step
    WHERE step.id = v_step_id
      AND step.operation_id = v_operation_id
      AND step.book_id = p_book_id
    FOR UPDATE;
    IF NOT FOUND OR v_step.state <> 'admitted' OR v_step.step_kind <> 'recognize' THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'OPERATION_STEP_STATE_STALE';
    END IF;
    IF v_step.request_sha256 IS DISTINCT FROM jw_private.wallet_transfer_step_sha256_v1(
        p_book_id, v_operation_id, v_step_key, v_operation.request_sha256
    ) THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'OPERATION_STEP_IDENTITY_CONFLICT';
    END IF;

    SELECT * INTO v_proposal
    FROM jw.posting_proposals AS proposal
    WHERE proposal.id = v_proposal_id
      AND proposal.operation_step_id = v_step_id
      AND proposal.book_id = p_book_id
    FOR UPDATE;
    IF NOT FOUND
       OR v_proposal.state <> 'approved'
       OR v_proposal.current_version <> v_proposal_version
       OR v_proposal.version <> v_expected_proposal_version
       OR v_proposal.created_by = v_reviewer_id THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'POSTING_PROPOSAL_STALE';
    END IF;

    PERFORM 1
    FROM jw.proposal_approvals AS approval
    WHERE approval.proposal_id = v_proposal_id
      AND approval.proposal_version = v_proposal_version
      AND approval.book_id = p_book_id
      AND approval.payload_sha256 = v_payload_hash
      AND approval.approval_class = 'manual_distinct_reviewer'
    ORDER BY approval.id
    FOR SHARE;

    SELECT coalesce(
        array_agg(DISTINCT approval.reviewer_principal_id ORDER BY approval.reviewer_principal_id),
        ARRAY[]::uuid[]
    )
    INTO v_current_reviewers
    FROM jw.proposal_approvals AS approval
    WHERE approval.proposal_id = v_proposal_id
      AND approval.proposal_version = v_proposal_version
      AND approval.book_id = p_book_id
      AND approval.payload_sha256 = v_payload_hash
      AND approval.approval_class = 'manual_distinct_reviewer'
      AND approval.state = 'approved'
      AND approval.revoked_at IS NULL
      AND approval.expires_at > clock_timestamp()
      AND approval.reviewer_principal_id <> v_proposal.created_by;
    IF v_current_reviewers IS DISTINCT FROM v_approved_reviewers THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'APPROVAL_SET_CHANGED';
    END IF;

    SELECT * INTO v_proposal_payload
    FROM jw.posting_proposal_versions AS proposal_version
    WHERE proposal_version.proposal_id = v_proposal_id
      AND proposal_version.proposal_version = v_proposal_version
      AND proposal_version.book_id = p_book_id
    FOR SHARE;
    IF NOT FOUND
       OR v_proposal_payload.payload_sha256 IS DISTINCT FROM v_payload_hash
       OR v_proposal_payload.payload_sha256 IS DISTINCT FROM
          jw_private.posting_proposal_payload_sha256_v1(
              v_proposal_id,
              v_proposal_version,
              p_book_id,
              v_proposal_payload.posting_template_id,
              v_proposal_payload.posting_template_version,
              v_proposal_payload.effective_date,
              v_proposal_payload.period_id,
              v_proposal_payload.canonical_lines,
              v_proposal_payload.evidence_references
          ) THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'PROPOSAL_PAYLOAD_HASH_MISMATCH';
    END IF;

    SELECT * INTO v_approval
    FROM jw.proposal_approvals AS approval
    WHERE approval.id = v_approval_id
      AND approval.proposal_id = v_proposal_id
      AND approval.proposal_version = v_proposal_version
      AND approval.book_id = p_book_id
      AND approval.payload_sha256 = v_payload_hash
      AND approval.reviewer_principal_id = v_reviewer_id
      AND approval.approval_class = 'manual_distinct_reviewer'
      AND approval.state = 'approved'
      AND approval.revoked_at IS NULL
      AND approval.expires_at > clock_timestamp()
    FOR SHARE;
    IF NOT FOUND
       OR v_approval.reviewer_membership_version <> v_reviewer_membership_version
       OR v_approval.reviewer_membership_version <> v_reviewer_current_membership_version THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'APPROVAL_STALE';
    END IF;

    PERFORM 1
    FROM jw.posting_templates AS posting_template
    WHERE posting_template.id = v_proposal_payload.posting_template_id
      AND posting_template.book_id = p_book_id
      AND posting_template.state = 'active'
    FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'POSTING_TEMPLATE_UNAVAILABLE';
    END IF;

    SELECT * INTO v_template_version_row
    FROM jw.posting_template_versions AS template_version
    WHERE template_version.template_id = v_proposal_payload.posting_template_id
      AND template_version.version = v_proposal_payload.posting_template_version
      AND template_version.book_id = p_book_id
      AND template_version.approved_at IS NOT NULL
    FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'POSTING_TEMPLATE_UNAVAILABLE';
    END IF;

    v_expected_lines := jw_private.expand_wallet_transfer_v1(
        p_book_id,
        v_operation_id,
        v_template_version_row.template_id,
        v_template_version_row.version,
        v_proposal_payload.canonical_lines
    );
    v_proposed_without_descriptions := NULL;
    SELECT jsonb_agg(line.value - 'safe_description' ORDER BY line.ordinality)
    INTO v_proposed_without_descriptions
    FROM jsonb_array_elements(v_proposal_payload.canonical_lines)
         WITH ORDINALITY AS line(value, ordinality);
    IF v_proposed_without_descriptions IS DISTINCT FROM v_expected_lines THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'PROPOSAL_LINES_DO_NOT_MATCH_TEMPLATE';
    END IF;

    SELECT period.id, period.state, period.starts_on, period.ends_before
    INTO v_period_id, v_period_state, v_period_starts_on, v_period_ends_before
    FROM jw.accounting_periods AS period
    WHERE period.id = v_proposal_payload.period_id
      AND period.book_id = p_book_id
    FOR SHARE;
    IF NOT FOUND
       OR v_period_state <> 'open'
       OR v_proposal_payload.effective_date < v_period_starts_on
       OR v_proposal_payload.effective_date >= v_period_ends_before THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'PERIOD_NOT_OPEN';
    END IF;

    SELECT array_agg(DISTINCT (line.value ->> 'account_id')::uuid ORDER BY (line.value ->> 'account_id')::uuid)
    INTO v_account_ids
    FROM jsonb_array_elements(v_expected_lines) AS line(value);
    v_account_locked_count := 0;
    FOR v_locked_account_id IN
        SELECT account.id
        FROM jw.accounts AS account
        WHERE account.book_id = p_book_id
          AND account.id = ANY(v_account_ids)
        ORDER BY account.id
        FOR SHARE OF account
    LOOP
        v_account_locked_count := v_account_locked_count + 1;
    END LOOP;
    IF v_account_locked_count <> cardinality(v_account_ids) THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'POSTING_ACCOUNT_SCOPE_INVALID';
    END IF;

    v_financial_locked_count := 0;
    FOR v_locked_account_id IN
        SELECT financial_state.account_id
        FROM jw.account_financial_state AS financial_state
        WHERE financial_state.book_id = p_book_id
          AND financial_state.account_id = ANY(v_account_ids)
        ORDER BY financial_state.account_id
        FOR UPDATE
    LOOP
        v_financial_locked_count := v_financial_locked_count + 1;
    END LOOP;
    IF v_financial_locked_count <> cardinality(v_account_ids) THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'POSTING_ACCOUNT_STATE_UNAVAILABLE';
    END IF;

    v_journal_sequence := v_book_journal_sequence + 1;
    v_state_sequence := v_book_state_sequence + 1;
    v_journal_id := gen_random_uuid();
    INSERT INTO jw.command_receipts (
        book_id, actor_principal_id, command_family, command_key_sha256,
        canonical_request_sha256, operation_id, step_id, state
    )
    VALUES (
        p_book_id, p_actor_id, 'journal.post', p_command_key_sha256,
        v_request_hash, v_operation_id, v_step_id, 'admitted'
    )
    RETURNING id INTO v_receipt_id;

    FOR v_line, v_line_number IN
        SELECT line.value, line.ordinality::integer
        FROM jsonb_array_elements(v_expected_lines) WITH ORDINALITY AS line(value, ordinality)
        ORDER BY line.ordinality
    LOOP
        v_original_line := v_proposal_payload.canonical_lines -> (v_line_number - 1);
        v_amount := jw_private.parse_positive_amount_v1(v_line ->> 'amount');
        INSERT INTO jw.postings (
            journal_id, line_number, book_id, account_id, currency_definition_id,
            side, amount, template_role, safe_description
        )
        VALUES (
            v_journal_id,
            v_line_number,
            p_book_id,
            (v_line ->> 'account_id')::uuid,
            (v_line ->> 'currency_definition_id')::uuid,
            v_line ->> 'side',
            v_amount,
            v_line ->> 'template_role',
            v_original_line ->> 'safe_description'
        );
    END LOOP;

    INSERT INTO jw.journals (
        id, book_id, organization_id, journal_sequence, state_sequence, operation_id, operation_step_id,
        proposal_id, accepted_proposal_version, accepted_proposal_sha256,
        template_id, template_version, effective_date, period_id, source_kind,
        source_reference_id, payload_sha256, created_by
    )
    VALUES (
        v_journal_id,
        p_book_id,
        v_book_organization_id,
        v_journal_sequence,
        v_state_sequence,
        v_operation_id,
        v_step_id,
        v_proposal_id,
        v_proposal_version,
        v_payload_hash,
        v_template_version_row.template_id,
        v_template_version_row.version,
        v_proposal_payload.effective_date,
        v_period_id,
        'wallet_transfer',
        v_operation_id,
        v_payload_hash,
        p_actor_id
    );

    v_financial_locked_count := 0;
    FOR v_account_record IN
        WITH expanded_lines AS (
            SELECT (line.value ->> 'account_id')::uuid AS account_id,
                   line.value ->> 'side' AS side,
                   jw_private.parse_positive_amount_v1(line.value ->> 'amount') AS amount
            FROM jsonb_array_elements(v_expected_lines) AS line(value)
        ),
        account_deltas AS (
            SELECT expanded_lines.account_id,
                   coalesce(sum(expanded_lines.amount) FILTER (WHERE expanded_lines.side = 'debit'), 0) AS debit_delta,
                   coalesce(sum(expanded_lines.amount) FILTER (WHERE expanded_lines.side = 'credit'), 0) AS credit_delta
            FROM expanded_lines
            GROUP BY expanded_lines.account_id
        )
        SELECT account.id AS account_id,
               account.state AS account_state,
               account.normal_side,
               account.spend_policy,
               financial_state.debit_total,
               financial_state.credit_total,
               financial_state.active_reserved_total,
               financial_state.restriction_amount,
               financial_state.version AS financial_version,
               coalesce(account_deltas.debit_delta, 0) AS debit_delta,
               coalesce(account_deltas.credit_delta, 0) AS credit_delta
        FROM jw.accounts AS account
        JOIN jw.account_financial_state AS financial_state
          ON financial_state.account_id = account.id
         AND financial_state.book_id = account.book_id
         AND financial_state.currency_definition_id = account.currency_definition_id
        LEFT JOIN account_deltas ON account_deltas.account_id = account.id
        WHERE account.book_id = p_book_id
          AND account.id = ANY(v_account_ids)
        ORDER BY account.id
        FOR UPDATE OF financial_state
    LOOP
        v_financial_locked_count := v_financial_locked_count + 1;
        IF v_account_record.account_state <> 'active'
           OR v_account_record.financial_version = 9223372036854775807 THEN
            RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'POSTING_ACCOUNT_STATE_STALE';
        END IF;

        v_debit_after := v_account_record.debit_total + v_account_record.debit_delta;
        v_credit_after := v_account_record.credit_total + v_account_record.credit_delta;
        IF v_debit_after >= 100000000000000000000000000000000000000
           OR v_credit_after >= 100000000000000000000000000000000000000 THEN
            RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'AMOUNT_OVERFLOW';
        END IF;

        IF v_account_record.spend_policy = 'protected_customer_liability'
           AND v_account_record.credit_total + v_account_record.credit_delta
             - v_account_record.debit_total - v_account_record.debit_delta
             - v_account_record.active_reserved_total - v_account_record.restriction_amount < 0 THEN
            RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'INSUFFICIENT_AVAILABLE_FUNDS';
        END IF;

        UPDATE jw.account_financial_state
        SET debit_total = v_debit_after,
            credit_total = v_credit_after,
            last_journal_sequence = v_journal_sequence,
            last_state_sequence = v_state_sequence,
            version = version + 1
        WHERE account_id = v_account_record.account_id
          AND book_id = p_book_id;
    END LOOP;

    IF v_financial_locked_count <> cardinality(v_account_ids) THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'POSTING_ACCOUNT_STATE_UNAVAILABLE';
    END IF;

    UPDATE jw.book_financial_state
    SET journal_sequence = v_journal_sequence,
        state_sequence = v_state_sequence,
        updated_at = clock_timestamp()
    WHERE book_id = p_book_id
      AND organization_id = v_book_organization_id;

    INSERT INTO jw.journal_correction_limits (original_journal_id, book_id, policy_version)
    VALUES (v_journal_id, p_book_id, 'wallet-transfer-reversal-v1');
    INSERT INTO jw.journal_line_correction_state (
        original_journal_id, original_line_number, book_id, original_amount
    )
    SELECT posting.journal_id, posting.line_number, posting.book_id, posting.amount
    FROM jw.postings AS posting
    WHERE posting.journal_id = v_journal_id
      AND posting.book_id = p_book_id;

    UPDATE jw.operation_steps
    SET state = 'accepted',
        result_journal_id = v_journal_id,
        accepted_state_sequence = v_state_sequence,
        completed_at = clock_timestamp()
    WHERE id = v_step_id
      AND book_id = p_book_id;

    UPDATE jw.posting_proposals
    SET state = 'posted', version = version + 1
    WHERE id = v_proposal_id
      AND book_id = p_book_id;

    UPDATE jw.business_operations
    SET execution_state = 'recognized',
        financial_status = 'recognized',
        updated_at = clock_timestamp(),
        version = version + 1
    WHERE id = v_operation_id
      AND book_id = p_book_id;

    INSERT INTO jw.audit_events (
        organization_id, book_id, actor_principal_id, actor_kind, action,
        target_kind, target_id, outcome, request_id, command_receipt_id,
        event_schema_version, safe_payload
    )
    VALUES (
        v_book_organization_id, p_book_id, p_actor_id, 'human', 'journal.post',
        'journal', v_journal_id, 'accepted', gen_random_uuid()::text, v_receipt_id,
        1,
        jsonb_build_object(
            'operation_id', v_operation_id,
            'step_id', v_step_id,
            'proposal_id', v_proposal_id,
            'proposal_version', v_proposal_version,
            'payload_sha256', encode(v_payload_hash, 'hex'),
            'journal_sequence', v_journal_sequence,
            'state_sequence', v_state_sequence
        )
    );

    UPDATE jw.command_receipts
    SET state = 'accepted',
        result_kind = 'journal',
        result_id = v_journal_id,
        accepted_at = clock_timestamp()
    WHERE id = v_receipt_id
      AND book_id = p_book_id;

    SELECT operation.version
    INTO v_result_operation_version
    FROM jw.business_operations AS operation
    WHERE operation.id = v_operation_id
      AND operation.book_id = p_book_id;
    RETURN jsonb_build_object(
        'command_receipt_id', v_receipt_id,
        'operation_id', v_operation_id,
        'step_id', v_step_id,
        'result_kind', 'journal',
        'result_id', v_journal_id,
        'journal_sequence', v_journal_sequence,
        'state_sequence', v_state_sequence,
        'operation_version', v_result_operation_version,
        'reused', false
    );
END
$post_proposal$;
REVOKE ALL ON FUNCTION jw_api.post_proposal_v1(uuid, uuid, bytea, bytea, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION jw_api.post_proposal_v1(uuid, uuid, bytea, bytea, jsonb)
    TO journalwick_runtime;
