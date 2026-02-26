You are a principal software architect.

Analyze this repository for reusable engineering practices, focusing only on:
- Expandability (how easy to add new modules/use-cases)
- Testability (how easy to unit/integration/e2e test)
- Clean architecture (boundaries, dependency direction, separation of concerns)

Do NOT explain business features unless needed to justify architecture points.

What to do:
1. Map the structure:
   - packages/modules and their responsibilities
   - dependency flow between modules
   - entry points (API/CLI/HTTP/workers)
2. Evaluate architecture quality:
   - modularity
   - coupling/cohesion
   - interface/abstraction design
   - configuration and environment isolation
   - error handling and observability boundaries
3. Evaluate testability:
   - test layout and strategy
   - mocking seams and dependency injection points
   - deterministic vs flaky areas
   - test pyramid balance
4. Evaluate expandability:
   - effort to add a new domain/service/integration
   - extension points and plugin-like patterns
   - likely bottlenecks and scaling pain points
5. Extract transferable patterns for other projects.

Output format:
- Architecture Map (short)
- Strengths (ranked)
- Weaknesses/Risks (ranked)
- Reusable Patterns (with “when to use / when not to use”)
- Concrete Blueprint for a new project:
  - folder structure
  - dependency rules
  - testing strategy
  - coding standards
- 30/60/90-day adoption plan
- Architecture scorecard (0–10): expandability, testability, maintainability, clarity

Constraints:
- Be evidence-based: cite files/paths for every key claim.
- Prefer practical improvements over theoretical purity.
- Keep recommendations incremental and low-risk first.
