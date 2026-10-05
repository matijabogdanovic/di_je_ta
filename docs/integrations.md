# Integration research — 2026-10-05

## OpenAI

Official sources checked:

- [ChatGPT plan usage overview](https://developers.openai.com/siwc/token-sharing-open-source)
- [Registration and sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)

The documentation describes optional ChatGPT plan usage for eligible open-source/local apps. Identity permission alone does not authorize inference. Implementation must use the documented public-client registration flow, PKCE, validated callback state/nonce and ID token, issued client ID, appropriate Responses scopes and granted direct-use permission. Do not reuse a Codex client ID or copy Codex credentials.

This supports investigating the requested path for Milestone 2; it does not establish that this unregistered native iOS app already qualifies or that every model/image feature is covered. Verify redirect support, client eligibility, permitted models/image input, the current Responses request contract and renewal behavior at implementation time. Store OAuth tokens and account credentials in iOS Keychain, never SQLite or source control. Use ASWebAuthenticationSession for an approved browser authorization flow. No API key or separately billed request is currently configured.

## Garmin

Not integrated and not a V1 blocker. Verify official Garmin authorization, developer eligibility and data access before implementing. Do not depend on unofficial password scraping. The schema supports future provider import; manual nutrition and weight work independently.
