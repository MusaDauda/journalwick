CREATE TABLE jw.business_operations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    book_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    family text NOT NULL,
    family_version integer NOT NULL,
    origin_namespace text NOT NULL,
    business_key text NOT NULL,
    request_sha256 bytea NOT NULL,
    primary_currency_definition_id uuid,
    requested_amount numeric(38, 0),
    execution_state text NOT NULL DEFAULT 'admitted',
    financial_status text NOT NULL DEFAULT 'unrecognized',
    created_by uuid NOT NULL REFERENCES jw.principals (id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT business_operations_family_shape CHECK (
        char_length(family) BETWEEN 1 AND 80
        AND family COLLATE "C" ~ '^[a-z][a-z0-9_.-]*$'
    ),
    CONSTRAINT business_operations_family_version_positive CHECK (family_version > 0),
    CONSTRAINT business_operations_namespace_shape CHECK (
        char_length(origin_namespace) BETWEEN 1 AND 80
        AND origin_namespace COLLATE "C" ~ '^[a-z0-9][a-z0-9._-]*$'
    ),
    CONSTRAINT business_operations_business_key_shape CHECK (
        char_length(business_key) BETWEEN 1 AND 160
        AND business_key !~ '[[:cntrl:]]'
    ),
    CONSTRAINT business_operations_hash_size CHECK (octet_length(request_sha256) = 32),
    CONSTRAINT business_operations_primary_amount CHECK (
        (requested_amount IS NULL AND primary_currency_definition_id IS NULL)
        OR (
            requested_amount IS NOT NULL
            AND requested_amount > 0
            AND requested_amount < 1000000000000000000000000000000
            AND primary_currency_definition_id IS NOT NULL
        )
    ),
    CONSTRAINT business_operations_execution_state CHECK (
        execution_state IN (
            'admitted', 'reserved', 'dispatch_ready', 'dispatching', 'provider_pending',
            'provider_unknown', 'recognized', 'settled', 'failed', 'cancelled'
        )
    ),
    CONSTRAINT business_operations_financial_status CHECK (
        financial_status IN ('unrecognized', 'partially_recognized', 'recognized', 'corrected')
    ),
    CONSTRAINT business_operations_version_positive CHECK (version > 0),
    CONSTRAINT business_operations_updated_time CHECK (updated_at >= created_at),
    CONSTRAINT business_operations_book_scope_fk
        FOREIGN KEY (book_id, organization_id)
        REFERENCES jw.books (id, organization_id) ON DELETE RESTRICT,
    CONSTRAINT business_operations_primary_currency_fk
        FOREIGN KEY (primary_currency_definition_id)
        REFERENCES jw.currency_definitions (id) ON DELETE RESTRICT,
    CONSTRAINT business_operations_id_book_unique UNIQUE (id, book_id),
    CONSTRAINT business_operations_book_business_identity_unique
        UNIQUE (book_id, origin_namespace, business_key)
);
CREATE INDEX business_operations_book_state_time_idx
    ON jw.business_operations (book_id, execution_state, updated_at, id);
CREATE INDEX business_operations_book_family_time_idx
    ON jw.business_operations (book_id, family, created_at, id);

CREATE TABLE jw.operation_steps (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    operation_id uuid NOT NULL,
    book_id uuid NOT NULL,
    step_key text NOT NULL,
    step_kind text NOT NULL,
    request_sha256 bytea NOT NULL,
    state text NOT NULL DEFAULT 'admitted',
    amount numeric(38, 0),
    currency_definition_id uuid,
    result_journal_id uuid,
    result_reservation_id uuid,
    accepted_state_sequence bigint,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    completed_at timestamptz,
    CONSTRAINT operation_steps_key_shape CHECK (
        char_length(step_key) BETWEEN 1 AND 100
        AND step_key COLLATE "C" ~ '^[A-Za-z0-9][A-Za-z0-9_.:-]*$'
    ),
    CONSTRAINT operation_steps_kind CHECK (
        step_kind IN (
            'request_reservation', 'reserve', 'capture', 'release', 'expire',
            'recognize', 'settle', 'reverse', 'adjust'
        )
    ),
    CONSTRAINT operation_steps_request_hash_size CHECK (octet_length(request_sha256) = 32),
    CONSTRAINT operation_steps_state CHECK (
        state IN ('admitted', 'accepted', 'rejected', 'cancelled')
    ),
    CONSTRAINT operation_steps_amount_currency_pair CHECK (
        (amount IS NULL AND currency_definition_id IS NULL)
        OR (
            amount IS NOT NULL
            AND amount > 0
            AND amount < 1000000000000000000000000000000
            AND currency_definition_id IS NOT NULL
        )
    ),
    CONSTRAINT operation_steps_reservation_amount_required CHECK (
        step_kind NOT IN ('request_reservation', 'reserve', 'capture', 'release', 'expire')
        OR amount IS NOT NULL
    ),
    CONSTRAINT operation_steps_result_shape CHECK (
        (
            state = 'admitted'
            AND completed_at IS NULL
            AND accepted_state_sequence IS NULL
            AND result_journal_id IS NULL
            AND result_reservation_id IS NULL
        )
        OR (
            state IN ('rejected', 'cancelled')
            AND completed_at IS NOT NULL
            AND accepted_state_sequence IS NULL
            AND result_journal_id IS NULL
            AND result_reservation_id IS NULL
        )
        OR (
            state = 'accepted'
            AND completed_at IS NOT NULL
            AND accepted_state_sequence IS NOT NULL
            AND accepted_state_sequence > 0
            AND (
                (
                    step_kind IN ('request_reservation', 'reserve', 'release', 'expire')
                    AND result_journal_id IS NULL
                    AND result_reservation_id IS NOT NULL
                )
                OR (
                    step_kind = 'capture'
                    AND result_journal_id IS NOT NULL
                    AND result_reservation_id IS NOT NULL
                )
                OR (
                    step_kind IN ('recognize', 'settle', 'reverse', 'adjust')
                    AND result_journal_id IS NOT NULL
                    AND result_reservation_id IS NULL
                )
            )
        )
    ),
    CONSTRAINT operation_steps_completed_time CHECK (
        completed_at IS NULL OR completed_at >= created_at
    ),
    CONSTRAINT operation_steps_operation_scope_fk
        FOREIGN KEY (operation_id, book_id)
        REFERENCES jw.business_operations (id, book_id) ON DELETE RESTRICT,
    CONSTRAINT operation_steps_currency_fk
        FOREIGN KEY (currency_definition_id)
        REFERENCES jw.currency_definitions (id) ON DELETE RESTRICT,
    CONSTRAINT operation_steps_operation_key_unique UNIQUE (operation_id, step_key),
    CONSTRAINT operation_steps_id_book_unique UNIQUE (id, book_id),
    CONSTRAINT operation_steps_id_operation_book_unique UNIQUE (id, operation_id, book_id)
);
CREATE INDEX operation_steps_book_state_time_idx
    ON jw.operation_steps (book_id, state, created_at, id);
CREATE INDEX operation_steps_operation_time_idx
    ON jw.operation_steps (operation_id, created_at, id);

CREATE TABLE jw.command_receipts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    book_id uuid NOT NULL REFERENCES jw.books (id) ON DELETE RESTRICT,
    actor_principal_id uuid NOT NULL REFERENCES jw.principals (id) ON DELETE RESTRICT,
    command_family text NOT NULL,
    command_key_sha256 bytea NOT NULL,
    canonical_request_sha256 bytea NOT NULL,
    operation_id uuid,
    step_id uuid,
    result_kind text,
    result_id uuid,
    state text NOT NULL DEFAULT 'admitted',
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    accepted_at timestamptz,
    CONSTRAINT command_receipts_family_shape CHECK (
        char_length(command_family) BETWEEN 1 AND 80
        AND command_family COLLATE "C" ~ '^[a-z][a-z0-9_.-]*$'
    ),
    CONSTRAINT command_receipts_hash_sizes CHECK (
        octet_length(command_key_sha256) = 32
        AND octet_length(canonical_request_sha256) = 32
    ),
    CONSTRAINT command_receipts_step_requires_operation CHECK (
        step_id IS NULL OR operation_id IS NOT NULL
    ),
    CONSTRAINT command_receipts_state CHECK (state IN ('admitted', 'accepted', 'rejected')),
    CONSTRAINT command_receipts_result_pair CHECK (
        (result_kind IS NULL AND result_id IS NULL)
        OR (result_kind IS NOT NULL AND result_id IS NOT NULL)
    ),
    CONSTRAINT command_receipts_result_kind_shape CHECK (
        result_kind IS NULL
        OR (
            char_length(result_kind) BETWEEN 1 AND 80
            AND result_kind COLLATE "C" ~ '^[a-z][a-z0-9_.-]*$'
        )
    ),
    CONSTRAINT command_receipts_state_result CHECK (
        (
            state = 'accepted'
            AND accepted_at IS NOT NULL
            AND result_kind IS NOT NULL
            AND result_id IS NOT NULL
            AND (operation_id IS NOT NULL OR step_id IS NOT NULL)
        )
        OR (
            state IN ('admitted', 'rejected')
            AND accepted_at IS NULL
            AND result_kind IS NULL
            AND result_id IS NULL
        )
    ),
    CONSTRAINT command_receipts_result_identity CHECK (
        (
            result_kind IS DISTINCT FROM 'operation'
            OR (operation_id IS NOT DISTINCT FROM result_id AND step_id IS NULL)
        )
        AND (result_kind IS DISTINCT FROM 'operation_step' OR step_id IS NOT DISTINCT FROM result_id)
    ),
    CONSTRAINT command_receipts_accepted_time CHECK (
        accepted_at IS NULL OR accepted_at >= created_at
    ),
    CONSTRAINT command_receipts_operation_scope_fk
        FOREIGN KEY (operation_id, book_id)
        REFERENCES jw.business_operations (id, book_id) ON DELETE RESTRICT,
    CONSTRAINT command_receipts_step_scope_fk
        FOREIGN KEY (step_id, operation_id, book_id)
        REFERENCES jw.operation_steps (id, operation_id, book_id) ON DELETE RESTRICT,
    CONSTRAINT command_receipts_scoped_key_unique
        UNIQUE (book_id, actor_principal_id, command_family, command_key_sha256),
    CONSTRAINT command_receipts_id_book_unique UNIQUE (id, book_id)
);
CREATE INDEX command_receipts_operation_time_idx
    ON jw.command_receipts (book_id, operation_id, created_at DESC, id);

CREATE TABLE jw.economic_recognitions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    book_id uuid NOT NULL,
    source_namespace text NOT NULL,
    source_account_reference uuid NOT NULL,
    source_mode text NOT NULL,
    economic_object_key text NOT NULL,
    recognition_kind text NOT NULL,
    recognition_version integer NOT NULL,
    operation_step_id uuid NOT NULL,
    journal_id uuid,
    source_observation_id uuid,
    canonical_facts_sha256 bytea NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT economic_recognitions_namespace_shape CHECK (
        char_length(source_namespace) BETWEEN 1 AND 80
        AND source_namespace COLLATE "C" ~ '^[a-z0-9][a-z0-9._-]*$'
    ),
    CONSTRAINT economic_recognitions_mode CHECK (source_mode IN ('synthetic', 'sandbox', 'live')),
    CONSTRAINT economic_recognitions_object_key_shape CHECK (
        char_length(economic_object_key) BETWEEN 1 AND 160
        AND economic_object_key !~ '[[:cntrl:]]'
    ),
    CONSTRAINT economic_recognitions_kind_shape CHECK (
        char_length(recognition_kind) BETWEEN 1 AND 80
        AND recognition_kind COLLATE "C" ~ '^[a-z][a-z0-9_.-]*$'
    ),
    CONSTRAINT economic_recognitions_version_positive CHECK (recognition_version > 0),
    CONSTRAINT economic_recognitions_hash_size CHECK (octet_length(canonical_facts_sha256) = 32),
    CONSTRAINT economic_recognitions_operation_step_scope_fk
        FOREIGN KEY (operation_step_id, book_id)
        REFERENCES jw.operation_steps (id, book_id) ON DELETE RESTRICT,
    CONSTRAINT economic_recognitions_id_book_unique UNIQUE (id, book_id),
    CONSTRAINT economic_recognitions_identity_unique UNIQUE (
        book_id, source_namespace, source_account_reference, source_mode,
        economic_object_key, recognition_kind, recognition_version
    )
);
CREATE INDEX economic_recognitions_book_time_idx
    ON jw.economic_recognitions (book_id, created_at DESC, id);

CREATE TABLE jw.posting_templates (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    book_id uuid NOT NULL REFERENCES jw.books (id) ON DELETE RESTRICT,
    code text NOT NULL,
    state text NOT NULL DEFAULT 'draft',
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT posting_templates_code_shape CHECK (
        char_length(code) BETWEEN 1 AND 80
        AND code COLLATE "C" ~ '^[A-Z0-9][A-Z0-9_-]*$'
    ),
    CONSTRAINT posting_templates_state CHECK (state IN ('draft', 'active', 'retired')),
    CONSTRAINT posting_templates_book_code_unique UNIQUE (book_id, code),
    CONSTRAINT posting_templates_id_book_unique UNIQUE (id, book_id)
);
CREATE INDEX posting_templates_book_state_idx
    ON jw.posting_templates (book_id, state, code, id);

CREATE TABLE jw.posting_template_versions (
    template_id uuid NOT NULL,
    version integer NOT NULL,
    book_id uuid NOT NULL,
    payload_schema_version integer NOT NULL,
    payload jsonb NOT NULL,
    payload_sha256 bytea NOT NULL,
    created_by uuid NOT NULL REFERENCES jw.principals (id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    approved_at timestamptz,
    CONSTRAINT posting_template_versions_pk PRIMARY KEY (template_id, version),
    CONSTRAINT posting_template_versions_version_positive CHECK (version > 0),
    CONSTRAINT posting_template_versions_schema_version_positive CHECK (
        payload_schema_version > 0
    ),
    CONSTRAINT posting_template_versions_payload_object CHECK (
        jsonb_typeof(payload) = 'object'
        AND octet_length(payload::text) <= 65536
    ),
    CONSTRAINT posting_template_versions_hash_size CHECK (octet_length(payload_sha256) = 32),
    CONSTRAINT posting_template_versions_approval_time CHECK (
        approved_at IS NULL OR approved_at >= created_at
    ),
    CONSTRAINT posting_template_versions_template_scope_fk
        FOREIGN KEY (template_id, book_id)
        REFERENCES jw.posting_templates (id, book_id) ON DELETE RESTRICT,
    CONSTRAINT posting_template_versions_template_version_book_unique
        UNIQUE (template_id, version, book_id)
);

CREATE TABLE jw.posting_proposals (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    book_id uuid NOT NULL REFERENCES jw.books (id) ON DELETE RESTRICT,
    operation_step_id uuid NOT NULL,
    current_version bigint NOT NULL DEFAULT 1,
    state text NOT NULL DEFAULT 'draft',
    created_by uuid NOT NULL REFERENCES jw.principals (id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT posting_proposals_current_version_positive CHECK (current_version > 0),
    CONSTRAINT posting_proposals_state CHECK (
        state IN ('draft', 'validated', 'approved', 'posted', 'rejected', 'cancelled')
    ),
    CONSTRAINT posting_proposals_version_positive CHECK (version > 0),
    CONSTRAINT posting_proposals_step_scope_fk
        FOREIGN KEY (operation_step_id, book_id)
        REFERENCES jw.operation_steps (id, book_id) ON DELETE RESTRICT,
    CONSTRAINT posting_proposals_one_per_step UNIQUE (operation_step_id),
    CONSTRAINT posting_proposals_id_book_unique UNIQUE (id, book_id)
);
CREATE INDEX posting_proposals_book_state_time_idx
    ON jw.posting_proposals (book_id, state, created_at DESC, id);

CREATE TABLE jw.posting_proposal_versions (
    proposal_id uuid NOT NULL,
    proposal_version bigint NOT NULL,
    book_id uuid NOT NULL,
    posting_template_id uuid NOT NULL,
    posting_template_version integer NOT NULL,
    effective_date date NOT NULL,
    period_id uuid NOT NULL,
    canonical_lines jsonb NOT NULL,
    evidence_references jsonb NOT NULL DEFAULT '[]'::jsonb,
    payload_sha256 bytea NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT posting_proposal_versions_pk PRIMARY KEY (proposal_id, proposal_version),
    CONSTRAINT posting_proposal_versions_version_positive CHECK (proposal_version > 0),
    CONSTRAINT posting_proposal_versions_template_version_positive CHECK (
        posting_template_version > 0
    ),
    CONSTRAINT posting_proposal_versions_canonical_lines CHECK (
        jsonb_typeof(canonical_lines) = 'array'
        AND jsonb_array_length(canonical_lines) BETWEEN 2 AND 200
        AND octet_length(canonical_lines::text) <= 262144
    ),
    CONSTRAINT posting_proposal_versions_evidence_references CHECK (
        jsonb_typeof(evidence_references) = 'array'
        AND jsonb_array_length(evidence_references) <= 200
        AND octet_length(evidence_references::text) <= 65536
    ),
    CONSTRAINT posting_proposal_versions_hash_size CHECK (octet_length(payload_sha256) = 32),
    CONSTRAINT posting_proposal_versions_proposal_scope_fk
        FOREIGN KEY (proposal_id, book_id)
        REFERENCES jw.posting_proposals (id, book_id) ON DELETE RESTRICT,
    CONSTRAINT posting_proposal_versions_template_scope_fk
        FOREIGN KEY (posting_template_id, posting_template_version, book_id)
        REFERENCES jw.posting_template_versions (template_id, version, book_id)
        ON DELETE RESTRICT,
    CONSTRAINT posting_proposal_versions_period_scope_fk
        FOREIGN KEY (period_id, book_id)
        REFERENCES jw.accounting_periods (id, book_id) ON DELETE RESTRICT,
    CONSTRAINT posting_proposal_versions_proposal_version_book_unique
        UNIQUE (proposal_id, proposal_version, book_id),
    CONSTRAINT posting_proposal_versions_proposal_hash_scope_unique
        UNIQUE (proposal_id, proposal_version, book_id, payload_sha256)
);

ALTER TABLE jw.posting_proposals
    ADD CONSTRAINT posting_proposals_current_version_fk
    FOREIGN KEY (id, current_version, book_id)
    REFERENCES jw.posting_proposal_versions (proposal_id, proposal_version, book_id)
    DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE jw.proposal_approvals (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    proposal_id uuid NOT NULL,
    proposal_version bigint NOT NULL,
    book_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    payload_sha256 bytea NOT NULL,
    reviewer_principal_id uuid NOT NULL,
    reviewer_kind text GENERATED ALWAYS AS ('human'::text) STORED,
    reviewer_membership_version bigint NOT NULL,
    approval_class text NOT NULL,
    state text NOT NULL DEFAULT 'approved',
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    CONSTRAINT proposal_approvals_hash_size CHECK (octet_length(payload_sha256) = 32),
    CONSTRAINT proposal_approvals_membership_version_positive CHECK (
        reviewer_membership_version > 0
    ),
    CONSTRAINT proposal_approvals_class_shape CHECK (
        char_length(approval_class) BETWEEN 1 AND 80
        AND approval_class COLLATE "C" ~ '^[a-z][a-z0-9_.-]*$'
    ),
    CONSTRAINT proposal_approvals_state CHECK (state IN ('approved', 'revoked')),
    CONSTRAINT proposal_approvals_expiry CHECK (expires_at > created_at),
    CONSTRAINT proposal_approvals_revoked_time CHECK (
        (state = 'approved' AND revoked_at IS NULL)
        OR (state = 'revoked' AND revoked_at IS NOT NULL AND revoked_at >= created_at)
    ),
    CONSTRAINT proposal_approvals_exact_version_fk
        FOREIGN KEY (proposal_id, proposal_version, book_id, payload_sha256)
        REFERENCES jw.posting_proposal_versions
            (proposal_id, proposal_version, book_id, payload_sha256) ON DELETE RESTRICT,
    CONSTRAINT proposal_approvals_book_scope_fk
        FOREIGN KEY (book_id, organization_id)
        REFERENCES jw.books (id, organization_id) ON DELETE RESTRICT,
    CONSTRAINT proposal_approvals_reviewer_membership_fk
        FOREIGN KEY (organization_id, reviewer_principal_id)
        REFERENCES jw.organization_memberships (organization_id, principal_id) ON DELETE RESTRICT,
    CONSTRAINT proposal_approvals_reviewer_human_fk
        FOREIGN KEY (reviewer_principal_id, reviewer_kind)
        REFERENCES jw.principals (id, kind) ON DELETE RESTRICT,
    CONSTRAINT proposal_approvals_reviewer_class_unique
        UNIQUE (proposal_id, proposal_version, reviewer_principal_id, approval_class)
);
CREATE INDEX proposal_approvals_proposal_state_idx
    ON jw.proposal_approvals (book_id, proposal_id, proposal_version, state, expires_at);

CREATE FUNCTION jw_private.keep_business_operation_identity_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $business_operation$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'BUSINESS_OPERATION_RETAINED';
    END IF;

    IF ROW(NEW.id, NEW.book_id, NEW.organization_id, NEW.family, NEW.family_version,
           NEW.origin_namespace, NEW.business_key, NEW.request_sha256,
           NEW.primary_currency_definition_id, NEW.requested_amount, NEW.created_by, NEW.created_at)
       IS DISTINCT FROM
       ROW(OLD.id, OLD.book_id, OLD.organization_id, OLD.family, OLD.family_version,
           OLD.origin_namespace, OLD.business_key, OLD.request_sha256,
           OLD.primary_currency_definition_id, OLD.requested_amount, OLD.created_by, OLD.created_at)
       OR NEW.version <> OLD.version + 1
       OR NEW.updated_at < OLD.updated_at THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'BUSINESS_OPERATION_IDENTITY_IMMUTABLE';
    END IF;

    RETURN NEW;
END
$business_operation$;
REVOKE ALL ON FUNCTION jw_private.keep_business_operation_identity_v1() FROM PUBLIC;

CREATE TRIGGER business_operations_identity_retained
BEFORE UPDATE OR DELETE ON jw.business_operations
FOR EACH ROW EXECUTE FUNCTION jw_private.keep_business_operation_identity_v1();
CREATE TRIGGER business_operations_no_truncate
BEFORE TRUNCATE ON jw.business_operations
FOR EACH STATEMENT EXECUTE FUNCTION jw_private.reject_immutable_row_v1();

CREATE FUNCTION jw_private.keep_operation_step_identity_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $operation_step$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'OPERATION_STEP_RETAINED';
    END IF;

    IF OLD.state <> 'admitted'
       OR ROW(NEW.id, NEW.operation_id, NEW.book_id, NEW.step_key, NEW.step_kind,
              NEW.request_sha256, NEW.amount, NEW.currency_definition_id, NEW.created_at)
          IS DISTINCT FROM
          ROW(OLD.id, OLD.operation_id, OLD.book_id, OLD.step_key, OLD.step_kind,
              OLD.request_sha256, OLD.amount, OLD.currency_definition_id, OLD.created_at)
       OR NEW.state NOT IN ('accepted', 'rejected', 'cancelled') THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'OPERATION_STEP_TRANSITION_INVALID';
    END IF;

    RETURN NEW;
END
$operation_step$;
REVOKE ALL ON FUNCTION jw_private.keep_operation_step_identity_v1() FROM PUBLIC;

CREATE TRIGGER operation_steps_admit_once
BEFORE UPDATE OR DELETE ON jw.operation_steps
FOR EACH ROW EXECUTE FUNCTION jw_private.keep_operation_step_identity_v1();
CREATE TRIGGER operation_steps_no_truncate
BEFORE TRUNCATE ON jw.operation_steps
FOR EACH STATEMENT EXECUTE FUNCTION jw_private.reject_immutable_row_v1();

CREATE FUNCTION jw_private.keep_command_receipt_identity_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $command_receipt$
BEGIN
    IF TG_OP = 'DELETE' OR OLD.state <> 'admitted' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'COMMAND_RECEIPT_RETAINED';
    END IF;

    IF ROW(NEW.id, NEW.book_id, NEW.actor_principal_id, NEW.command_family,
           NEW.command_key_sha256, NEW.canonical_request_sha256, NEW.operation_id,
           NEW.step_id, NEW.created_at)
       IS DISTINCT FROM
       ROW(OLD.id, OLD.book_id, OLD.actor_principal_id, OLD.command_family,
           OLD.command_key_sha256, OLD.canonical_request_sha256, OLD.operation_id,
           OLD.step_id, OLD.created_at)
       OR NEW.state NOT IN ('accepted', 'rejected') THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'COMMAND_RECEIPT_IDENTITY_IMMUTABLE';
    END IF;

    RETURN NEW;
END
$command_receipt$;
REVOKE ALL ON FUNCTION jw_private.keep_command_receipt_identity_v1() FROM PUBLIC;

CREATE TRIGGER command_receipts_admit_once
BEFORE UPDATE OR DELETE ON jw.command_receipts
FOR EACH ROW EXECUTE FUNCTION jw_private.keep_command_receipt_identity_v1();
CREATE TRIGGER command_receipts_no_truncate
BEFORE TRUNCATE ON jw.command_receipts
FOR EACH STATEMENT EXECUTE FUNCTION jw_private.reject_immutable_row_v1();

CREATE TRIGGER economic_recognitions_append_only
BEFORE UPDATE OR DELETE ON jw.economic_recognitions
FOR EACH ROW EXECUTE FUNCTION jw_private.reject_immutable_row_v1();

CREATE TRIGGER economic_recognitions_no_truncate
BEFORE TRUNCATE ON jw.economic_recognitions
FOR EACH STATEMENT EXECUTE FUNCTION jw_private.reject_immutable_row_v1();

CREATE FUNCTION jw_private.keep_posting_template_identity_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $posting_template$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'POSTING_TEMPLATE_RETAINED';
    END IF;

    IF ROW(NEW.id, NEW.book_id, NEW.code, NEW.created_at)
       IS DISTINCT FROM ROW(OLD.id, OLD.book_id, OLD.code, OLD.created_at)
       OR (OLD.state = 'retired' AND NEW.state <> 'retired')
       OR (OLD.state = 'draft' AND NEW.state NOT IN ('draft', 'active', 'retired'))
       OR (OLD.state = 'active' AND NEW.state NOT IN ('active', 'retired')) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'POSTING_TEMPLATE_IDENTITY_IMMUTABLE';
    END IF;

    RETURN NEW;
END
$posting_template$;
REVOKE ALL ON FUNCTION jw_private.keep_posting_template_identity_v1() FROM PUBLIC;

CREATE TRIGGER posting_templates_identity_retained
BEFORE UPDATE OR DELETE ON jw.posting_templates
FOR EACH ROW EXECUTE FUNCTION jw_private.keep_posting_template_identity_v1();
CREATE TRIGGER posting_templates_no_truncate
BEFORE TRUNCATE ON jw.posting_templates
FOR EACH STATEMENT EXECUTE FUNCTION jw_private.reject_immutable_row_v1();

CREATE FUNCTION jw_private.keep_posting_template_version_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $posting_template_version$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'POSTING_TEMPLATE_VERSION_RETAINED';
    END IF;

    IF ROW(NEW.template_id, NEW.version, NEW.book_id, NEW.payload_schema_version,
           NEW.payload, NEW.payload_sha256, NEW.created_by, NEW.created_at)
       IS DISTINCT FROM
       ROW(OLD.template_id, OLD.version, OLD.book_id, OLD.payload_schema_version,
           OLD.payload, OLD.payload_sha256, OLD.created_by, OLD.created_at)
       OR (OLD.approved_at IS NOT NULL AND NEW.approved_at IS DISTINCT FROM OLD.approved_at)
       OR (OLD.approved_at IS NULL AND NEW.approved_at IS NOT NULL
           AND NEW.approved_at < OLD.created_at) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'POSTING_TEMPLATE_VERSION_IMMUTABLE';
    END IF;

    RETURN NEW;
END
$posting_template_version$;
REVOKE ALL ON FUNCTION jw_private.keep_posting_template_version_v1() FROM PUBLIC;

CREATE TRIGGER posting_template_versions_immutable_payload
BEFORE UPDATE OR DELETE ON jw.posting_template_versions
FOR EACH ROW EXECUTE FUNCTION jw_private.keep_posting_template_version_v1();
CREATE TRIGGER posting_template_versions_no_truncate
BEFORE TRUNCATE ON jw.posting_template_versions
FOR EACH STATEMENT EXECUTE FUNCTION jw_private.reject_immutable_row_v1();

CREATE TRIGGER posting_proposal_versions_append_only
BEFORE UPDATE OR DELETE ON jw.posting_proposal_versions
FOR EACH ROW EXECUTE FUNCTION jw_private.reject_immutable_row_v1();

CREATE TRIGGER posting_proposal_versions_no_truncate
BEFORE TRUNCATE ON jw.posting_proposal_versions
FOR EACH STATEMENT EXECUTE FUNCTION jw_private.reject_immutable_row_v1();

CREATE FUNCTION jw_private.keep_posting_proposal_history_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $posting_proposal$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'POSTING_PROPOSAL_RETAINED';
    END IF;

    IF ROW(NEW.id, NEW.book_id, NEW.operation_step_id, NEW.created_by, NEW.created_at)
       IS DISTINCT FROM
       ROW(OLD.id, OLD.book_id, OLD.operation_step_id, OLD.created_by, OLD.created_at)
       OR NEW.version <> OLD.version + 1
       OR NEW.current_version NOT IN (OLD.current_version, OLD.current_version + 1)
       OR (NEW.current_version = OLD.current_version + 1 AND NEW.state <> 'draft')
       OR (OLD.state = 'draft' AND NEW.state NOT IN ('draft', 'validated', 'rejected', 'cancelled'))
       OR (OLD.state = 'validated' AND NEW.state NOT IN (
           'draft', 'validated', 'approved', 'posted', 'rejected', 'cancelled'
       ))
       OR (OLD.state = 'approved' AND NEW.state NOT IN (
           'draft', 'approved', 'posted', 'rejected', 'cancelled'
       ))
       OR (OLD.state IN ('posted', 'rejected', 'cancelled') AND NEW.state <> OLD.state)
       OR (
           NEW.state = 'draft'
           AND OLD.state IN ('validated', 'approved')
           AND NEW.current_version <> OLD.current_version + 1
       )
       OR (NEW.state = OLD.state AND NEW.current_version = OLD.current_version) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'POSTING_PROPOSAL_TRANSITION_INVALID';
    END IF;

    RETURN NEW;
END
$posting_proposal$;
REVOKE ALL ON FUNCTION jw_private.keep_posting_proposal_history_v1() FROM PUBLIC;

CREATE TRIGGER posting_proposals_versioned_history
BEFORE UPDATE OR DELETE ON jw.posting_proposals
FOR EACH ROW EXECUTE FUNCTION jw_private.keep_posting_proposal_history_v1();
CREATE TRIGGER posting_proposals_no_truncate
BEFORE TRUNCATE ON jw.posting_proposals
FOR EACH STATEMENT EXECUTE FUNCTION jw_private.reject_immutable_row_v1();

CREATE FUNCTION jw_private.keep_proposal_approval_history_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $proposal_approval$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'PROPOSAL_APPROVAL_RETAINED';
    END IF;

    IF ROW(NEW.id, NEW.proposal_id, NEW.proposal_version, NEW.book_id,
           NEW.organization_id, NEW.payload_sha256, NEW.reviewer_principal_id,
           NEW.reviewer_membership_version, NEW.approval_class, NEW.created_at, NEW.expires_at)
       IS DISTINCT FROM
       ROW(OLD.id, OLD.proposal_id, OLD.proposal_version, OLD.book_id,
           OLD.organization_id, OLD.payload_sha256, OLD.reviewer_principal_id,
           OLD.reviewer_membership_version, OLD.approval_class, OLD.created_at, OLD.expires_at)
       OR (OLD.state = 'revoked' AND (
           NEW.state <> 'revoked' OR NEW.revoked_at IS DISTINCT FROM OLD.revoked_at
       ))
       OR (OLD.state = 'approved' AND NEW.state NOT IN ('approved', 'revoked'))
       OR (OLD.state = 'approved' AND NEW.state = 'approved'
           AND NEW.revoked_at IS DISTINCT FROM OLD.revoked_at) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'PROPOSAL_APPROVAL_IMMUTABLE';
    END IF;

    RETURN NEW;
END
$proposal_approval$;
REVOKE ALL ON FUNCTION jw_private.keep_proposal_approval_history_v1() FROM PUBLIC;

CREATE TRIGGER proposal_approvals_append_only
BEFORE UPDATE OR DELETE ON jw.proposal_approvals
FOR EACH ROW EXECUTE FUNCTION jw_private.keep_proposal_approval_history_v1();
CREATE TRIGGER proposal_approvals_no_truncate
BEFORE TRUNCATE ON jw.proposal_approvals
FOR EACH STATEMENT EXECUTE FUNCTION jw_private.reject_immutable_row_v1();

REVOKE ALL ON ALL TABLES IN SCHEMA jw FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA jw_api FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA jw_private FROM PUBLIC;
REVOKE CREATE ON SCHEMA jw, jw_api, jw_private, jw_support, public
    FROM PUBLIC, journalwick_runtime, journalwick_worker, journalwick_reporter;
