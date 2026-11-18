# Trajectory for iPhone

Open `ios/Trajectory.xcodeproj` in Xcode 16.1 or later and choose the Trajectory scheme and an iPhone with iOS 17 or later. Xcode resolves the local TrajectoryCore package and the Plaid LinkKit binary through Swift Package Manager. With the default configuration, the app runs its four tabs locally with card imports disabled. You can use the simulator without setting up a backend or configuring Sign in with Apple.

The PWA remains available from `dist/`. To move a plan to iPhone, export **Plans JSON** from the PWA and open **Accounts & Data → Import Trajectory JSON**. Imported web spending initializes scenario targets and the phone retains its existing manual and card activity. Native backups restore both scenarios and budget history, including card activity, reconciliation, category overrides, and the sync position. Card and session credentials live outside the backup. Treat the exported JSON as private financial data. One on-device ledger is shared by every scenario in that installation. Signing out of the card service leaves this device's financial records available offline.

The monthly income assumption is annual gross salary. The model estimates take-home income using the plan's taxes and contributions. A Savings & Debt target earmarks part of the planned surplus, and actual transfers are excluded from card spending. Monthly recurring entries post on their scheduled day through today, using the last day for shorter months. Deleting a generated entry skips that occurrence. Editing a monthly rule affects occurrences that are generated later.

The native 10-year view adds scheduled major expenses and retirement cash flow when their ages fall inside the chart. The longer retirement report uses the original retirement model and shows coverage with and without the scheduled expenses. Choose **Job change** or **Extra saving** in the Trajectory chart to compare career paths against a saved scenario.

## Local backend

Use Python 3.12–3.14 and PostgreSQL. From the repository root, one way to start a disposable local database is:

```sh
docker run --name trajectory-postgres \
  -e POSTGRES_USER=trajectory -e POSTGRES_PASSWORD=trajectory \
  -e POSTGRES_DB=trajectory -p 127.0.0.1:5432:5432 -d postgres:17

cd backend
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt

export DATABASE_URL='postgresql+psycopg://trajectory:trajectory@127.0.0.1:5432/trajectory'
export APPLE_CLIENT_ID='com.example.trajectory'
export PLAID_ENV=sandbox
export PLAID_CLIENT_ID='<Plaid client ID>'
export PLAID_SECRET='<Plaid Sandbox secret>'
export PLAID_TOKEN_KEYS="$(python -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())')"

alembic upgrade head
uvicorn main:create_app --factory --host 127.0.0.1 --port 8000
```

Set a persistent encryption key before creating any connections. For key rotation, put the new Fernet key first in the comma-separated key list, retain prior keys until all tokens have been re-encrypted, and secure database backups and keys separately. The server stores Apple subjects, revocable session digests, challenges, and encrypted Plaid access tokens. It fetches transaction changes on request. The phone stores financial history and applies each cursor and its changes in one atomic file replacement.

FastAPI serves the client contract at `/openapi.json` and interactive API docs at `/docs`. The Swift client maps the auth, connection, and sync schemas in `ios/Trajectory/CardImports.swift`. A reverse proxy with trusted TLS can forward to port 8000. Use an HTTPS URL the iPhone can reach. Keep environment secrets on the server.

## Sign in with Apple and Plaid Sandbox

1. After enrolling in the Apple Developer Program, register an App ID for your bundle identifier and enable Sign in with Apple. Select your development team in Xcode and provision the app. Copy `ios/Local.xcconfig.example` to `ios/Local.xcconfig`, enter your team, bundle ID, and HTTPS backend URL, and enable the supplied entitlements through that configuration. Set `APPLE_CLIENT_ID` to the same bundle identifier. [Apple identity token verification](https://developer.apple.com/documentation/signinwithapple/verifying-a-user)
2. Set up the Plaid Sandbox keys and enable Transactions for testing. Start the backend, install the app on your device, open **Accounts & Data**, and sign in with Apple. Choose **Link a credit card**, select a Sandbox institution with a credit card and use Plaid's test credentials. Verify the connection, its last successful sync, and the imported activity. The initial history may take more than one sync to appear. [Plaid Link for iOS](https://plaid.com/docs/link/ios/) · [Sandbox testing](https://plaid.com/docs/sandbox/)
3. Pull to refresh twice and verify that posted totals stay stable. Test a pending-to-posted transition, a refund, a payment, and a category override. Match a manual expense to a card purchase and confirm it counts once after posting. Background and foreground the app to check automatic sync. Test **Reconnect** in Link update mode, then **Disconnect**. The previously imported activity remains available on the device. [Transactions Sync](https://plaid.com/docs/api/products/transactions/)
4. Repeat with a second Apple account on a separate device or clean installation. Its connection list should contain only its own Items. Exercise the app airplane-mode workflow, light and dark appearance, larger accessibility text sizes, chart scrubbing, and CSV and JSON sharing. For a reliable offline budget test, force-quit and reopen before re-enabling connectivity.

## Live card connections and distribution

Request Plaid Production access for Transactions. Configure a production PostgreSQL database, HTTPS server, production Plaid credentials, durable encryption keys, request rate limits, and monitoring. Set `PLAID_ENV=production` on that deployment and use a separate backend and database from Sandbox. For OAuth institutions, configure a registered HTTPS redirect URI in the Plaid Dashboard and `PLAID_REDIRECT_URI` on the server. Enable Associated Domains, add the domain to the app's entitlements (a local copy can be referenced using `TRAJECTORY_ENTITLEMENTS`), and host the Apple App Site Association file for your team and app ID. Test OAuth and reconnect on a physical iPhone with the resulting provisioning profile. [Plaid OAuth setup](https://plaid.com/docs/link/oauth/)

Before distributing through TestFlight or the App Store, configure your App Store Connect record and test the signed archive. Review privacy disclosures and account-deletion requirements for your release. The PWA can continue to be deployed independently from `dist/`.

## Automated checks

```sh
node test.js
swift test --package-path native
cd backend
python -m pytest
```

The Swift suite compares all forecast percentiles with fixtures from the bundled JavaScript engine and checks retirement, legacy normalization, native backup restore, recurring entries, overspending, and card reconciliation. The backend tests use SQLite and controlled Apple and Plaid responses for ownership and sync behavior. Run the PostgreSQL migration and the iPhone Sandbox flow separately to verify the deployed integration.
