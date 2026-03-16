RULE: When making architecture decisions, consider future platform expansion plans recorded in the project discovery.

## Future Scalability

### What This Rule Requires
During evaluation and planning phases, check `manifest.json → discovery → futurePlatforms`. If the project has stated future expansion plans, consider whether the current architectural choice:
- Keeps that option open (good)
- Makes it harder but not impossible (flag it)
- Closes it off entirely (stop and discuss)

### Examples
- Building a server API that might add mobile clients → separate API layer from business logic
- Building a CLI tool that might become a web service → don't hardcode stdin/stdout as the only interface
- Building a mobile app that might add a web dashboard → ensure the backend API is not tightly coupled to mobile-specific patterns

### When to Skip
- No future platforms recorded in discovery
- The change is purely internal and doesn't affect architecture
