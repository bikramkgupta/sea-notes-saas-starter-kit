# Hot Reload Migration Status - seanotes-testing Branch

**Last Updated:** December 25, 2025  
**Branch:** `testing` (worktree: `seanotes-testing/`)  
**Repository:** `https://github.com/bikramkgupta/sea-notes-saas-starter-kit`

---

## Deployment Information

### Current App Instance
- **App ID:** `af67efb4-8f54-47dc-a0fb-91915c0530b1`
- **Component Name:** `dev-workspace`
- **App Name:** `seanotes-testing-dev`
- **Region:** `syd` (Sydney)
- **Live URL:** Check via `doctl apps get af67efb4-8f54-47dc-a0fb-91915c0530b1 -o json | jq -r '.[0].live_url'`
- **Status:** ACTIVE

### Previous App Instance (for reference)
- **App ID:** `8fc0aece-77e1-4d72-8da8-230d6cc5bd1a` (initial dev server deployment - working)
- **Component Name:** `dev-workspace`

---

## ✅ Completed Tasks

### Phase 1: Migration (Hot-Reload Expert)
1. **GitHub Actions Workflow**
   - ✅ Created `.github/workflows/deploy-app.yml` in both `main` and `testing` branches
   - ✅ Workflow supports manual trigger with `deploy`/`delete` actions
   - ✅ Auto-fills `GITHUB_REPO_URL` from repository context
   - ✅ Includes all required secrets for environment variable substitution

2. **App Platform Configuration**
   - ✅ Created `.do/app.yaml` with hot reload configuration
   - ✅ Configured for Next.js using `hot-reload-node` image
   - ✅ Set region to `syd`
   - ✅ Configured health check on port 9090 (keeps container alive for debugging)
   - ✅ App runs on port 8080
   - ✅ Added all environment variables from `application/env-example`:
     - Database: `DATABASE_URL`, `DATABASE_PROVIDER`
     - Auth: `AUTH_SECRET`
     - Storage: `SPACES_KEY_ID`, `SPACES_SECRET_KEY`, `SPACES_BUCKET_NAME`, `SPACES_REGION`, `STORAGE_PROVIDER`
     - Email: `RESEND_API_KEY`, `RESEND_EMAIL_SENDER`, `EMAIL_PROVIDER`, `ENABLE_EMAIL_INTEGRATION`
     - Billing: `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_FREE_PRICE_ID`, `STRIPE_PRO_PRICE_ID`, `STRIPE_PRO_GIFT_PRICE_ID`, `STRIPE_PORTAL_CONFIG_ID`, `BILLING_PROVIDER`
     - AI: `DO_INFERENCE_API_KEY`, `INVOICE_PROVIDER`
     - App: `BASE_URL`, `NEXT_PUBLIC_DIGITALOCEAN_GRADIENTAI_ENABLED`
   - ✅ Set `GITHUB_BRANCH: "testing"` for correct branch syncing
   - ✅ Set `DEV_START_COMMAND: "bash application/dev_startup.sh"` (app is in subfolder)

3. **Startup Scripts**
   - ✅ Created `application/dev_startup.sh` for Next.js dev server (HMR enabled)
   - ✅ Script handles dependency installation with change detection
   - ✅ Auto-restarts dev server on package.json changes
   - ✅ Configured for `application/` subfolder with `cd /workspaces/app/application`
   - ✅ Uses `npm run dev -- --hostname 0.0.0.0 --port 8080` with Turbopack

4. **Configuration Verification**
   - ✅ Verified `next.config.ts` is compatible (minimal config, no port restrictions)
   - ✅ Verified `package.json` has correct dev script: `"dev": "next dev --turbopack"`

### Phase 2: Deployment & QA
1. **Code Review**
   - ✅ Reviewed all migration changes
   - ✅ Verified environment variable mappings
   - ✅ Confirmed file paths account for `application/` subfolder

2. **Git Operations**
   - ✅ Committed all changes to `testing` branch
   - ✅ Pushed to remote repository
   - ✅ Added workflow to `main` branch (required for GitHub Actions visibility)

### Phase 3: Initial Deployment & Testing
1. **Dev Server Deployment**
   - ✅ Successfully deployed with dev server (`dev_startup.sh` with HMR)
   - ✅ Verified container stays alive even when app fails (health check on port 9090)
   - ✅ Confirmed git sync working correctly (syncing `testing` branch)
   - ✅ Verified Next.js dev server running on port 8080
   - ✅ Confirmed shell access available via do-app-sandbox

2. **Troubleshooting & Fixes**
   - ✅ Identified and fixed branch syncing issue (startup.sh was pulling from `main` instead of `GITHUB_BRANCH`)
   - ✅ Template image updated to fix container crash issue (container now stays alive for debugging)
   - ✅ Verified file structure and git sync working correctly

### Phase 4: Production Server Testing
1. **Script Update**
   - ✅ Updated `application/dev_startup.sh` to use optimized production build script
   - ✅ Script based on `dev_startup_nextjs_optimized.sh` template
   - ✅ Added `cd /workspaces/app/application || exit 1` for subfolder support
   - ✅ Script performs: `npm install` → `npm run build` → `npm run start`
   - ✅ Polls for changes and rebuilds/restarts on code changes

2. **Current Issue (In Progress)**
   - ⚠️ Production server deployment encountering issues
   - ⚠️ App ID: `af67efb4-8f54-47dc-a0fb-91915c0530b1`
   - ⚠️ Investigation needed: Check logs at https://cloud.digitalocean.com/apps/af67efb4-8f54-47dc-a0fb-91915c0530b1/logs/dev-workspace

---

## 🔄 Remaining Tasks

### 1. Production Server Deployment (In Progress)
- [ ] **Investigate production server startup issues**
  - App ID: `af67efb4-8f54-47dc-a0fb-91915c0530b1`
  - Component: `dev-workspace`
  - Check logs: `doctl apps logs af67efb4-8f54-47dc-a0fb-91915c0530b1 dev-workspace --type run --tail 50`
  - Verify script execution and identify any errors
  - Ensure `cd /workspaces/app/application` is working correctly
  - Verify `npm run build` completes successfully
  - Verify `npm run start` starts the production server

### 2. Hot Reload Verification
- [ ] **Test dependency changes**
  - Add a new dependency to `package.json`
  - Verify it's detected and installed within sync interval (15 seconds)
  - Verify server restarts automatically

- [ ] **Test code changes**
  - Make a code change in `src/` directory
  - Verify change is detected within sync interval
  - For dev server: Verify HMR works
  - For prod server: Verify rebuild and restart happens

- [ ] **Verify 30-second change detection**
  - Confirm git sync picks up changes within 15 seconds
  - Confirm build/restart completes within 30 seconds total
  - Test both dependency and code changes

### 3. Final Validation
- [ ] Verify health check endpoint responds: `/dev_health` on port 9090
- [ ] Verify app is accessible on port 8080
- [ ] Verify container stays alive even if app crashes (shell access test)
- [ ] Document any additional configuration needed

---

## 📁 Key Files

### Configuration Files
- **App Spec:** `seanotes-testing/.do/app.yaml`
- **GitHub Workflow:** `seanotes-testing/.github/workflows/deploy-app.yml` (also in `main/`)
- **Startup Script:** `seanotes-testing/application/dev_startup.sh`
- **Environment Template:** `seanotes-testing/application/env-example`

### Reference Files
- **Template:** `.reference/do-app-hot-reload-template/`
- **Sandbox SDK:** `.reference/do-app-sandbox/`
- **Reference Guide:** `.reference/reference.md`

---

## 🔧 Troubleshooting Commands

### Check App Status
```bash
doctl apps get af67efb4-8f54-47dc-a0fb-91915c0530b1 -o json | jq -r '.[0].active_deployment.phase'
```

### View Logs
```bash
doctl apps logs af67efb4-8f54-47dc-a0fb-91915c0530b1 dev-workspace --type run --tail 50 --follow
```

### Connect to Container (using do-app-sandbox)
```python
from do_app_sandbox import Sandbox
app = Sandbox.get_from_id(
    app_id="af67efb4-8f54-47dc-a0fb-91915c0530b1",
    component="dev-workspace"
)
result = app.exec("pwd")
print(result.stdout)
```

### Check Git Sync Status
```bash
doctl apps logs af67efb4-8f54-47dc-a0fb-91915c0530b1 dev-workspace --type run | grep -i "sync\|commit"
```

### Verify File Structure in Container
```python
app.exec("ls -la /workspaces/app/application/")
app.exec("cd /workspaces/app && git branch --show-current")
app.exec("test -f /workspaces/app/application/package.json && echo 'Found' || echo 'Not found'")
```

---

## 🎯 Architecture Summary

### Hot Reload Setup
- **Image:** `ghcr.io/bikramkgupta/hot-reload-node:latest`
- **Port 8080:** Application (Next.js)
- **Port 9090:** Health check (keeps container alive)
- **Git Sync:** Every 15 seconds from `testing` branch
- **Workspace:** `/workspaces/app` (repo root)
- **App Location:** `/workspaces/app/application/` (subfolder)

### Startup Flow
1. Container starts → `startup.sh` runs
2. Git sync service clones/updates repo from `testing` branch
3. Health check server starts on port 9090
4. `DEV_START_COMMAND` executes: `bash application/dev_startup.sh`
5. Script changes to `/workspaces/app/application/`
6. Installs dependencies (if needed)
7. For dev: Runs `npm run dev` (HMR)
8. For prod: Runs `npm run build` then `npm run start`
9. Script polls for changes and restarts as needed

---

## 📝 Notes

1. **Workflow Location:** GitHub Actions workflow must exist in `main` branch to be visible in Actions tab, but it can checkout any branch specified.

2. **Branch Syncing:** Fixed in template image - `startup.sh` now respects `GITHUB_BRANCH` environment variable.

3. **Container Persistence:** Template image updated to keep container alive even when app fails, enabling shell access for debugging.

4. **Subfolder Support:** All commands account for `application/` subfolder - startup script includes `cd /workspaces/app/application`.

5. **Environment Variables:** All secrets must be added to GitHub Secrets before deployment. The workflow substitutes `${SECRET_NAME}` syntax.

---

## 🚀 Next Steps

1. **Immediate:** Investigate production server deployment issue (App ID: `af67efb4-8f54-47dc-a0fb-91915c0530b1`)
2. **After Fix:** Test dependency changes (add a package, verify auto-install)
3. **After Fix:** Test code changes (modify source, verify rebuild/restart)
4. **Final:** Verify 30-second change detection works end-to-end

---

## 📚 Reference Links

- **DigitalOcean App Platform Logs:** https://cloud.digitalocean.com/apps/af67efb4-8f54-47dc-a0fb-91915c0530b1/logs/dev-workspace
- **Hot Reload Template:** `.reference/do-app-hot-reload-template/`
- **Sandbox SDK Docs:** `.reference/do-app-sandbox/docs/troubleshooting_existing_apps.md`
- **Reference Guide:** `.reference/reference.md`

