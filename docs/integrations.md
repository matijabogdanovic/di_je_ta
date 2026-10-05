# Integration research and implementation — 2026-10-05

Official OpenAI documentation was checked before implementation:

- [Registration and sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
- [Models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
- [Preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)
- [Accounts and sessions](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions)
- [Images and vision](https://developers.openai.com/api/docs/guides/images-vision)
- [Structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs)

## ChatGPT authentication

Implemented public-client dynamic registration with fresh state, nonce and PKCE, a stable per-installation host identifier, the issued client ID, direct-use scopes and the public OAuth token endpoint. No copied Codex registration, client secret, backend or API key. ID tokens are signature-checked against official JWKS (RS256 and ES256), with issuer, audience, authorized party for multi-audience tokens, expiry, not-before and nonce validation. Returning registration must match the saved client and account.

Credentials are stored as an atomic Keychain record using WhenUnlockedThisDeviceOnly. Refresh preserves/rotates tokens together and uses the issued client ID. Disconnect removes the account record but retains the stable host ID. The selected model slug is a non-secret UserDefaults preference; credentials are never in SQLite, exports or logs.

`NativeChatGPTSignIn` uses ASWebAuthenticationSession with a short-lived Network.framework listener bound exclusively to 127.0.0.1, on a dynamically assigned port, at `/auth/callback`. The exact URI is reused for code exchange. The listener is stopped on callback, cancellation, backgrounding, failure or timeout, and is unrelated to future Desktop Sync. No custom scheme is substituted for the documented loopback redirect.

Important validation limit: OpenAI's documented route is for local clients and uses a loopback callback; the docs checked do not provide an iOS-specific example. This implementation compiles, but real-iPhone authentication-sheet routing and real-account eligibility have not been exercised. A successful build is not proof of successful native OAuth. If your device/browser rejects loopback, capture the visible error and resolve the supported native path; do not silently fall back to another client's credentials or a paid API key.

## Recognition

The account model catalog supplies display names and model slugs. An eligible image-capable model receives a high-detail JPEG data URL and the user's ingredient note in one request. Strict JSON schema requests per-food values, confidence and uncertainty, plus overall confidence and assumptions. Unknown hidden quantities must be described as assumptions; separate ingredients must not be counted twice.

Requests use `POST https://api.openai.com/v1/responses`, `store:false`, `stream:true`, array input and instructions; unsupported plan-flow fields are omitted. SSE parsing requires `response.completed`, rejects refusal/failure/incomplete/interrupted streams, and never saves a partial result. HTTP errors explain session, permission, model and usage-limit problems. No automatic request retries or separately billed API fallback.

The camera never writes to the photo library. Library selection uses PhotosPicker and does not request broad library access or delete original library photos. Images are redrawn at up to 1,536 pixels with source metadata stripped, JPEG encoded in memory, and never written by the app to a file, SQLite, an export, logs or URLSession disk cache. System-owned picker storage follows the OS lifecycle. App image references and pending request tasks are released on save/cancel/dismiss/background. Failed analysis leaves the in-memory image available for an explicit retry while the editor remains active.

Only reviewed meal data is authoritative. The normalized structured model response, original totals, submitted note, model and timestamp are stored only when the meal is confirmed. Correction deltas are refreshed on later edits, including removal of an estimated food. No image input or bearer token is retained in the audit.

## Garmin

Not integrated. Verify official authorization, developer eligibility and data access before implementing. No unofficial password scraping. Manual nutrition and weight work independently.
