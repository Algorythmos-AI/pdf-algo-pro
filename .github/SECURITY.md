# Security policy

This policy covers the PDF Algo Pro apps (iPhone, iPad and, later, Mac and Vision Pro), the
services they call, and this repository.

## Reporting a vulnerability

**Please don't open a public issue.** Report privately in one of these ways:

1. **GitHub private vulnerability reporting** (preferred): in this repository, go to
   **Security → Report a vulnerability**.
2. **Email** [info@algorythmos.com.au](mailto:info@algorythmos.com.au) with the subject line
   `SECURITY: pdf-algo-pro`.

Include the app version and device, the steps to reproduce, and the impact you observed. We aim to
acknowledge reports within five business days and will keep you updated until the issue is
resolved. Please give us a reasonable chance to fix the issue before disclosing it.

## Scope

In scope: the apps, their extensions and widgets, any Algorythmos service they call, and this
repository. Of particular interest: document content leaving the device without consent, redaction
that leaves recoverable content, prompt injection through document content, entitlement bypass,
and crashes on crafted PDF files.

Out of scope: denial-of-service testing, social engineering, and third-party services we don't
operate (Apple, App Store, AI providers).
