# API Docs

PDF Algo Pro has no public API. This page documents internal interfaces as they are created:

- **Module interfaces.** Each Swift package documents its public protocols with DocC comments;
  generated documentation will be linked here once code exists. Module boundaries and allowed
  imports are in the [coding standards](../coding-standards.md).
- **Deep links and App Intents.** The URL scheme `pdfalgopro://` and the app's intents and
  entities are described in the [iOS architecture review](../ios-architecture-review.md).
- **Relay API (V2).** The `pdf-algo-pro-backend` relay for the opt-in Claude tier will be
  documented here when it is designed; see [AI governance](../ai-governance.md).
