CREATE TABLE jw.schema_migrations (
    migration_id text PRIMARY KEY,
    checksum bytea NOT NULL,
    applied_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    source_revision text NOT NULL,
    runner_version text NOT NULL,
    CONSTRAINT schema_migrations_id_shape CHECK (
        migration_id ~ '^[0-9]{4}_[a-z0-9_]+$'
    ),
    CONSTRAINT schema_migrations_checksum_size CHECK (
        octet_length(checksum) = 32
    ),
    CONSTRAINT schema_migrations_source_revision_size CHECK (
        char_length(source_revision) BETWEEN 1 AND 64
    ),
    CONSTRAINT schema_migrations_runner_version_size CHECK (
        char_length(runner_version) BETWEEN 1 AND 64
    )
);

CREATE TABLE jw.principals (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    kind text NOT NULL,
    state text NOT NULL,
    authority_epoch bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT principals_kind CHECK (kind IN ('human', 'service')),
    CONSTRAINT principals_state CHECK (state IN ('pending', 'active', 'suspended', 'retired')),
    CONSTRAINT principals_authority_epoch_positive CHECK (authority_epoch > 0),
    CONSTRAINT principals_version_positive CHECK (version > 0),
    CONSTRAINT principals_id_kind_unique UNIQUE (id, kind)
);

CREATE TABLE jw.human_users (
    principal_id uuid PRIMARY KEY,
    principal_kind text GENERATED ALWAYS AS ('human'::text) STORED,
    login_name text NOT NULL,
    login_key text NOT NULL UNIQUE,
    display_name text NOT NULL,
    state text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT human_users_principal_kind_fk FOREIGN KEY (principal_id, principal_kind)
        REFERENCES jw.principals (id, kind) ON DELETE RESTRICT,
    CONSTRAINT human_users_login_name_length CHECK (char_length(login_name) BETWEEN 3 AND 128),
    CONSTRAINT human_users_login_key_length CHECK (char_length(login_key) BETWEEN 3 AND 128),
    CONSTRAINT human_users_display_name_length CHECK (char_length(display_name) BETWEEN 1 AND 160),
    CONSTRAINT human_users_names_no_control_chars CHECK (
        login_name !~ '[[:cntrl:]]' AND display_name !~ '[[:cntrl:]]'
    ),
    CONSTRAINT human_users_state CHECK (state IN ('pending', 'active', 'suspended', 'retired')),
    CONSTRAINT human_users_version_positive CHECK (version > 0)
);

CREATE TABLE jw.authenticators (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    principal_id uuid NOT NULL,
    principal_kind text GENERATED ALWAYS AS ('human'::text) STORED,
    credential_id bytea NOT NULL UNIQUE,
    public_verification_key bytea NOT NULL,
    sign_count bigint NOT NULL DEFAULT 0,
    state text NOT NULL,
    transports jsonb NOT NULL DEFAULT '[]'::jsonb,
    aaguid uuid,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    last_used_at timestamptz,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT authenticators_credential_id_size CHECK (
        octet_length(credential_id) BETWEEN 1 AND 1024
    ),
    CONSTRAINT authenticators_public_key_nonempty CHECK (
        octet_length(public_verification_key) > 0
    ),
    CONSTRAINT authenticators_sign_count_nonnegative CHECK (sign_count >= 0),
    CONSTRAINT authenticators_state CHECK (state IN ('pending', 'active', 'revoked')),
    CONSTRAINT authenticators_transports_array CHECK (jsonb_typeof(transports) = 'array'),
    CONSTRAINT authenticators_version_positive CHECK (version > 0),
    CONSTRAINT authenticators_human_principal_fk
        FOREIGN KEY (principal_id, principal_kind)
        REFERENCES jw.principals (id, kind) ON DELETE RESTRICT
);
CREATE INDEX authenticators_principal_state_idx
    ON jw.authenticators (principal_id, state, id);

CREATE TABLE jw.authentication_challenges (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    principal_id uuid,
    principal_kind text GENERATED ALWAYS AS ('human'::text) STORED,
    purpose text NOT NULL,
    challenge_digest bytea NOT NULL,
    browser_proof_digest bytea NOT NULL,
    requested_operation_sha256 bytea,
    state text NOT NULL,
    attempts integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    expires_at timestamptz NOT NULL,
    consumed_at timestamptz,
    CONSTRAINT authentication_challenges_purpose CHECK (
        purpose IN ('sign_in', 'enroll_authenticator', 'step_up', 'restricted_reenrollment')
    ),
    CONSTRAINT authentication_challenges_hash_sizes CHECK (
        octet_length(challenge_digest) = 32
        AND octet_length(browser_proof_digest) = 32
        AND (requested_operation_sha256 IS NULL OR octet_length(requested_operation_sha256) = 32)
    ),
    CONSTRAINT authentication_challenges_state CHECK (
        state IN ('pending', 'consumed', 'denied', 'cancelled', 'expired')
    ),
    CONSTRAINT authentication_challenges_attempts CHECK (attempts BETWEEN 0 AND 5),
    CONSTRAINT authentication_challenges_expiry CHECK (expires_at > created_at),
    CONSTRAINT authentication_challenges_lifetime CHECK (
        expires_at <= created_at + interval '3 minutes'
    ),
    CONSTRAINT authentication_challenges_pending_attempts CHECK (
        state <> 'pending' OR attempts < 5
    ),
    CONSTRAINT authentication_challenges_consumed_state CHECK (
        (state = 'consumed' AND consumed_at IS NOT NULL)
        OR (state <> 'consumed' AND consumed_at IS NULL)
    ),
    CONSTRAINT authentication_challenges_human_principal_fk
        FOREIGN KEY (principal_id, principal_kind)
        REFERENCES jw.principals (id, kind) ON DELETE RESTRICT
);
CREATE INDEX authentication_challenges_expiry_idx
    ON jw.authentication_challenges (state, expires_at, id);
CREATE INDEX authentication_challenges_principal_idx
    ON jw.authentication_challenges (principal_id, purpose, created_at DESC);

CREATE TABLE jw.native_sessions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    principal_id uuid NOT NULL,
    principal_kind text GENERATED ALWAYS AS ('human'::text) STORED,
    token_digest bytea NOT NULL UNIQUE,
    csrf_digest bytea NOT NULL,
    principal_epoch bigint NOT NULL,
    state text NOT NULL,
    authentication_method text NOT NULL,
    authenticated_at timestamptz NOT NULL,
    last_seen_at timestamptz NOT NULL,
    absolute_expires_at timestamptz NOT NULL,
    idle_expires_at timestamptz NOT NULL,
    recent_uv_at timestamptz,
    recent_operation_sha256 bytea,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    revoked_at timestamptz,
    CONSTRAINT native_sessions_token_digest_size CHECK (octet_length(token_digest) = 32),
    CONSTRAINT native_sessions_csrf_digest_size CHECK (octet_length(csrf_digest) = 32),
    CONSTRAINT native_sessions_principal_epoch_positive CHECK (principal_epoch > 0),
    CONSTRAINT native_sessions_state CHECK (state IN ('active', 'revoked')),
    CONSTRAINT native_sessions_authentication_method CHECK (authentication_method = 'passkey'),
    CONSTRAINT native_sessions_time_order CHECK (
        authenticated_at <= last_seen_at
        AND last_seen_at <= absolute_expires_at
        AND authenticated_at < absolute_expires_at
        AND authenticated_at < idle_expires_at
        AND idle_expires_at <= absolute_expires_at
        AND absolute_expires_at <= authenticated_at + interval '8 hours'
        AND idle_expires_at <= last_seen_at + interval '30 minutes'
    ),
    CONSTRAINT native_sessions_operation_digest_size CHECK (
        recent_operation_sha256 IS NULL OR octet_length(recent_operation_sha256) = 32
    ),
    CONSTRAINT native_sessions_revocation_state CHECK (
        (state = 'active' AND revoked_at IS NULL)
        OR (state = 'revoked' AND revoked_at IS NOT NULL)
    ),
    CONSTRAINT native_sessions_human_principal_fk
        FOREIGN KEY (principal_id, principal_kind)
        REFERENCES jw.principals (id, kind) ON DELETE RESTRICT
);
CREATE INDEX native_sessions_principal_state_idx
    ON jw.native_sessions (principal_id, state, absolute_expires_at);

CREATE TABLE jw.organizations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    slug text NOT NULL UNIQUE,
    display_name text NOT NULL,
    state text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT organizations_slug_shape CHECK (
        char_length(slug) BETWEEN 3 AND 80
        AND slug ~ '^[a-z0-9][a-z0-9-]{1,78}[a-z0-9]$'
    ),
    CONSTRAINT organizations_display_name_length CHECK (char_length(display_name) BETWEEN 1 AND 160),
    CONSTRAINT organizations_display_name_safe CHECK (display_name !~ '[[:cntrl:]]'),
    CONSTRAINT organizations_state CHECK (state IN ('provisioning', 'active', 'restricted', 'closed')),
    CONSTRAINT organizations_version_positive CHECK (version > 0),
    CONSTRAINT organizations_id_slug_unique UNIQUE (id, slug)
);

CREATE TABLE jw.organization_memberships (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES jw.organizations (id) ON DELETE RESTRICT,
    principal_id uuid NOT NULL,
    principal_kind text GENERATED ALWAYS AS ('human'::text) STORED,
    state text NOT NULL,
    authority_epoch bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT organization_memberships_state CHECK (
        state IN ('pending', 'active', 'suspended', 'revoked')
    ),
    CONSTRAINT organization_memberships_epoch_positive CHECK (authority_epoch > 0),
    CONSTRAINT organization_memberships_version_positive CHECK (version > 0),
    CONSTRAINT organization_memberships_identity_unique UNIQUE (organization_id, principal_id),
    CONSTRAINT organization_memberships_scope_unique UNIQUE (id, organization_id),
    CONSTRAINT organization_memberships_human_principal_fk
        FOREIGN KEY (principal_id, principal_kind)
        REFERENCES jw.principals (id, kind) ON DELETE RESTRICT
);
CREATE INDEX organization_memberships_principal_state_idx
    ON jw.organization_memberships (principal_id, state, organization_id);

CREATE TABLE jw.organization_owner_assignments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    state text NOT NULL,
    granted_by uuid NOT NULL,
    grantor_kind text GENERATED ALWAYS AS ('human'::text) STORED,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    revoked_at timestamptz,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT organization_owner_assignments_membership_fk
        FOREIGN KEY (membership_id, organization_id)
        REFERENCES jw.organization_memberships (id, organization_id) ON DELETE RESTRICT,
    CONSTRAINT organization_owner_assignments_state CHECK (state IN ('active', 'revoked')),
    CONSTRAINT organization_owner_assignments_revocation_state CHECK (
        (state = 'active' AND revoked_at IS NULL)
        OR (state = 'revoked' AND revoked_at IS NOT NULL)
    ),
    CONSTRAINT organization_owner_assignments_version_positive CHECK (version > 0),
    CONSTRAINT organization_owner_assignments_human_grantor_fk
        FOREIGN KEY (granted_by, grantor_kind)
        REFERENCES jw.principals (id, kind) ON DELETE RESTRICT
);
CREATE UNIQUE INDEX organization_owner_assignments_active_membership_uq
    ON jw.organization_owner_assignments (membership_id)
    WHERE state = 'active';
CREATE INDEX organization_owner_assignments_org_state_idx
    ON jw.organization_owner_assignments (organization_id, state, membership_id);

CREATE TABLE jw.organization_governance (
    organization_id uuid PRIMARY KEY REFERENCES jw.organizations (id) ON DELETE RESTRICT,
    authority_epoch bigint NOT NULL DEFAULT 1,
    version bigint NOT NULL DEFAULT 1,
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT organization_governance_epoch_positive CHECK (authority_epoch > 0),
    CONSTRAINT organization_governance_version_positive CHECK (version > 0)
);

CREATE TABLE jw.installation_bootstrap (
    singleton boolean PRIMARY KEY DEFAULT true,
    initialized_at timestamptz,
    bootstrap_version bigint NOT NULL DEFAULT 1,
    CONSTRAINT installation_bootstrap_singleton CHECK (singleton),
    CONSTRAINT installation_bootstrap_version_positive CHECK (bootstrap_version > 0)
);
INSERT INTO jw.installation_bootstrap (singleton, initialized_at, bootstrap_version)
VALUES (true, NULL, 1);

CREATE TABLE jw.installation_operating_state (
    singleton boolean PRIMARY KEY DEFAULT true,
    mode text NOT NULL DEFAULT 'maintenance',
    normal_financial_admission boolean NOT NULL DEFAULT false,
    dispatch_admission boolean NOT NULL DEFAULT false,
    recovery_generation bigint NOT NULL DEFAULT 1,
    version bigint NOT NULL DEFAULT 1,
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT installation_operating_state_singleton CHECK (singleton),
    CONSTRAINT installation_operating_state_mode CHECK (
        mode IN ('normal', 'maintenance', 'recovery_quarantine')
    ),
    CONSTRAINT installation_operating_state_generation_positive CHECK (recovery_generation > 0),
    CONSTRAINT installation_operating_state_version_positive CHECK (version > 0),
    CONSTRAINT installation_operating_state_quarantine_closed CHECK (
        mode <> 'recovery_quarantine'
        OR (NOT normal_financial_admission AND NOT dispatch_admission)
    )
);
INSERT INTO jw.installation_operating_state (
    singleton, mode, normal_financial_admission, dispatch_admission, recovery_generation, version
)
VALUES (true, 'maintenance', false, false, 1, 1);

CREATE TABLE jw.trusted_operator_events (
    event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_uid bigint NOT NULL,
    actor_gid bigint NOT NULL,
    operation text NOT NULL,
    target_kind text NOT NULL,
    target_id uuid,
    outcome text NOT NULL,
    request_id text NOT NULL,
    event_schema_version integer NOT NULL,
    safe_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT trusted_operator_events_uid_range CHECK (actor_uid BETWEEN 0 AND 4294967295),
    CONSTRAINT trusted_operator_events_gid_range CHECK (actor_gid BETWEEN 0 AND 4294967295),
    CONSTRAINT trusted_operator_events_operation_shape CHECK (
        char_length(operation) BETWEEN 1 AND 100
        AND operation ~ '^[a-z][a-z0-9_.-]*$'
    ),
    CONSTRAINT trusted_operator_events_target_kind_shape CHECK (
        char_length(target_kind) BETWEEN 1 AND 80
        AND target_kind ~ '^[a-z][a-z0-9_.-]*$'
    ),
    CONSTRAINT trusted_operator_events_outcome_size CHECK (char_length(outcome) BETWEEN 1 AND 40),
    CONSTRAINT trusted_operator_events_request_id_size CHECK (
        char_length(request_id) BETWEEN 1 AND 128
    ),
    CONSTRAINT trusted_operator_events_schema_version_positive CHECK (event_schema_version > 0),
    CONSTRAINT trusted_operator_events_safe_payload_object CHECK (
        jsonb_typeof(safe_payload) = 'object' AND octet_length(safe_payload::text) <= 8192
    )
);

CREATE TABLE jw.enrollment_requests (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    purpose text NOT NULL,
    browser_proof_digest bytea NOT NULL,
    confirmation_phrase_digest bytea NOT NULL,
    state text NOT NULL,
    target_principal_id uuid,
    target_principal_kind text GENERATED ALWAYS AS ('human'::text) STORED,
    organization_id uuid,
    approved_by uuid,
    approver_kind text GENERATED ALWAYS AS ('human'::text) STORED,
    approval_path text,
    trusted_operator_event_id uuid REFERENCES jw.trusted_operator_events (event_id)
        ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    expires_at timestamptz NOT NULL,
    attempts integer NOT NULL DEFAULT 0,
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT enrollment_requests_purpose CHECK (
        purpose IN ('first_enrollment', 'lost_device_reenrollment')
    ),
    CONSTRAINT enrollment_requests_digest_sizes CHECK (
        octet_length(browser_proof_digest) = 32
        AND octet_length(confirmation_phrase_digest) = 32
    ),
    CONSTRAINT enrollment_requests_state CHECK (
        state IN ('pending', 'approved', 'enrolling', 'completed', 'cancelled', 'expired')
    ),
    CONSTRAINT enrollment_requests_approval_path CHECK (
        approval_path IS NULL
        OR approval_path IN ('organization_owner', 'installation_bootstrap', 'protected_host_recovery')
    ),
    CONSTRAINT enrollment_requests_lost_device_path CHECK (
        purpose <> 'lost_device_reenrollment'
        OR approval_path IS NULL
        OR approval_path = 'protected_host_recovery'
    ),
    CONSTRAINT enrollment_requests_binding_shape CHECK (
        (
            state = 'pending'
            AND target_principal_id IS NULL
            AND organization_id IS NULL
            AND approved_by IS NULL
            AND approval_path IS NULL
            AND trusted_operator_event_id IS NULL
        )
        OR state IN ('cancelled', 'expired')
        OR (
            state IN ('approved', 'enrolling', 'completed')
            AND target_principal_id IS NOT NULL
            AND organization_id IS NOT NULL
            AND (
                (
                    approval_path = 'organization_owner'
                    AND approved_by IS NOT NULL
                    AND trusted_operator_event_id IS NULL
                )
                OR (
                    approval_path IN ('installation_bootstrap', 'protected_host_recovery')
                    AND approved_by IS NULL
                    AND trusted_operator_event_id IS NOT NULL
                )
            )
        )
    ),
    CONSTRAINT enrollment_requests_created_expiry CHECK (
        expires_at > created_at
        AND expires_at <= created_at + interval '5 minutes'
    ),
    CONSTRAINT enrollment_requests_attempts CHECK (attempts BETWEEN 0 AND 5),
    CONSTRAINT enrollment_requests_pending_attempts CHECK (
        state <> 'pending' OR attempts < 5
    ),
    CONSTRAINT enrollment_requests_version_positive CHECK (version > 0),
    CONSTRAINT enrollment_requests_target_human_fk
        FOREIGN KEY (target_principal_id, target_principal_kind)
        REFERENCES jw.principals (id, kind) ON DELETE RESTRICT,
    CONSTRAINT enrollment_requests_organization_fk
        FOREIGN KEY (organization_id) REFERENCES jw.organizations (id) ON DELETE RESTRICT,
    CONSTRAINT enrollment_requests_approver_human_fk
        FOREIGN KEY (approved_by, approver_kind)
        REFERENCES jw.principals (id, kind) ON DELETE RESTRICT
);
CREATE INDEX enrollment_requests_state_expiry_idx
    ON jw.enrollment_requests (state, expires_at, id);
CREATE INDEX enrollment_requests_target_state_idx
    ON jw.enrollment_requests (target_principal_id, state, created_at DESC);

CREATE TABLE jw.audit_events (
    event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid REFERENCES jw.organizations (id) ON DELETE RESTRICT,
    book_id uuid,
    actor_principal_id uuid,
    actor_kind text NOT NULL,
    trusted_operator_event_id uuid REFERENCES jw.trusted_operator_events (event_id)
        ON DELETE RESTRICT,
    action text NOT NULL,
    target_kind text NOT NULL,
    target_id uuid,
    outcome text NOT NULL,
    request_id text NOT NULL,
    command_receipt_id uuid,
    event_schema_version integer NOT NULL,
    safe_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT audit_events_scope_shape CHECK (book_id IS NULL OR organization_id IS NOT NULL),
    CONSTRAINT audit_events_actor_kind CHECK (
        actor_kind IN ('human', 'service', 'trusted_operator')
    ),
    CONSTRAINT audit_events_actor_reference CHECK (
        (
            actor_kind IN ('human', 'service')
            AND actor_principal_id IS NOT NULL
            AND trusted_operator_event_id IS NULL
        )
        OR (
            actor_kind = 'trusted_operator'
            AND actor_principal_id IS NULL
            AND trusted_operator_event_id IS NOT NULL
        )
    ),
    CONSTRAINT audit_events_action_shape CHECK (
        char_length(action) BETWEEN 1 AND 100 AND action ~ '^[a-z][a-z0-9_.-]*$'
    ),
    CONSTRAINT audit_events_target_kind_shape CHECK (
        char_length(target_kind) BETWEEN 1 AND 80 AND target_kind ~ '^[a-z][a-z0-9_.-]*$'
    ),
    CONSTRAINT audit_events_outcome_size CHECK (char_length(outcome) BETWEEN 1 AND 40),
    CONSTRAINT audit_events_request_id_size CHECK (char_length(request_id) BETWEEN 1 AND 128),
    CONSTRAINT audit_events_schema_version_positive CHECK (event_schema_version > 0),
    CONSTRAINT audit_events_safe_payload_object CHECK (
        jsonb_typeof(safe_payload) = 'object' AND octet_length(safe_payload::text) <= 8192
    ),
    CONSTRAINT audit_events_principal_kind_fk
        FOREIGN KEY (actor_principal_id, actor_kind)
        REFERENCES jw.principals (id, kind) ON DELETE RESTRICT
);
CREATE INDEX audit_events_org_time_idx
    ON jw.audit_events (organization_id, created_at DESC, event_id);
CREATE INDEX audit_events_book_time_idx
    ON jw.audit_events (book_id, created_at DESC, event_id);
CREATE INDEX audit_events_actor_time_idx
    ON jw.audit_events (actor_principal_id, created_at DESC, event_id);

CREATE FUNCTION jw_private.reject_immutable_row_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $immutable$
BEGIN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'IMMUTABLE_RECORD';
END
$immutable$;
REVOKE ALL ON FUNCTION jw_private.reject_immutable_row_v1() FROM PUBLIC;

CREATE FUNCTION jw_private.require_migrator_identity_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $migrator$
BEGIN
    IF session_user <> 'journalwick_migrator'
       OR current_user <> 'journalwick_kernel_owner' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'MIGRATOR_IDENTITY_REQUIRED';
    END IF;
    RETURN NEW;
END
$migrator$;
REVOKE ALL ON FUNCTION jw_private.require_migrator_identity_v1() FROM PUBLIC;

CREATE TRIGGER schema_migrations_require_migrator
BEFORE INSERT ON jw.schema_migrations
FOR EACH ROW EXECUTE FUNCTION jw_private.require_migrator_identity_v1();

CREATE TRIGGER schema_migrations_immutable_rows
BEFORE UPDATE OR DELETE ON jw.schema_migrations
FOR EACH ROW EXECUTE FUNCTION jw_private.reject_immutable_row_v1();
CREATE TRIGGER schema_migrations_immutable_truncate
BEFORE TRUNCATE ON jw.schema_migrations
FOR EACH STATEMENT EXECUTE FUNCTION jw_private.reject_immutable_row_v1();
CREATE TRIGGER audit_events_immutable_rows
BEFORE UPDATE OR DELETE ON jw.audit_events
FOR EACH ROW EXECUTE FUNCTION jw_private.reject_immutable_row_v1();
CREATE TRIGGER audit_events_immutable_truncate
BEFORE TRUNCATE ON jw.audit_events
FOR EACH STATEMENT EXECUTE FUNCTION jw_private.reject_immutable_row_v1();
CREATE TRIGGER trusted_operator_events_immutable_rows
BEFORE UPDATE OR DELETE ON jw.trusted_operator_events
FOR EACH ROW EXECUTE FUNCTION jw_private.reject_immutable_row_v1();
CREATE TRIGGER trusted_operator_events_immutable_truncate
BEFORE TRUNCATE ON jw.trusted_operator_events
FOR EACH STATEMENT EXECUTE FUNCTION jw_private.reject_immutable_row_v1();

REVOKE ALL ON ALL TABLES IN SCHEMA jw FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA jw_api FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA jw_private FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE journalwick_kernel_owner IN SCHEMA jw
    REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE journalwick_kernel_owner IN SCHEMA jw_api
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE journalwick_kernel_owner IN SCHEMA jw_private
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
GRANT SELECT ON jw.schema_migrations TO journalwick_runtime, journalwick_worker, journalwick_reporter;
