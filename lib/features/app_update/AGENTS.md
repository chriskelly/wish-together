# App update — Agent Guide

The startup gate that can force an outdated client onto a newer build.

## Rules

- This is a policy nudge, not a security control: a modified client can bypass it.
- The gate refuses to block when `update_url` is unusable, and fails open on a timeout.

## Reference

- The Remote Config keys, the decision record, and the runbook → `docs/app-update.md`
