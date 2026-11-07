# Journalwick finance console

React and TypeScript console for the Journalwick ledger API. This app uses the same browser origin as the API in development, through the Vite `/api` proxy.

## Local commands

Run the console from this directory:

```bash
npm ci --ignore-scripts
npm run dev
npm run typecheck
npm run build
npm test
```

The development server binds to `localhost:5203` with a strict port. The `/api` proxy targets `127.0.0.1:8003` without rewriting `/api/v1` paths.

## API client

Export the actual FastAPI OpenAPI document to `../../contracts/openapi.json`, then run `npm run openapi:types`. Generated code must not be edited by hand. Runtime data is validated at the browser boundary, and all monetary values remain integer strings tied to currency definitions.

The overview page currently uses clearly labeled synthetic fixture data. It does not claim live database or provider behavior.
