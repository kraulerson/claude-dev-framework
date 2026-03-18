RULE: During the first planning phase of a project (or when discovery is reviewed), assess testing and security needs based on the project's actual risk profile. Use Superpowers brainstorming to produce a tailored test plan.

## Test Strategy

### What This Rule Requires

Testing requirements should be proportional to the project's risk profile, not applied uniformly. During the planning phase, review the project's discovery data and assess what kinds of testing are appropriate.

### When to Trigger

- First planning session on a new project (after framework installation)
- When discovery config is reviewed (90-day review prompt from session-start)
- When a significant new feature changes the project's risk surface (e.g., adding auth, payment processing, or external API integration)

### How to Assess

1. Review discovery data in `manifest.json -> discovery`:
   - `dataHandled` — what kind of data does the app process?
   - `networkExposure` — is it local, LAN, or internet-facing?
   - `authModel` — does it have users and authentication?
   - `apiIntegrations` — does it connect to external services?
   - `deploymentModel` — how is it deployed?
   - `platforms` — what platforms does it target?

2. Identify the risk surface based on what the project actually does

3. Use Superpowers brainstorming to produce a test plan appropriate to the risk level

4. Record the agreed strategy in the project as `TEST-STRATEGY.md`

### Risk Profile Examples

The brainstorming output should produce a risk assessment tailored to the project. These examples illustrate the format, not a fixed checklist:

| Project characteristic | Testing implications |
|----------------------|---------------------|
| Handles personal/sensitive data | Input validation, data encryption at rest, API key handling, privacy compliance |
| Locally hosted, single user | Functional tests, basic error handling — no auth or penetration testing needed |
| App store distribution | UI/UX testing on target devices, store compliance, crash reporting |
| Internal tool, no network exposure | Basic functional tests, content integrity |
| AI API integration | Prompt injection prevention, API key exposure, rate limit handling, fallback behavior |
| Multi-platform (e.g., iOS + Android) | Platform-specific behavior tests, shared logic consistency |
| Financial data or transactions | Payment flow testing, data integrity, audit logging, regulatory compliance |
| Multi-user with authentication | Auth flow testing, session management, privilege escalation prevention |
| Accepts user-generated content | XSS prevention, content sanitization, upload validation |

### Security Considerations

Security depth is driven by the discovery data, not a blanket requirement:
- A locally-hosted utility with no auth and no sensitive data gets basic input sanitization
- A mobile app with API keys, user accounts, and personal data gets encrypted storage, key management, and privacy compliance
- The framework prompts the assessment — the brainstorming output determines the specifics

### When to Skip

- The project already has a `TEST-STRATEGY.md` that is current
- The user explicitly says "skip test strategy"
