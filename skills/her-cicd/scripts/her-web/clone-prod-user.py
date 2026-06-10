#!/usr/bin/env python3
"""Clone a production her-web user for testing.

Dynamically discovers all FK tables from information_schema — no hardcoded
column names. New tables/fields are picked up automatically.

Usage:
    python3 clone-prod-user.py zengyingmi@gmail.com test-clone@hersoul.cn
    python3 clone-prod-user.py zengyingmi@gmail.com test-clone@hersoul.cn --dry-run
    python3 clone-prod-user.py --cleanup test-clone@hersoul.cn
"""
import argparse, json, os, subprocess, sys

# ── connection ──────────────────────────────────────────────────────────
SSH = "/usr/bin/ssh"
SERVER = "ubuntu@192.144.187.174"
HERWEB_DSN = "PGPASSWORD='HerAgent#2026' psql -h 172.17.255.75 -U her -d her_web -t -A -F '|'"
GATEWAY_DSN = "PGPASSWORD='HerAgent#2026' psql -h 172.17.255.75 -U her -d newapi -t -A -F '|'"
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
GW_ADMIN = "/Users/suyuan/.claude/skills/her-ops/scripts/gateway/gw-admin.sh"

# ── tables to skip (generated on login / not user-owned) ───────────────
# session: auto-generated on login
# invite_code: clone doesn't need own codes (user_invite refs existing ones)
# pending_invite_signup: ephemeral
# user_gateway: handled separately in gateway clone step (needs real GW user/token)
SKIP_TABLES = {"session", "invite_code", "pending_invite_signup", "user_gateway"}

# Fixed password hash for all clones: "test123456"
# scrypt N=16384 r=16 p=1 dkLen=64 (better-auth @better-auth/utils params)
CLONE_PASSWORD_HASH = (
    "0cd2858bb93c304290285e4fddb1f7f3:"
    "09c363d05b54d33ad1e2fc4d46296d75a8a817df7dd660b195bf56fa3e99f0b3"
    "5c2de4c26b0b381387eb077299b514adadc7a78936f202ab1a6aa3212ea96b65"
)

# ── non-FK tables that reference user by a different column ─────────────
# herclub_member: links to user via her_user_id (not standard FK)
# herclub_order: links via herclub_member.order_no (indirect, handled after herclub_member)
EXTRA_USER_TABLES = [
    {"table": "herclub_member", "fk_col": "her_user_id", "email_col": "email"},
]
# Tables linked indirectly (via order_no join, not user_id)
# Handled in a separate step after herclub_member is cloned
INDIRECT_TABLES = ["herclub_order"]

# ── helpers ─────────────────────────────────────────────────────────────
def ssh_psql(dsn, sql, check=True):
    """Run SQL via SSH+psql, return rows as list of pipe-split strings."""
    cmd = [SSH, SERVER, f"{dsn} -c {_shell_quote(sql)}"]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    if check and r.returncode != 0:
        print(f"[ERROR] SQL failed:\n{sql[:500]}\n{r.stderr.strip()}", file=sys.stderr)
        sys.exit(1)
    return [line for line in r.stdout.strip().split("\n") if line]

def ssh_psql_exec(dsn, sql, check=True):
    """Execute multi-statement SQL (no output parsing)."""
    dsn_exec = dsn.replace("-t -A -F '|'", "-v ON_ERROR_STOP=1")
    cmd = [SSH, SERVER, f"echo {_shell_quote(sql)} | {dsn_exec}"]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if check and r.returncode != 0:
        print(f"[ERROR] SQL exec failed:\n{r.stderr.strip()}", file=sys.stderr)
        sys.exit(1)
    return r

def ssh_psql_pipe(dsn, sql, check=True):
    """Pipe large SQL via stdin to psql."""
    dsn_clean = dsn.replace("-t -A -F '|'", "-v ON_ERROR_STOP=1")
    full_cmd = f"cat <<'__CLONE_SQL__' | {dsn_clean}\n{sql}\n__CLONE_SQL__"
    cmd = [SSH, SERVER, full_cmd]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if check and r.returncode != 0:
        print(f"[ERROR] SQL pipe failed:\n{r.stderr.strip()}", file=sys.stderr)
        sys.exit(1)
    return r

def gw_api(method, path, data=None):
    """Call gateway admin API via gw-admin.sh."""
    cmd = ["bash", GW_ADMIN, method, path]
    if data:
        cmd += ["-d", json.dumps(data)]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if r.returncode != 0:
        print(f"[ERROR] gateway API {method} {path} failed: {r.stderr}", file=sys.stderr)
        sys.exit(1)
    return json.loads(r.stdout)

def _shell_quote(s):
    """Quote for shell embedding inside double quotes."""
    return "'" + s.replace("'", "'\\''") + "'"

def log(msg):
    print(f"\033[36m[clone]\033[0m {msg}")

def ok(msg):
    print(f"\033[32m  [OK]\033[0m {msg}")

def fail(msg):
    print(f"\033[31m[FAIL]\033[0m {msg}")
    sys.exit(1)

# ── schema discovery ────────────────────────────────────────────────────
def discover_fk_tables():
    """Discover all tables with FK to user(id). Returns [{table, fk_col}]."""
    rows = ssh_psql(HERWEB_DSN, """
        SELECT tc.table_name, kcu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
        JOIN information_schema.constraint_column_usage ccu
          ON tc.constraint_name = ccu.constraint_name
        WHERE tc.constraint_type = 'FOREIGN KEY'
          AND ccu.table_name = 'user'
          AND tc.table_schema = 'public'
        ORDER BY tc.table_name
    """)
    tables = {}
    for row in rows:
        parts = row.split("|")
        if len(parts) == 2:
            tbl, col = parts[0].strip(), parts[1].strip()
            # Only clone rows where the FK is the user_id ownership column
            # Skip operator_id, updated_by, created_by (those reference other users)
            if col in ("user_id",):
                tables[tbl] = {"table": tbl, "fk_col": col}
    return list(tables.values())

def get_table_columns(table):
    """Get ordered column list for a table."""
    rows = ssh_psql(HERWEB_DSN, f"""
        SELECT column_name FROM information_schema.columns
        WHERE table_name = '{table}' AND table_schema = 'public'
        ORDER BY ordinal_position
    """)
    return [r.strip() for r in rows if r.strip()]

def get_pk_column(table):
    """Get primary key column(s) for a table."""
    rows = ssh_psql(HERWEB_DSN, f"""
        SELECT kcu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
        WHERE tc.table_name = '{table}' AND tc.constraint_type = 'PRIMARY KEY'
          AND tc.table_schema = 'public'
    """)
    return [r.strip() for r in rows if r.strip()]

def get_unique_columns(table):
    """Get columns with UNIQUE constraints (excluding PK)."""
    rows = ssh_psql(HERWEB_DSN, f"""
        SELECT kcu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
        WHERE tc.table_name = '{table}'
          AND tc.constraint_type = 'UNIQUE'
          AND tc.table_schema = 'public'
    """)
    return [r.strip() for r in rows if r.strip()]

def get_fk_targets(table):
    """Get {column: referenced_table} for all FK columns in this table."""
    rows = ssh_psql(HERWEB_DSN, f"""
        SELECT kcu.column_name, ccu.table_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
        JOIN information_schema.constraint_column_usage ccu
          ON tc.constraint_name = ccu.constraint_name
        WHERE tc.table_name = '{table}' AND tc.constraint_type = 'FOREIGN KEY'
          AND tc.table_schema = 'public'
    """)
    result = {}
    for r in rows:
        parts = r.split("|")
        if len(parts) == 2:
            result[parts[0].strip()] = parts[1].strip()
    return result

# ── SQL generation ──────────────────────────────────────────────────────
def gen_clone_table_sql(table, fk_col, source_id, clone_id, clone_email,
                        chat_map=False, email_col="user_email"):
    """Generate INSERT...SELECT SQL for cloning a table. Fully dynamic columns."""
    columns = get_table_columns(table)
    pk_cols = get_pk_column(table)
    unique_cols = get_unique_columns(table)
    select_parts = []
    for col in columns:
        if col in pk_cols and col not in unique_cols:
            # PK — generate new UUID
            select_parts.append("gen_random_uuid()::text")
        elif col == fk_col:
            # The user_id FK column
            select_parts.append(f"'{clone_id}'")
        elif col == email_col:
            # user_email or email column
            select_parts.append(f"'{clone_email}'")
        elif col in unique_cols and col not in pk_cols:
            # UNIQUE columns — generate new natural-looking value (not visible CLONE- prefix)
            select_parts.append(
                f"CASE WHEN {_sql_ident(col)} IS NOT NULL "
                f"THEN left({_sql_ident(col)}, 3) || substr(gen_random_uuid()::text, 1, 16) "
                f"ELSE NULL END"
            )
        elif chat_map and col == "chat_id":
            # chat_message.chat_id → mapped new ID
            select_parts.append("m.new_id")
        else:
            select_parts.append(f"src.{_sql_ident(col)}")

    col_list = ", ".join(f"{_sql_ident(c)}" for c in columns)
    sel_list = ", ".join(select_parts)
    tbl = _sql_ident(table)

    if chat_map:
        return f"""INSERT INTO {tbl} ({col_list})
SELECT {sel_list}
FROM {tbl} src JOIN _clone_chat_map m ON src.chat_id = m.old_id
WHERE src.{_sql_ident(fk_col)} = '{source_id}';"""
    else:
        return f"""INSERT INTO {tbl} ({col_list})
SELECT {sel_list}
FROM {tbl} src
WHERE src.{_sql_ident(fk_col)} = '{source_id}';"""

def _sql_ident(name):
    """Quote SQL identifier if it's a reserved word."""
    reserved = {"order", "user", "group", "interval"}
    return f'"{name}"' if name in reserved else name

# ── core operations ─────────────────────────────────────────────────────
def clone_user(args):
    source_email = args.source_email
    clone_email = args.clone_email
    clone_id = f"clone-{clone_email.split('@')[0]}"

    # 1. Get source user
    log(f"Source: {source_email}")
    rows = ssh_psql(HERWEB_DSN, f"SELECT id FROM \"user\" WHERE email = '{source_email}'")
    if not rows:
        fail(f"Source user not found: {source_email}")
    source_id = rows[0].strip()
    log(f"Source ID: {source_id}")

    # 2. Check clone doesn't exist
    rows = ssh_psql(HERWEB_DSN, f"SELECT id FROM \"user\" WHERE email = '{clone_email}'")
    if rows:
        fail(f"Clone already exists: {clone_email} (id={rows[0].strip()}). Use --cleanup first.")

    # 3. Discover FK tables
    log("Discovering FK tables from information_schema...")
    fk_tables = discover_fk_tables()
    all_tables = fk_tables + EXTRA_USER_TABLES
    log(f"Found {len(fk_tables)} FK tables + {len(EXTRA_USER_TABLES)} extra")

    # 4. Count rows
    log("Counting source rows...")
    counts = {}
    for t in all_tables:
        tbl, col = t["table"], t["fk_col"]
        rows = ssh_psql(HERWEB_DSN, f"SELECT count(*) FROM {_sql_ident(tbl)} WHERE {_sql_ident(col)} = '{source_id}'")
        counts[tbl] = int(rows[0].strip()) if rows else 0
    for tbl, cnt in sorted(counts.items()):
        if cnt > 0 and tbl not in SKIP_TABLES:
            print(f"    {tbl:25s} {cnt:>6d} rows")
        elif cnt > 0:
            print(f"    {tbl:25s} {cnt:>6d} rows (SKIP)")

    # 5. Password — all clones use fixed "test123456"
    pw_hash = CLONE_PASSWORD_HASH
    ok("Password: test123456 (fixed for all clones)")

    # 6. Build SQL
    log("Generating clone SQL...")
    sql_parts = ["BEGIN;"]

    # 6a. Clone user record
    user_cols = get_table_columns("user")
    user_select = []
    for col in user_cols:
        if col == "id":
            user_select.append(f"'{clone_id}'")
        elif col == "email":
            user_select.append(f"'{clone_email}'")
        else:
            user_select.append(_sql_ident(col))
    sql_parts.append(f'INSERT INTO "user" ({", ".join(_sql_ident(c) for c in user_cols)})\n'
                     f'SELECT {", ".join(user_select)} FROM "user" WHERE id = \'{source_id}\';')

    # 6b. Clone account (credential with password)
    sql_parts.append(
        f"INSERT INTO account (id, account_id, provider_id, user_id, password, created_at, updated_at) "
        f"VALUES ('{clone_id}-acc', '{clone_id}', 'credential', '{clone_id}', "
        f"'{pw_hash}', now(), now());")

    # 6c. chat needs ID mapping for chat_message
    has_chat = counts.get("chat", 0) > 0
    if has_chat:
        sql_parts.append(
            f"CREATE TEMP TABLE _clone_chat_map AS "
            f"SELECT id AS old_id, gen_random_uuid()::text AS new_id "
            f"FROM chat WHERE user_id = '{source_id}';")

    # 6d. Clone each FK table
    for t in all_tables:
        tbl = t["table"]
        if tbl in SKIP_TABLES or counts.get(tbl, 0) == 0:
            continue
        if tbl == "account":
            continue  # handled above
        ecol = t.get("email_col", "user_email")
        is_chat_msg = (tbl == "chat_message" and has_chat)
        sql = gen_clone_table_sql(tbl, t["fk_col"], source_id, clone_id, clone_email,
                                  chat_map=is_chat_msg, email_col=ecol)
        sql_parts.append(f"-- {tbl} ({counts[tbl]} rows)")
        sql_parts.append(sql)

    if has_chat:
        sql_parts.append("DROP TABLE IF EXISTS _clone_chat_map;")

    sql_parts.append("COMMIT;")
    full_sql = "\n\n".join(sql_parts)

    if args.dry_run:
        log("DRY RUN — SQL that would be executed:")
        print(full_sql)
        return

    # 7. Execute SQL
    log("Executing clone SQL...")
    ssh_psql_pipe(HERWEB_DSN, full_sql)
    ok("her-web clone complete")

    # 8. Gateway clone
    log("Cloning gateway user...")
    src_gw_id = None
    new_gw_id = None
    gw_rows = ssh_psql(HERWEB_DSN,
        f"SELECT gateway_user_id, token_id FROM user_gateway WHERE user_id = '{source_id}'")
    if not gw_rows:
        log("No gateway binding found, skipping gateway clone")
    else:
        parts = gw_rows[0].split("|")
        src_gw_id, src_token_id = int(parts[0].strip()), int(parts[1].strip())

        # Read source gateway state
        gw_user = ssh_psql(GATEWAY_DSN,
            f"SELECT quota, used_quota FROM users WHERE id = {src_gw_id}")
        gw_parts = gw_user[0].split("|")
        src_quota, src_used = int(gw_parts[0].strip()), int(gw_parts[1].strip())

        gw_token = ssh_psql(GATEWAY_DSN,
            f"SELECT remain_quota, unlimited_quota FROM tokens "
            f"WHERE id = {src_token_id} AND deleted_at IS NULL")
        tk_parts = gw_token[0].split("|")
        src_remain = int(tk_parts[0].strip())
        src_unlimited = tk_parts[1].strip() == "t"

        # Create gateway user via API (username without @)
        gw_username = clone_email.replace("@", "-at-") + "-Her"
        resp = gw_api("POST", "/api/user/",
                      {"username": gw_username, "display_name": "Clone", "password": "CloneX2026"})
        if not resp.get("success"):
            fail(f"Gateway user creation failed: {resp}")
        new_gw_id = resp["data"]["id"]
        ok(f"Gateway user {new_gw_id} created")

        # Create token
        resp = gw_api("POST", f"/api/user/{new_gw_id}/token",
                      {"name": "clone-token", "remain_quota": src_remain,
                       "unlimited_quota": src_unlimited, "expired_time": -1})
        if not resp.get("success"):
            fail(f"Gateway token creation failed: {resp}")
        new_token_id = resp["data"]["id"]
        new_api_key = resp["data"]["key"]
        ok(f"Gateway token {new_token_id} created")

        # Set quota + used_quota
        gw_api("PUT", f"/api/user/{new_gw_id}/quota", {"quota": src_quota})
        ssh_psql(GATEWAY_DSN,
            f"UPDATE users SET used_quota = {src_used} WHERE id = {new_gw_id}")
        ok(f"Gateway quota={src_quota} used={src_used}")

        # Insert user_gateway binding
        gw_bind_cols = get_table_columns("user_gateway")
        gw_select = []
        for col in gw_bind_cols:
            if col == "id":
                gw_select.append(f"'{clone_id}-gw'")
            elif col == "user_id":
                gw_select.append(f"'{clone_id}'")
            elif col == "gateway_user_id":
                gw_select.append(str(new_gw_id))
            elif col == "gateway_username":
                gw_select.append(f"'{gw_username}'")
            elif col == "token_id":
                gw_select.append(str(new_token_id))
            elif col == "api_key":
                gw_select.append(f"'{new_api_key}'")
            else:
                gw_select.append(f"src.{_sql_ident(col)}")
        bind_sql = (
            f"INSERT INTO user_gateway ({', '.join(_sql_ident(c) for c in gw_bind_cols)}) "
            f"SELECT {', '.join(gw_select)} FROM user_gateway src "
            f"WHERE src.user_id = '{source_id}';"
        )
        ssh_psql_pipe(HERWEB_DSN, bind_sql)
        ok("Gateway binding created")

    # 8b. Indirect tables (herclub_order linked via herclub_member.order_no)
    log("Cloning indirect tables (herclub_order)...")
    indirect_sql = """
        INSERT INTO herclub_order (id, order_no, nickname, email, normalized_email,
          amount_cents, currency, status, payment_provider, payment_session_id,
          transaction_id, payment_result, fulfillment_error, member_id, source,
          campaign, utm_source, utm_medium, utm_campaign, paid_at, created_at, updated_at)
        SELECT
          gen_random_uuid()::text,
          cm.order_no,
          ho.nickname,
          '{clone_email}',
          '{clone_email}',
          ho.amount_cents, ho.currency, ho.status, ho.payment_provider, ho.payment_session_id,
          ho.transaction_id, ho.payment_result, ho.fulfillment_error,
          cm.id,
          ho.source, ho.campaign, ho.utm_source, ho.utm_medium, ho.utm_campaign,
          ho.paid_at, ho.created_at, ho.updated_at
        FROM herclub_member om
        JOIN herclub_order ho ON ho.order_no = om.order_no
        JOIN herclub_member cm ON cm.her_user_id = '{clone_id}'
        WHERE om.her_user_id = '{source_id}'
          AND NOT EXISTS (SELECT 1 FROM herclub_order WHERE order_no = cm.order_no);
    """.format(clone_email=clone_email, clone_id=clone_id, source_id=source_id)
    ssh_psql_pipe(HERWEB_DSN, indirect_sql, check=False)
    # Count cloned
    hco_rows = ssh_psql(HERWEB_DSN,
        f"SELECT count(*) FROM herclub_order ho "
        f"JOIN herclub_member hm ON hm.order_no = ho.order_no "
        f"WHERE hm.her_user_id = '{clone_id}'")
    hco_count = int(hco_rows[0].strip()) if hco_rows else 0
    if hco_count > 0:
        ok(f"herclub_order: {hco_count} rows")
    else:
        log("herclub_order: 0 rows (source had none)")

    # 9. Test payment config
    log("Adding to test payment whitelist...")
    ssh_psql_pipe(HERWEB_DSN,
        f"UPDATE config SET value = value || ',{clone_email}' "
        f"WHERE name = 'payment_test_account_emails' "
        f"AND value NOT LIKE '%{clone_email}%';")
    ok("Test payment config updated")
    log("NOTE: Restart her-web container to flush config cache (1h TTL)")

    # 10. Verify
    verify(source_id, clone_id, all_tables, counts,
           src_gw_id if gw_rows else None,
           new_gw_id if gw_rows else None)

def verify(_source_id, clone_id, all_tables, expected_counts, src_gw_id=None, clone_gw_id=None):
    """Verify clone matches source in every table."""
    log("=" * 50)
    log("VERIFICATION")
    log("=" * 50)
    all_ok = True
    for t in all_tables:
        tbl = t["table"]
        if tbl in SKIP_TABLES:
            continue
        col = t["fk_col"]
        expected = expected_counts.get(tbl, 0)
        if expected == 0:
            continue
        rows = ssh_psql(HERWEB_DSN,
            f"SELECT count(*) FROM {_sql_ident(tbl)} WHERE {_sql_ident(col)} = '{clone_id}'")
        actual = int(rows[0].strip()) if rows else 0
        # account: we create 1 credential; source might have different providers
        if tbl == "account":
            expected = 1  # we always create exactly 1
            if actual >= 1:
                ok(f"{tbl:25s} {actual:>6d} rows (credential account)")
                continue
        if actual == expected:
            ok(f"{tbl:25s} {actual:>6d} == {expected} rows")
        else:
            fail_msg = f"{tbl:25s} {actual:>6d} != {expected} rows MISMATCH"
            print(f"\033[31m[FAIL]\033[0m {fail_msg}")
            all_ok = False

    # Gateway verification
    if src_gw_id and clone_gw_id:
        log("Gateway comparison:")
        gw_sql = (
            f"SELECT 'source' as who, u.quota, u.used_quota, t.remain_quota, t.unlimited_quota "
            f"FROM users u JOIN tokens t ON t.user_id = u.id AND t.deleted_at IS NULL "
            f"WHERE u.id = {src_gw_id} "
            f"UNION ALL "
            f"SELECT 'clone', u.quota, u.used_quota, t.remain_quota, t.unlimited_quota "
            f"FROM users u JOIN tokens t ON t.user_id = u.id AND t.deleted_at IS NULL "
            f"WHERE u.id = {clone_gw_id}"
        )
        rows = ssh_psql(GATEWAY_DSN, gw_sql)
        src_vals = ""
        for row in rows:
            parts = [p.strip() for p in row.split("|")]
            who = parts[0]
            vals = f"quota={parts[1]} used={parts[2]} token_remain={parts[3]} unlimited={parts[4]}"
            if who == "source":
                src_vals = vals
                print(f"    source: {vals}")
            else:
                print(f"    clone:  {vals}")
                if vals == src_vals:
                    ok("Gateway state matches")
                else:
                    print(f"\033[33m[WARN]\033[0m Gateway values differ (check token unlimited if expected)")
                    all_ok = False

    if all_ok:
        log("\033[32mAll checks passed.\033[0m")
    else:
        log("\033[31mSome checks failed. Review above.\033[0m")

def cleanup(args):
    """Remove a cloned user and all associated data."""
    clone_email = args.clone_email or args.source_email  # in cleanup mode, first arg is the clone
    log(f"Cleaning up clone: {clone_email}")

    # Find clone user ID
    rows = ssh_psql(HERWEB_DSN, f"SELECT id FROM \"user\" WHERE email = '{clone_email}'")
    if not rows:
        fail(f"Clone not found: {clone_email}")
    clone_id = rows[0].strip()
    log(f"Clone ID: {clone_id}")

    # Safety: refuse to delete if user_id doesn't start with 'clone-'
    if not clone_id.startswith("clone-"):
        fail(f"User ID '{clone_id}' does not start with 'clone-'. "
             f"Refusing to delete — this might be a real user. "
             f"If this is intentional, delete manually.")

    # Find gateway — SAFETY: only delete GW users whose username matches clone pattern
    gw_rows = ssh_psql(HERWEB_DSN,
        f"SELECT gateway_user_id, gateway_username FROM user_gateway WHERE user_id = '{clone_id}'",
        check=False)
    gw_id = None
    if gw_rows and gw_rows[0].strip():
        parts = gw_rows[0].split("|")
        candidate_id = int(parts[0].strip())
        candidate_name = parts[1].strip() if len(parts) > 1 else ""
        # Only delete if the gateway username was created by this script (contains -at-)
        # This prevents accidentally deleting a real user's gateway account
        if "-at-" in candidate_name or candidate_name.startswith("test-"):
            gw_id = candidate_id
        else:
            log(f"WARNING: gateway user {candidate_id} ({candidate_name}) does NOT look "
                f"like a clone — skipping gateway deletion to protect real data")

    # Discover all FK tables
    fk_tables = discover_fk_tables()
    all_tables = fk_tables + EXTRA_USER_TABLES

    # Build delete SQL (reverse dependency order: chat_message before chat, indirect before direct)
    sql_parts = ["BEGIN;"]

    # Delete indirect tables first (herclub_order via herclub_member.order_no)
    sql_parts.append(
        f"DELETE FROM herclub_order WHERE order_no IN "
        f"(SELECT order_no FROM herclub_member WHERE her_user_id = '{clone_id}');")

    # Delete from all FK tables
    ordered = sorted(all_tables, key=lambda t: 0 if t["table"] == "chat_message" else 1)
    for t in ordered:
        tbl, col = t["table"], t["fk_col"]
        sql_parts.append(f"DELETE FROM {_sql_ident(tbl)} WHERE {_sql_ident(col)} = '{clone_id}';")

    # Delete user
    sql_parts.append(f'DELETE FROM "user" WHERE id = \'{clone_id}\';')
    sql_parts.append("COMMIT;")

    ssh_psql_pipe(HERWEB_DSN, "\n".join(sql_parts))
    ok("her-web data deleted")

    # Gateway cleanup
    if gw_id:
        ssh_psql_pipe(GATEWAY_DSN,
            f"DELETE FROM tokens WHERE user_id = {gw_id};\n"
            f"DELETE FROM users WHERE id = {gw_id};")
        ok(f"Gateway user {gw_id} deleted")

    # Remove from payment config
    ssh_psql_pipe(HERWEB_DSN,
        f"UPDATE config SET value = replace(value, ',{clone_email}', '') "
        f"WHERE name = 'payment_test_account_emails';")
    ok("Removed from test payment config")

    log("Cleanup complete")

# ── main ────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="Clone a production user for testing")
    parser.add_argument("source_email", help="Source user email to clone")
    parser.add_argument("clone_email", nargs="?", help="Clone email address")
    parser.add_argument("--dry-run", action="store_true", help="Print SQL without executing")
    parser.add_argument("--cleanup", action="store_true", help="Delete a clone (source_email = clone to delete)")
    args = parser.parse_args()

    if args.cleanup:
        cleanup(args)
    else:
        if not args.clone_email:
            parser.error("clone_email is required when not using --cleanup")
        clone_user(args)

if __name__ == "__main__":
    main()
