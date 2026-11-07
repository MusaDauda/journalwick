DO $bootstrap_roles$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_roles
    WHERE rolname = 'journalwick_kernel_owner'
      AND (rolcanlogin OR rolsuper OR rolcreatedb OR rolcreaterole OR rolinherit OR rolbypassrls OR rolreplication)
  ) THEN
    RAISE EXCEPTION 'Unexpected attributes for journalwick_kernel_owner; inspect before continuing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'journalwick_kernel_owner') THEN
    CREATE ROLE journalwick_kernel_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_roles
    WHERE rolname = 'journalwick_migrator'
      AND (NOT rolcanlogin OR rolsuper OR rolcreatedb OR rolcreaterole OR rolinherit OR rolbypassrls OR rolreplication)
  ) THEN
    RAISE EXCEPTION 'Unexpected attributes for journalwick_migrator; inspect before continuing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'journalwick_migrator') THEN
    CREATE ROLE journalwick_migrator LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_roles
    WHERE rolname = 'journalwick_runtime'
      AND (NOT rolcanlogin OR rolsuper OR rolcreatedb OR rolcreaterole OR rolinherit OR rolbypassrls OR rolreplication)
  ) THEN
    RAISE EXCEPTION 'Unexpected attributes for journalwick_runtime; inspect before continuing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'journalwick_runtime') THEN
    CREATE ROLE journalwick_runtime LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_roles
    WHERE rolname = 'journalwick_worker'
      AND (NOT rolcanlogin OR rolsuper OR rolcreatedb OR rolcreaterole OR rolinherit OR rolbypassrls OR rolreplication)
  ) THEN
    RAISE EXCEPTION 'Unexpected attributes for journalwick_worker; inspect before continuing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'journalwick_worker') THEN
    CREATE ROLE journalwick_worker LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_roles
    WHERE rolname = 'journalwick_reporter'
      AND (NOT rolcanlogin OR rolsuper OR rolcreatedb OR rolcreaterole OR rolinherit OR rolbypassrls OR rolreplication)
  ) THEN
    RAISE EXCEPTION 'Unexpected attributes for journalwick_reporter; inspect before continuing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'journalwick_reporter') THEN
    CREATE ROLE journalwick_reporter LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
  END IF;
END
$bootstrap_roles$;

REVOKE ALL ON DATABASE journalwick FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

DO $bootstrap_schemas$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_namespace
    WHERE nspname IN ('jw', 'jw_api', 'jw_private', 'jw_support')
      AND nspowner <> 'journalwick_kernel_owner'::regrole
  ) THEN
    RAISE EXCEPTION 'A Journalwick schema has an unexpected owner; inspect before continuing';
  END IF;
END
$bootstrap_schemas$;

CREATE SCHEMA IF NOT EXISTS jw AUTHORIZATION journalwick_kernel_owner;
CREATE SCHEMA IF NOT EXISTS jw_api AUTHORIZATION journalwick_kernel_owner;
CREATE SCHEMA IF NOT EXISTS jw_private AUTHORIZATION journalwick_kernel_owner;
CREATE SCHEMA IF NOT EXISTS jw_support AUTHORIZATION journalwick_kernel_owner;

GRANT journalwick_kernel_owner TO journalwick_migrator;
GRANT CONNECT ON DATABASE journalwick TO journalwick_migrator, journalwick_runtime, journalwick_worker, journalwick_reporter;
GRANT USAGE ON SCHEMA jw, jw_api TO journalwick_runtime, journalwick_worker;
GRANT USAGE ON SCHEMA jw TO journalwick_reporter;

CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA jw_support;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA jw_support;

DO $verify_bootstrap$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_namespace
    WHERE nspname IN ('jw', 'jw_api', 'jw_private', 'jw_support')
      AND nspowner <> 'journalwick_kernel_owner'::regrole
  ) THEN
    RAISE EXCEPTION 'Journalwick schema ownership is not correct';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_extension e
    JOIN pg_namespace n ON n.oid = e.extnamespace
    WHERE e.extname = 'btree_gist' AND n.nspname = 'jw_support'
  ) THEN
    RAISE EXCEPTION 'btree_gist is not installed in jw_support';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_extension e
    JOIN pg_namespace n ON n.oid = e.extnamespace
    WHERE e.extname = 'pgcrypto' AND n.nspname = 'jw_support'
  ) THEN
    RAISE EXCEPTION 'pgcrypto is not installed in jw_support';
  END IF;
END
$verify_bootstrap$;
