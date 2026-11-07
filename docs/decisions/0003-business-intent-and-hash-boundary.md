# Decision 0003: retain typed operation intent

The operation API accepts family-specific intent facts, and a posting template must resolve account roles from that admitted intent. A hash alone cannot recover or independently validate those facts. Draft migration `0004` therefore adds a bounded `intent_facts` object to the business operation and makes it immutable with the rest of the operation identity. Supported family validators must allowlist its fields and exclude secrets or raw provider payloads.

The initial wallet-transfer step hash binds the book, operation, step key, and admitted operation request hash. The database recomputes command, template, and proposal hashes using versioned domain prefixes and `pgcrypto` in `jw_support`.

The current canonical representation uses PostgreSQL's JSONB text representation. Cross-adapter and PostgreSQL-version compatibility have not yet been established. Before releasing migration `0004`, define and verify those bytes against independent Python and database vectors, or replace the representation with a reviewed portable format. This decision does not claim the full posting-template grammar or all operation families are implemented.
