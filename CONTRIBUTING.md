# Contributing to PromptHalo

PromptHalo is an early Build in Public macOS app. Small, testable improvements are more useful than large feature expansions.

## Before opening a pull request

1. Describe the user-visible problem.
2. Keep the change focused.
3. Preserve local prompt data and existing files.
4. Run:

   ```bash
   ./run_tests.sh
   swift build
   ```

5. Explain how the behavior was verified.

## Current priorities

1. Trigger and insertion reliability
2. Accessibility permission recovery
3. Correct target-window handling
4. Prompt backup and recovery
5. Signed and notarized distribution

Please avoid adding accounts, cloud sync, prompt marketplaces, AI rewriting, or multi-layer wheels before the core interaction is reliable.

## Bug reports

Include:

- macOS version and Mac model
- PromptHalo version
- Target app
- Trigger configuration
- Exact reproduction steps
- What happened and what you expected

Never attach private prompts, clipboard contents, or credentials.
