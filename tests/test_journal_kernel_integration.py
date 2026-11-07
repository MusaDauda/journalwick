"""PostgreSQL integration checks against an explicitly selected local verification database."""

from __future__ import annotations

import hashlib
import os
import secrets
import threading
import time
import uuid
from collections.abc import Iterator
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import psycopg
import pytest
from psycopg import Connection
from psycopg.conninfo import conninfo_to_dict, make_conninfo
from psycopg.types.json import Jsonb


def verification_dsn() -> str:
    dsn = os.environ.get("JW_TEST_ADMIN_DSN")
    if not dsn:
        pytest.skip("JW_TEST_ADMIN_DSN must name a dedicated local verification database")
    parts = conninfo_to_dict(dsn)
    if (
        parts.get("host") != "127.0.0.1"
        or parts.get("port") != "55003"
        or parts.get("user") != "postgres"
        or not parts.get("dbname", "").startswith("journalwick_verify_")
    ):
        raise RuntimeError("Integration checks require a dedicated local verification database")
    return dsn


@pytest.fixture
def database() -> Iterator[Connection[Any]]:
    dsn = verification_dsn()
    parts = conninfo_to_dict(dsn)

    with psycopg.connect(dsn) as connection:
        database_name, login_role, existing_journals = connection.execute(
            "SELECT current_database(), session_user, to_regclass('jw.journals')"
        ).fetchone()
        if database_name != parts["dbname"] or login_role != "postgres" or existing_journals:
            raise RuntimeError("Verification database must have only migrations 0001 through 0003")

        try:
            connection.execute("SET LOCAL ROLE journalwick_kernel_owner")
            migration = Path("migrations/0004_journals_postings_and_financial_kernel.sql")
            connection.execute(migration.read_text(), prepare=False)
            yield connection
        finally:
            connection.rollback()


@contextmanager
def runtime(connection: Connection[Any]) -> Iterator[None]:
    connection.execute("RESET ROLE")
    connection.execute("SET LOCAL SESSION AUTHORIZATION journalwick_runtime")
    try:
        yield
    finally:
        connection.execute("RESET SESSION AUTHORIZATION")
        connection.execute("SET LOCAL ROLE journalwick_kernel_owner")


def one(connection: Connection[Any], query: str, params: tuple[Any, ...] = ()) -> Any:
    row = connection.execute(query, params).fetchone()
    assert row is not None
    return row[0]


def human(connection: Connection[Any], name: str) -> uuid.UUID:
    principal = one(
        connection,
        "INSERT INTO jw.principals (kind, state) VALUES ('human', 'active') RETURNING id",
    )
    connection.execute(
        "INSERT INTO jw.human_users (principal_id, login_name, login_key, display_name, state) "
        "VALUES (%s, %s, %s, %s, 'active')",
        (principal, name, name.lower(), name),
    )
    return principal


def wallet_template() -> dict[str, Any]:
    def role(field: str) -> dict[str, Any]:
        return {
            "currency_role": "payment",
            "classification": "liability",
            "normal_side": "credit",
            "spend_policy": "protected_customer_liability",
            "selector": {"kind": "intent_account", "field": field},
            "allowed_states": ["active"],
        }

    return {
        "schema_version": 1,
        "operation_family": "wallet_transfer",
        "currency_roles": {"payment": {"source": "operation_primary_currency"}},
        "account_roles": {
            "source_wallet": role("source_account_id"),
            "target_wallet": role("target_account_id"),
        },
        "parameters": [
            {
                "name": "transfer_amount",
                "type": "amount",
                "currency_role": "payment",
                "minimum": "1",
                "maximum": "1000000",
                "trusted_source": "operation_amount",
            }
        ],
        "evidence_policy": {"kind": "authorized_internal_intent"},
        "approval_class": "manual_distinct_reviewer",
        "lines": [
            {
                "role": "source_wallet",
                "side": "debit",
                "amount": {"op": "amount_param", "name": "transfer_amount"},
                "omit_if_zero": False,
            },
            {
                "role": "target_wallet",
                "side": "credit",
                "amount": {"op": "amount_param", "name": "transfer_amount"},
                "omit_if_zero": False,
            },
        ],
        "execution_constraints": {
            "distinct_account_roles": [["source_wallet", "target_wallet"]],
            "requires_active_book": True,
            "requires_current_projection": True,
        },
    }


@dataclass(frozen=True)
class Transfer:
    book: uuid.UUID
    actor: uuid.UUID
    reviewer: uuid.UUID
    reviewer_membership: uuid.UUID
    source: uuid.UUID
    target: uuid.UUID
    session_digest: bytes
    command_digest: bytes
    request: dict[str, Any]


def seed_transfer(
    connection: Connection[Any],
    *,
    source_balance: int = 10000,
    transfer_amount: int = 2500,
    template_payload_override: dict[str, Any] | None = None,
    append_balanced_lines: bool = False,
    invalid_step_identity: bool = False,
) -> Transfer:
    fixture_id = uuid.uuid4().hex[:12]
    actor = human(connection, f"Operator-{fixture_id}")
    reviewer = human(connection, f"Reviewer-{fixture_id}")
    organization = one(
        connection,
        "INSERT INTO jw.organizations (slug, display_name, state) "
        "VALUES (%s, 'Synthetic organization', 'active') RETURNING id",
        (f"synthetic-{fixture_id}",),
    )
    memberships = {}
    for principal in (actor, reviewer):
        memberships[principal] = one(
            connection,
            "INSERT INTO jw.organization_memberships (organization_id, principal_id, state) "
            "VALUES (%s, %s, 'active') RETURNING id",
            (organization, principal),
        )
    book = one(
        connection,
        "INSERT INTO jw.books (organization_id, code, name, state) "
        "VALUES (%s, 'SYNTHETIC', 'Synthetic book', 'active') RETURNING id",
        (organization,),
    )
    connection.execute(
        "INSERT INTO jw.book_financial_state (book_id, organization_id) VALUES (%s, %s)",
        (book, organization),
    )
    for principal, role in ((actor, "finance_operator"), (reviewer, "finance_reviewer")):
        connection.execute(
            "INSERT INTO jw.book_role_assignments "
            "(book_id, organization_id, membership_id, role, state, granted_by) "
            "VALUES (%s, %s, %s, %s, 'active', %s)",
            (book, organization, memberships[principal], role, actor),
        )
    currency = one(
        connection,
        "SELECT id FROM jw.currency_definitions WHERE code = 'USD' AND definition_version = 1",
    )

    def account(code: str, classification: str, normal_side: str, policy: str) -> uuid.UUID:
        template = one(
            connection,
            "INSERT INTO jw.account_templates "
            "(organization_id,name,template_version,classification,normal_side,spend_policy,"
            "state,payload_sha256,created_by) VALUES (%s,%s,1,%s,%s,%s,'draft',%s,%s) RETURNING id",
            (
                organization,
                code,
                classification,
                normal_side,
                policy,
                secrets.token_bytes(32),
                actor,
            ),
        )
        connection.execute(
            "INSERT INTO jw.account_template_currencies "
            "(template_id,template_version,organization_id,currency_definition_id) "
            "VALUES (%s,1,%s,%s)",
            (template, organization, currency),
        )
        connection.execute(
            "UPDATE jw.account_templates SET state = 'active' WHERE id = %s", (template,)
        )
        account_id = one(
            connection,
            "INSERT INTO jw.accounts "
            "(book_id,organization_id,code,name,currency_definition_id,template_id,template_version,"
            "classification,normal_side,spend_policy,state,created_by,activated_by) "
            "VALUES (%s,%s,%s,%s,%s,%s,1,%s,%s,%s,'active',%s,%s) RETURNING id",
            (
                book,
                organization,
                code,
                code,
                currency,
                template,
                classification,
                normal_side,
                policy,
                actor,
                reviewer,
            ),
        )
        connection.execute(
            "INSERT INTO jw.account_financial_state (account_id,book_id,currency_definition_id) "
            "VALUES (%s,%s,%s)",
            (account_id, book, currency),
        )
        return account_id

    asset = account("RECEIVABLE", "asset", "debit", "unrestricted_accounting")
    source = account("WALLET_A", "liability", "credit", "protected_customer_liability")
    target = account("WALLET_B", "liability", "credit", "protected_customer_liability")
    period = one(
        connection,
        "INSERT INTO jw.accounting_periods (book_id, starts_on, ends_before) "
        "VALUES (%s, DATE '2026-01-01', DATE '2027-01-01') RETURNING id",
        (book,),
    )
    template_id = one(
        connection,
        "INSERT INTO jw.posting_templates (book_id, code, state) "
        "VALUES (%s, 'WALLET_TRANSFER', 'active') RETURNING id",
        (book,),
    )
    template_payload = template_payload_override or wallet_template()
    template_hash = one(
        connection,
        "SELECT jw_private.posting_template_payload_sha256_v1(%s,1,%s,%s)",
        (template_id, book, Jsonb(template_payload)),
    )
    connection.execute(
        "INSERT INTO jw.posting_template_versions "
        "(template_id,version,book_id,payload_schema_version,payload,payload_sha256,created_by,"
        "created_at,approved_at) VALUES (%s,1,%s,1,%s,%s,%s,"
        "clock_timestamp()-interval '1 second',clock_timestamp())",
        (template_id, book, Jsonb(template_payload), template_hash, actor),
    )

    # The synthetic opening journal backs the starting projection used by the test.
    opening_operation = one(
        connection,
        "INSERT INTO jw.business_operations "
        "(book_id,organization_id,family,family_version,origin_namespace,business_key,request_sha256,"
        "primary_currency_definition_id,requested_amount,created_by) "
        "VALUES (%s,%s,'opening_balance',1,'fixture.opening','synthetic-opening',%s,%s,%s,%s) "
        "RETURNING id",
        (book, organization, secrets.token_bytes(32), currency, source_balance, actor),
    )
    opening_step = one(
        connection,
        "INSERT INTO jw.operation_steps (operation_id,book_id,step_key,step_kind,request_sha256) "
        "VALUES (%s,%s,'opening','recognize',%s) RETURNING id",
        (opening_operation, book, secrets.token_bytes(32)),
    )
    opening_journal = uuid.uuid4()
    for line, account_id, side in ((1, asset, "debit"), (2, source, "credit")):
        connection.execute(
            "INSERT INTO jw.postings "
            "(journal_id,line_number,book_id,account_id,currency_definition_id,"
            "side,amount,template_role) "
            "VALUES (%s,%s,%s,%s,%s,%s,%s,'opening')",
            (opening_journal, line, book, account_id, currency, side, source_balance),
        )
    connection.execute(
        "INSERT INTO jw.journals "
        "(id,book_id,organization_id,journal_sequence,state_sequence,operation_id,operation_step_id,template_id,"
        "template_version,effective_date,period_id,source_kind,payload_sha256,created_by) "
        "VALUES (%s,%s,%s,1,1,%s,%s,%s,1,DATE '2026-02-01',%s,'synthetic_opening',%s,%s)",
        (
            opening_journal,
            book,
            organization,
            opening_operation,
            opening_step,
            template_id,
            period,
            secrets.token_bytes(32),
            actor,
        ),
    )
    connection.execute(
        "UPDATE jw.operation_steps SET state='accepted',result_journal_id=%s,"
        "accepted_state_sequence=1,completed_at=clock_timestamp() WHERE id=%s",
        (opening_journal, opening_step),
    )
    connection.execute(
        "UPDATE jw.account_financial_state SET debit_total=%s,last_journal_sequence=1,"
        "last_state_sequence=1,version=2 WHERE account_id=%s",
        (source_balance, asset),
    )
    connection.execute(
        "UPDATE jw.account_financial_state SET credit_total=%s,last_journal_sequence=1,"
        "last_state_sequence=1,version=2 WHERE account_id=%s",
        (source_balance, source),
    )
    connection.execute(
        "UPDATE jw.book_financial_state SET journal_sequence=1,state_sequence=1 WHERE book_id=%s",
        (book,),
    )
    connection.execute(
        "UPDATE jw.installation_operating_state SET mode='normal',normal_financial_admission=true,"
        "dispatch_admission=false,version=version+1 WHERE singleton=true"
    )
    session_digest = secrets.token_bytes(32)
    connection.execute(
        "INSERT INTO jw.native_sessions "
        "(principal_id,token_digest,csrf_digest,principal_epoch,state,authentication_method,authenticated_at,"
        "last_seen_at,absolute_expires_at,idle_expires_at) VALUES (%s,%s,%s,1,'active','passkey',"
        "clock_timestamp()-interval '1 minute',clock_timestamp(),"
        "clock_timestamp()+interval '7 hours',"
        "clock_timestamp()+interval '20 minutes')",
        (actor, session_digest, secrets.token_bytes(32)),
    )
    connection.execute("SET CONSTRAINTS ALL IMMEDIATE")
    connection.execute("SET CONSTRAINTS ALL DEFERRED")

    admission = {
        "schema_version": 1,
        "origin_namespace": "console.wallet-transfer",
        "business_key": "synthetic-wallet-transfer",
        "family": "wallet_transfer",
        "family_version": 1,
        "primary_currency_definition_id": str(currency),
        "requested_amount": str(transfer_amount),
        "intent_facts": {"source_account_id": str(source), "target_account_id": str(target)},
    }
    with runtime(connection):
        operation = one(
            connection,
            "SELECT jw_api.admit_operation_v1(%s,%s,%s,%s,%s)",
            (book, actor, session_digest, secrets.token_bytes(32), Jsonb(admission)),
        )["operation_id"]
    step_hash = one(
        connection,
        "SELECT jw_private.wallet_transfer_step_sha256_v1(%s,%s,'recognize-1',request_sha256) "
        "FROM jw.business_operations WHERE id=%s AND book_id=%s",
        (book, operation, operation, book),
    )
    if invalid_step_identity:
        step_hash = secrets.token_bytes(32)
    step = one(
        connection,
        "INSERT INTO jw.operation_steps (operation_id,book_id,step_key,step_kind,request_sha256) "
        "VALUES (%s,%s,'recognize-1','recognize',%s) RETURNING id",
        (operation, book, step_hash),
    )
    proposal = uuid.uuid4()
    lines = [
        {
            "account_id": str(source),
            "currency_definition_id": str(currency),
            "side": "debit",
            "amount": str(transfer_amount),
            "template_role": "source_wallet",
        },
        {
            "account_id": str(target),
            "currency_definition_id": str(currency),
            "side": "credit",
            "amount": str(transfer_amount),
            "template_role": "target_wallet",
        },
    ]
    if append_balanced_lines:
        lines.extend(
            [
                {
                    "account_id": str(source),
                    "currency_definition_id": str(currency),
                    "side": "debit",
                    "amount": "1",
                    "template_role": "source_wallet",
                },
                {
                    "account_id": str(target),
                    "currency_definition_id": str(currency),
                    "side": "credit",
                    "amount": "1",
                    "template_role": "target_wallet",
                },
            ]
        )
    proposal_hash = one(
        connection,
        "SELECT jw_private.posting_proposal_payload_sha256_v1("
        "%s,1,%s,%s,1,DATE '2026-02-02',%s,%s,'[]'::jsonb)",
        (proposal, book, template_id, period, Jsonb(lines)),
    )
    connection.execute(
        "INSERT INTO jw.posting_proposals "
        "(id,book_id,operation_step_id,current_version,state,created_by) "
        "VALUES (%s,%s,%s,1,'draft',%s)",
        (proposal, book, step, actor),
    )
    connection.execute(
        "INSERT INTO jw.posting_proposal_versions "
        "(proposal_id,proposal_version,book_id,posting_template_id,posting_template_version,"
        "effective_date,period_id,canonical_lines,payload_sha256) "
        "VALUES (%s,1,%s,%s,1,DATE '2026-02-02',%s,%s,%s)",
        (proposal, book, template_id, period, Jsonb(lines), proposal_hash),
    )
    connection.execute(
        "UPDATE jw.posting_proposals SET state='validated',version=2 WHERE id=%s", (proposal,)
    )
    connection.execute(
        "UPDATE jw.posting_proposals SET state='approved',version=3 WHERE id=%s", (proposal,)
    )
    connection.execute(
        "INSERT INTO jw.proposal_approvals "
        "(proposal_id,proposal_version,book_id,organization_id,payload_sha256,reviewer_principal_id,"
        "reviewer_membership_version,approval_class,expires_at) "
        "VALUES (%s,1,%s,%s,%s,%s,1,'manual_distinct_reviewer',"
        "clock_timestamp()+interval '10 minutes')",
        (proposal, book, organization, proposal_hash, reviewer),
    )
    request = {
        "schema_version": 1,
        "operation_id": str(operation),
        "step_key": "recognize-1",
        "proposal_id": str(proposal),
        "proposal_version": 1,
        "payload_sha256": proposal_hash.hex(),
        "expected_operation_version": 1,
        "expected_proposal_envelope_version": 3,
    }
    request_hash = one(
        connection,
        "SELECT jw_private.canonical_request_sha256_v1('journal.post',1,%s,%s,%s,%s)",
        (book, operation, step, Jsonb(request)),
    )
    connection.execute(
        "UPDATE jw.native_sessions SET recent_uv_at=clock_timestamp(),recent_operation_sha256=%s "
        "WHERE token_digest=%s",
        (request_hash, session_digest),
    )
    return Transfer(
        book,
        actor,
        reviewer,
        memberships[reviewer],
        source,
        target,
        session_digest,
        secrets.token_bytes(32),
        request,
    )


def seed_second_transfer(connection: Connection[Any], first: Transfer) -> Transfer:
    proposal_id = uuid.UUID(first.request["proposal_id"])
    row = connection.execute(
        "SELECT book.organization_id,account.currency_definition_id,proposal.posting_template_id,"
        "proposal.period_id,operation.requested_amount "
        "FROM jw.posting_proposal_versions AS proposal "
        "JOIN jw.books AS book ON book.id=proposal.book_id "
        "JOIN jw.accounts AS account ON account.id=%s AND account.book_id=book.id "
        "JOIN jw.business_operations AS operation ON operation.id=%s AND operation.book_id=book.id "
        "WHERE proposal.proposal_id=%s AND proposal.proposal_version=1",
        (first.source, first.request["operation_id"], proposal_id),
    ).fetchone()
    assert row is not None
    organization, currency, template, period, amount = row
    session_digest = secrets.token_bytes(32)
    connection.execute(
        "INSERT INTO jw.native_sessions "
        "(principal_id,token_digest,csrf_digest,principal_epoch,state,authentication_method,"
        "authenticated_at,last_seen_at,absolute_expires_at,idle_expires_at) "
        "VALUES (%s,%s,%s,1,'active','passkey',clock_timestamp()-interval '1 minute',"
        "clock_timestamp(),clock_timestamp()+interval '7 hours',"
        "clock_timestamp()+interval '20 minutes')",
        (first.actor, session_digest, secrets.token_bytes(32)),
    )
    admission = {
        "schema_version": 1,
        "origin_namespace": "console.wallet-transfer",
        "business_key": "synthetic-wallet-transfer-second",
        "family": "wallet_transfer",
        "family_version": 1,
        "primary_currency_definition_id": str(currency),
        "requested_amount": str(amount),
        "intent_facts": {
            "source_account_id": str(first.source),
            "target_account_id": str(first.target),
        },
    }
    with runtime(connection):
        operation = one(
            connection,
            "SELECT jw_api.admit_operation_v1(%s,%s,%s,%s,%s)",
            (first.book, first.actor, session_digest, secrets.token_bytes(32), Jsonb(admission)),
        )["operation_id"]
    step_hash = one(
        connection,
        "SELECT jw_private.wallet_transfer_step_sha256_v1(%s,%s,'recognize-2',request_sha256) "
        "FROM jw.business_operations WHERE id=%s AND book_id=%s",
        (first.book, operation, operation, first.book),
    )
    step = one(
        connection,
        "INSERT INTO jw.operation_steps (operation_id,book_id,step_key,step_kind,request_sha256) "
        "VALUES (%s,%s,'recognize-2','recognize',%s) RETURNING id",
        (operation, first.book, step_hash),
    )
    proposal = uuid.uuid4()
    lines = [
        {
            "account_id": str(first.source),
            "currency_definition_id": str(currency),
            "side": "debit",
            "amount": str(amount),
            "template_role": "source_wallet",
        },
        {
            "account_id": str(first.target),
            "currency_definition_id": str(currency),
            "side": "credit",
            "amount": str(amount),
            "template_role": "target_wallet",
        },
    ]
    payload_hash = one(
        connection,
        "SELECT jw_private.posting_proposal_payload_sha256_v1("
        "%s,1,%s,%s,1,DATE '2026-02-02',%s,%s,'[]'::jsonb)",
        (proposal, first.book, template, period, Jsonb(lines)),
    )
    connection.execute(
        "INSERT INTO jw.posting_proposals "
        "(id,book_id,operation_step_id,current_version,state,created_by) "
        "VALUES (%s,%s,%s,1,'draft',%s)",
        (proposal, first.book, step, first.actor),
    )
    connection.execute(
        "INSERT INTO jw.posting_proposal_versions "
        "(proposal_id,proposal_version,book_id,posting_template_id,posting_template_version,"
        "effective_date,period_id,canonical_lines,payload_sha256) "
        "VALUES (%s,1,%s,%s,1,DATE '2026-02-02',%s,%s,%s)",
        (proposal, first.book, template, period, Jsonb(lines), payload_hash),
    )
    connection.execute(
        "UPDATE jw.posting_proposals SET state='validated',version=2 WHERE id=%s", (proposal,)
    )
    connection.execute(
        "UPDATE jw.posting_proposals SET state='approved',version=3 WHERE id=%s", (proposal,)
    )
    connection.execute(
        "INSERT INTO jw.proposal_approvals "
        "(proposal_id,proposal_version,book_id,organization_id,payload_sha256,reviewer_principal_id,"
        "reviewer_membership_version,approval_class,expires_at) "
        "VALUES (%s,1,%s,%s,%s,%s,1,'manual_distinct_reviewer',"
        "clock_timestamp()+interval '10 minutes')",
        (proposal, first.book, organization, payload_hash, first.reviewer),
    )
    request = {
        "schema_version": 1,
        "operation_id": str(operation),
        "step_key": "recognize-2",
        "proposal_id": str(proposal),
        "proposal_version": 1,
        "payload_sha256": payload_hash.hex(),
        "expected_operation_version": 1,
        "expected_proposal_envelope_version": 3,
    }
    request_hash = one(
        connection,
        "SELECT jw_private.canonical_request_sha256_v1('journal.post',1,%s,%s,%s,%s)",
        (first.book, operation, step, Jsonb(request)),
    )
    connection.execute(
        "UPDATE jw.native_sessions SET recent_uv_at=clock_timestamp(),recent_operation_sha256=%s "
        "WHERE token_digest=%s",
        (request_hash, session_digest),
    )
    return Transfer(
        first.book,
        first.actor,
        first.reviewer,
        first.reviewer_membership,
        first.source,
        first.target,
        session_digest,
        secrets.token_bytes(32),
        request,
    )


def test_posting_and_retry_keep_one_balanced_journal(database: Connection[Any]) -> None:
    transfer = seed_transfer(database)
    with runtime(database):
        result = one(
            database,
            "SELECT jw_api.post_proposal_v1(%s,%s,%s,%s,%s)",
            (
                transfer.book,
                transfer.actor,
                transfer.session_digest,
                transfer.command_digest,
                Jsonb(transfer.request),
            ),
        )
    database.execute("SET CONSTRAINTS ALL IMMEDIATE")
    database.execute("SET CONSTRAINTS ALL DEFERRED")
    assert result["journal_sequence"] == 2
    assert result["state_sequence"] == 2
    assert result["reused"] is False
    balances = database.execute(
        "SELECT account_id,credit_total-debit_total FROM jw.account_financial_state "
        "WHERE account_id IN (%s,%s)",
        (transfer.source, transfer.target),
    ).fetchall()
    assert dict(balances) == {transfer.source: 7500, transfer.target: 2500}

    database.execute(
        "UPDATE jw.installation_operating_state "
        "SET mode='maintenance',normal_financial_admission=false "
        "WHERE singleton=true"
    )
    database.execute(
        "UPDATE jw.native_sessions SET recent_uv_at=NULL,recent_operation_sha256=NULL "
        "WHERE token_digest=%s",
        (transfer.session_digest,),
    )
    with runtime(database):
        retry = one(
            database,
            "SELECT jw_api.post_proposal_v1(%s,%s,%s,%s,%s)",
            (
                transfer.book,
                transfer.actor,
                transfer.session_digest,
                transfer.command_digest,
                Jsonb(transfer.request),
            ),
        )
    assert retry["reused"] is True
    assert retry["result_id"] == result["result_id"]
    assert one(database, "SELECT count(*) FROM jw.journals WHERE book_id=%s", (transfer.book,)) == 2

    changed_request = {**transfer.request, "proposal_version": 2}
    with runtime(database), pytest.raises(psycopg.Error) as raised, database.transaction():
        one(
            database,
            "SELECT jw_api.post_proposal_v1(%s,%s,%s,%s,%s)",
            (
                transfer.book,
                transfer.actor,
                transfer.session_digest,
                transfer.command_digest,
                Jsonb(changed_request),
            ),
        )
    assert raised.value.diag.message_primary == "IDEMPOTENCY_CONFLICT"
    assert one(database, "SELECT count(*) FROM jw.journals WHERE book_id=%s", (transfer.book,)) == 2


def assert_rejected_without_journal(
    database: Connection[Any], transfer: Transfer, expected_code: str
) -> None:
    with runtime(database), pytest.raises(psycopg.Error) as raised, database.transaction():
        one(
            database,
            "SELECT jw_api.post_proposal_v1(%s,%s,%s,%s,%s)",
            (
                transfer.book,
                transfer.actor,
                transfer.session_digest,
                transfer.command_digest,
                Jsonb(transfer.request),
            ),
        )
    assert raised.value.diag.message_primary == expected_code
    assert one(database, "SELECT count(*) FROM jw.journals WHERE book_id=%s", (transfer.book,)) == 1
    assert (
        one(
            database,
            "SELECT count(*) FROM jw.command_receipts "
            "WHERE book_id=%s AND command_family='journal.post'",
            (transfer.book,),
        )
        == 0
    )


def test_insufficient_funds_leave_no_posting_or_receipt(database: Connection[Any]) -> None:
    transfer = seed_transfer(database, source_balance=2000)
    assert_rejected_without_journal(database, transfer, "INSUFFICIENT_AVAILABLE_FUNDS")
    balances = database.execute(
        "SELECT account_id,credit_total-debit_total FROM jw.account_financial_state "
        "WHERE account_id IN (%s,%s)",
        (transfer.source, transfer.target),
    ).fetchall()
    assert dict(balances) == {transfer.source: 2000, transfer.target: 0}


def test_reviewer_membership_change_invalidates_approval(database: Connection[Any]) -> None:
    transfer = seed_transfer(database)
    database.execute(
        "UPDATE jw.organization_memberships SET version=version+1,"
        "authority_epoch=authority_epoch+1 "
        "WHERE id=%s",
        (transfer.reviewer_membership,),
    )
    assert_rejected_without_journal(database, transfer, "APPROVAL_STALE")


def test_reviewer_role_from_another_book_does_not_authorize_posting(
    database: Connection[Any],
) -> None:
    transfer = seed_transfer(database)
    organization = one(
        database, "SELECT organization_id FROM jw.books WHERE id=%s", (transfer.book,)
    )
    database.execute(
        "UPDATE jw.book_role_assignments SET state='revoked',version=version+1 "
        "WHERE book_id=%s AND membership_id=%s AND role='finance_reviewer' AND state='active'",
        (transfer.book, transfer.reviewer_membership),
    )
    other_book = one(
        database,
        "INSERT INTO jw.books (organization_id,code,name,state) "
        "VALUES (%s,'OTHER_BOOK','Other book','active') RETURNING id",
        (organization,),
    )
    database.execute(
        "INSERT INTO jw.book_role_assignments "
        "(book_id,organization_id,membership_id,role,state,granted_by,expires_at) "
        "VALUES (%s,%s,%s,'finance_reviewer','active',%s,clock_timestamp()+interval '1 hour')",
        (other_book, organization, transfer.reviewer_membership, transfer.actor),
    )
    assert_rejected_without_journal(database, transfer, "CURRENT_FINANCIAL_ROLE_REQUIRED")


def test_template_with_null_approval_class_cannot_authorize_posting(
    database: Connection[Any],
) -> None:
    payload = wallet_template()
    payload["approval_class"] = None
    transfer = seed_transfer(database, template_payload_override=payload)
    assert_rejected_without_journal(database, transfer, "WALLET_TRANSFER_TEMPLATE_UNSUPPORTED")


def test_revoked_session_cannot_submit_a_posting(database: Connection[Any]) -> None:
    transfer = seed_transfer(database)
    database.execute(
        "UPDATE jw.native_sessions SET state='revoked',revoked_at=clock_timestamp() "
        "WHERE token_digest=%s",
        (transfer.session_digest,),
    )
    assert_rejected_without_journal(database, transfer, "CURRENT_SESSION_UNAVAILABLE")


def test_balanced_extra_lines_cannot_bypass_template_expansion(database: Connection[Any]) -> None:
    transfer = seed_transfer(database, append_balanced_lines=True)
    assert_rejected_without_journal(database, transfer, "PROPOSAL_LINES_DO_NOT_MATCH_TEMPLATE")


def test_step_up_must_bind_the_exact_posting_request(database: Connection[Any]) -> None:
    transfer = seed_transfer(database)
    database.execute(
        "UPDATE jw.native_sessions SET recent_operation_sha256=%s WHERE token_digest=%s",
        (secrets.token_bytes(32), transfer.session_digest),
    )
    assert_rejected_without_journal(database, transfer, "RECENT_OPERATION_BOUND_UV_REQUIRED")


def test_missing_account_projection_cannot_leave_a_partial_journal(
    database: Connection[Any],
) -> None:
    transfer = seed_transfer(database)
    database.execute(
        "DELETE FROM jw.account_financial_state WHERE account_id=%s", (transfer.target,)
    )
    assert_rejected_without_journal(database, transfer, "POSTING_ACCOUNT_STATE_UNAVAILABLE")


def test_step_identity_must_match_the_admitted_operation(database: Connection[Any]) -> None:
    transfer = seed_transfer(database, invalid_step_identity=True)
    assert_rejected_without_journal(database, transfer, "OPERATION_STEP_IDENTITY_CONFLICT")


def test_journal_cannot_bind_a_proposal_to_another_step(database: Connection[Any]) -> None:
    transfer = seed_transfer(database)
    operation = uuid.UUID(transfer.request["operation_id"])
    proposal = uuid.UUID(transfer.request["proposal_id"])
    payload = database.execute(
        "SELECT proposal.book_id,proposal.posting_template_id,proposal.posting_template_version,"
        "proposal.period_id,book.organization_id,account.currency_definition_id "
        "FROM jw.posting_proposal_versions AS proposal "
        "JOIN jw.books AS book ON book.id=proposal.book_id "
        "JOIN jw.accounts AS account ON account.id=%s AND account.book_id=book.id "
        "WHERE proposal.proposal_id=%s AND proposal.proposal_version=1",
        (transfer.source, proposal),
    ).fetchone()
    assert payload is not None
    book, template, template_version, period, organization, currency = payload
    with pytest.raises(psycopg.errors.ForeignKeyViolation) as raised, database.transaction():
        other_step = one(
            database,
            "INSERT INTO jw.operation_steps "
            "(operation_id,book_id,step_key,step_kind,request_sha256) "
            "VALUES (%s,%s,'other-step','recognize',%s) RETURNING id",
            (operation, book, secrets.token_bytes(32)),
        )
        journal = uuid.uuid4()
        for number, account, side in (
            (1, transfer.source, "debit"),
            (2, transfer.target, "credit"),
        ):
            database.execute(
                "INSERT INTO jw.postings "
                "(journal_id,line_number,book_id,account_id,currency_definition_id,"
                "side,amount,template_role) VALUES (%s,%s,%s,%s,%s,%s,2500,'synthetic')",
                (journal, number, book, account, currency, side),
            )
        database.execute(
            "INSERT INTO jw.journals "
            "(id,book_id,organization_id,journal_sequence,state_sequence,operation_id,"
            "operation_step_id,proposal_id,accepted_proposal_version,accepted_proposal_sha256,"
            "template_id,template_version,effective_date,period_id,source_kind,"
            "payload_sha256,created_by) "
            "VALUES (%s,%s,%s,2,2,%s,%s,%s,1,%s,%s,%s,DATE '2026-02-02',%s,"
            "'synthetic_transfer',%s,%s)",
            (
                journal,
                book,
                organization,
                operation,
                other_step,
                proposal,
                bytes.fromhex(transfer.request["payload_sha256"]),
                template,
                template_version,
                period,
                secrets.token_bytes(32),
                transfer.actor,
            ),
        )
    assert raised.value.diag.constraint_name == "journals_proposal_step_scope_fk"
    assert one(database, "SELECT count(*) FROM jw.journals WHERE book_id=%s", (book,)) == 1


def test_concurrent_distinct_spends_cannot_overdraw_the_same_wallet() -> None:
    admin_dsn = os.environ.get("JW_TEST_COMMITTED_DSN")
    if not admin_dsn:
        pytest.skip("JW_TEST_COMMITTED_DSN must name a dedicated concurrency database")
    parts = conninfo_to_dict(admin_dsn)
    if (
        parts.get("host") != "127.0.0.1"
        or parts.get("port") != "55003"
        or parts.get("user") != "postgres"
        or not parts.get("dbname", "").startswith("journalwick_verify_race_")
    ):
        raise RuntimeError("Concurrency checks require a dedicated local verification database")

    migration = Path("migrations/0004_journals_postings_and_financial_kernel.sql")
    expected_checksum = hashlib.sha256(migration.read_bytes()).digest()
    with psycopg.connect(admin_dsn) as connection:
        database_name, login_role, checksum = connection.execute(
            "SELECT current_database(),session_user,checksum FROM jw.schema_migrations "
            "WHERE migration_id='0004_journals_postings_and_financial_kernel'"
        ).fetchone()
        if database_name != parts["dbname"] or login_role != "postgres":
            raise RuntimeError("Unexpected verification database identity")
        if bytes(checksum) != expected_checksum:
            raise RuntimeError("Concurrency database has a different draft migration checksum")
        connection.execute("SET LOCAL ROLE journalwick_kernel_owner")
        first = seed_transfer(connection, source_balance=10000, transfer_amount=7000)
        second = seed_second_transfer(connection, first)
        connection.execute("SET CONSTRAINTS ALL IMMEDIATE")

    runtime_dsn = make_conninfo(admin_dsn, user="journalwick_runtime")
    barrier = threading.Barrier(2)
    names = [f"journalwick-race-{uuid.uuid4().hex}" for _ in range(2)]

    def post(transfer: Transfer, name: str) -> tuple[str, Any]:
        try:
            with psycopg.connect(
                make_conninfo(runtime_dsn, application_name=name), autocommit=True
            ) as connection:
                connection.execute("SET statement_timeout = '15s'")
                barrier.wait(timeout=5)
                result = one(
                    connection,
                    "SELECT jw_api.post_proposal_v1(%s,%s,%s,%s,%s)",
                    (
                        transfer.book,
                        transfer.actor,
                        transfer.session_digest,
                        transfer.command_digest,
                        Jsonb(transfer.request),
                    ),
                )
                return "accepted", result
        except psycopg.Error as error:
            return "rejected", error.diag.message_primary

    with psycopg.connect(admin_dsn) as blocker:
        blocker.execute("SET LOCAL ROLE journalwick_kernel_owner")
        blocker.execute(
            "SELECT book_id FROM jw.book_financial_state WHERE book_id=%s FOR UPDATE",
            (first.book,),
        )
        with ThreadPoolExecutor(max_workers=2) as executor:
            futures = [
                executor.submit(post, transfer, name)
                for transfer, name in zip((first, second), names, strict=True)
            ]
            waiting = 0
            try:
                deadline = time.monotonic() + 10
                with psycopg.connect(admin_dsn, autocommit=True) as monitor:
                    while time.monotonic() < deadline:
                        waiting = one(
                            monitor,
                            "SELECT count(*) FROM pg_stat_activity "
                            "WHERE application_name = ANY(%s) "
                            "AND state='active' AND wait_event_type='Lock'",
                            (names,),
                        )
                        if waiting == 2:
                            break
                        time.sleep(0.05)
            finally:
                blocker.commit()
            outcomes = [future.result(timeout=20) for future in futures]

    assert waiting == 2, "both requests must reach the held book lock concurrently"
    assert sorted(outcome for outcome, _ in outcomes) == ["accepted", "rejected"]
    assert [detail for outcome, detail in outcomes if outcome == "rejected"] == [
        "INSUFFICIENT_AVAILABLE_FUNDS"
    ]
    with psycopg.connect(admin_dsn) as connection:
        balances = connection.execute(
            "SELECT account_id,credit_total-debit_total FROM jw.account_financial_state "
            "WHERE account_id IN (%s,%s)",
            (first.source, first.target),
        ).fetchall()
        assert dict(balances) == {first.source: 3000, first.target: 7000}
        assert (
            one(connection, "SELECT count(*) FROM jw.journals WHERE book_id=%s", (first.book,)) == 2
        )
