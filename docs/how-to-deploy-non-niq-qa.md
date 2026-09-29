Deploy non_niq_qa_v2.sh + queue_worker.sh to vm2

1. Clone the repo
git clone git@github.com:iethes/product-taxonomy-extraction.git
cd product-taxonomy-extraction

2. Install system deps (apt names for Debian/Ubuntu; adjust for vm2's distro)
sudo apt install -y jq postgresql-client   # jq, psql
curl -LsSf https://astral.sh/uv/install.sh | sh   # uv (for the Python venv)
curl https://sdk.cloud.google.com | bash          # gcloud + bq
# claude CLI:
curl -fsSL https://claude.ai/install.sh | bash    # or your org's install method

3. Build the Python venv — non_niq_helper.py needs google-cloud-bigquery + sentence-transformers, and the scripts hardcode .venv/bin/python3:
uv sync

4. Authenticate BigQuery (service account, no interactive browser on a headless box):
gcloud auth activate-service-account openclaw@magpie-openclaw.iam.gserviceaccount.com \
  --key-file=/path/to/key.json --project=sincere-hearth-273704
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json   # put in .env too, step 6
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=csv

5. Authenticate the claude CLI itself — non_niq_qa_v2.sh runs claude -p directly, using the CLI's own logged-in session, not an API key:
claude login   # interactive once; or scp an already-authenticated ~/.claude/.c

6. Configure .env
cp .env.example .env
# .env
QUEUE_DATABASE_URL=postgres://user:password@host:port/dbname
QUEUE_SCHEMA=p4ct2g2urhzcfnz
POLL_INTERVAL_SECONDS=30
LEASE_TIMEOUT_HOURS=4
GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json
chmod 600 .env — it holds a live DB credential.

7. Sanity-check one run manually before trusting the loop:
source script/load_env.sh
script/non_niq/non_niq_qa_v2.sh cookiesbiscuit shopee ID 50 20   # small max_tu

8. Run the worker unattended (pick one):
# tmux
tmux new -s non-niq-worker -d 'source script/load_env.sh && script/non_niq/queu

# systemd (persistent service)
sudo tee /etc/systemd/system/non-niq-queue-worker.service <<'EOF'
[Unit]
Description=non_niq_qa task queue worker

[Service]
WorkingDirectory=/path/to/product-taxonomy-extraction
EnvironmentFile=/path/to/product-taxonomy-extraction/.env
ExecStart=/path/to/product-taxonomy-extraction/script/non_niq/queue_worker.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl enable --now non-niq-queue-worker

9. Verify it's claiming work
source script/load_env.sh
QUEUE_TABLE="${QUEUE_SCHEMA:-public}.task_queue"
queue_psql "SELECT id, table_name, script_type, status FROM ${QUEUE_TABLE} WHERDER BY id DESC LIMIT 10;"

skipped: task_queue row submission (that's Windmill's job per docs/non-niq-queue-submitter-handoff.md, not this deploy) → add if vm2 also needs to submit tasks, not just run them.
