# Agent documentation

> Verified: 2026-11-13 · Source: `3c33543` · Proof: `wolkaraforever/tools/check_agent_docs.sh`

This directory is the operational documentation for agents and contributors. Read it before changing a repository path. Human guides are independent; use the links here only to determine which user page must change with a behavior change.

## Reading order

1. Read [status](STATUS.md), [repository map](REPOSITORY_MAP.md), and the relevant catalog shard.
2. Read [architecture](ARCHITECTURE.md), [product behavior](PRODUCT_BEHAVIOR.md), and the relevant operational or test guidance.
3. Before review, refresh the catalog and run `wolkaraforever/tools/check_agent_docs.sh` and `wolkaraforever/tools/check_docs.sh`.

## Refresh when

Refresh this directory on every tracked-file change. Run `python3 wolkaraforever/tools/generate_agent_docs.py`, review its catalog descriptions, and update the linked human guide when user behavior, setup, a command, or troubleshooting changes.

## References

- [Operations](OPERATIONS.md)
- [Testing](TESTING.md)
- [Security and policy](SECURITY_AND_POLICY.md)
- [Human documentation map](HUMAN_DOCUMENTATION_MAP.md)
- [File catalog](FILE_CATALOG.md)
- [Roadmap](ROADMAP.md)
