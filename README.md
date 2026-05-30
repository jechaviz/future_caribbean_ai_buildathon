# Future Caribbean AI Buildathon Product Tools

Vlang services, dataset generation, QA and submission automation for
`Caribbean Coordination Desk`.

## Commands

```powershell
v -path "C:/git/v_projects/lib|@vlib|@vmodules" run cmd/fcbuild -- generate
v -path "C:/git/v_projects/lib|@vlib|@vmodules" run cmd/fcbuild -- qa
v -path "C:/git/v_projects/lib|@vlib|@vmodules" run cmd/fcbuild -- form --dry-run --allow-placeholders
v -path "C:/git/v_projects/lib|@vlib|@vmodules" run cmd/fcbuild -- serve --site C:/git/websites/future_caribbean_ai_buildathon
```

Real external form submission is gated by `APPLICATION_CONSENT_TO_SUBMIT=yes`
and by non-placeholder applicant fields.
