# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

MOVEX Change Data Capture: captures Insert/Update/Delete events in relational databases via
**table-level triggers** (not redo/WAL log mining) and transfers them to Kafka. Rails 8 API-only
backend on **JRuby** (Java interop is used throughout — JDBC, Kafka java client), Vue 3 frontend,
shipped as a single Docker image.

Supported DBs: **Oracle** (12.2+, production target) and **SQLITE** (keeps the product DB-independent,
used for fast CI). Almost every DB-touching code path has both variants — see "DB abstraction" below.

## Runtime prerequisites

- Ruby is **JRuby** (`.ruby-version`, currently `jruby-10.1.1.0`); the `ruby` directive in the Gemfile
  is the JRuby-reported version (`4.0.0`), not MRI. Gems install to `vendor/bundle` (`.bundle/config`).
- `RAILS_MAX_THREADS` must be set (except in `test`) and must exceed
  `INITIAL_WORKER_THREADS + THREADS_FOR_API_REQUESTS + 10`; startup raises otherwise. It also sizes the
  AR connection pool (`config/database.yml`).
- `DB_TYPE` (`ORACLE`/`SQLITE`) must be set — many classes dispatch on
  `MovexCdc::Application.config.db_type` and raise on unknown values.
- Oracle JDBC jars live in `lib/*.jar`, Kafka client jars in `lib/kafka/*.jar` (checked into the repo,
  versions documented in `lib/kafka/README.md`).

## Workflow Rules

- **Always ask for confirmation before running `git commit` or `git push`.**

## Commands

Backend (JRuby, from repo root):

```bash
bundle install --jobs 1        # do NOT parallelize: race condition in ruby-maven-libs
bundle exec rails db:migrate   # no schema.rb load — migrations are the source of truth
bundle exec rails test                                   # whole suite
bundle exec rails test test/models/table_test.rb         # single file
bundle exec rails test test/models/table_test.rb:42      # single test by line
bundle exec rails test -n /pattern/                      # by name
DB_TYPE=SQLITE RAILS_ENV=test bundle exec rails test     # typical local invocation
```

Frontend (`frontend/`, Node 20.19+/22.12+, Vite + Vitest):

```bash
npm ci
npm run dev        # dev server on :8080, backend URL via VITE_BACKEND_URL
npm run test:unit  # vitest
npm run lint       # eslint --fix
npm run build
```

Project-specific rake tasks (`lib/tasks/`), mostly CI/Oracle preparation:

```bash
bundle exec rake "ci_preparation:wait_for_db_available[10]"
bundle exec rake ci_preparation:create_user               # creates test + victim Oracle users
bundle exec rake ci_preparation:reset_test_tables
bundle exec rake ci_preparation:speedup_oracle_dictionary_calls
bundle exec rake test:run_integration_test RAILS_ENV=development   # drives the built Docker image
```

Local dev via containers: `docker-compose -f docker/dev_docker-compose.yml up -d`
(frontend :8080, backend :3000, SQLITE).

Docs are AsciiDoc: `asciidoctor -o doc/movex-cdc.html doc/movex-cdc.adoc`.

## Configuration model

All runtime config flows through `config/application.rb`, which is unusually load-bearing — read it first
when touching configuration. Precedence: defaults in `set_attrib_from_env` < `config/run_config.yml`
(path overridable by `RUN_CONFIG`) < environment variables (upper-cased attribute name). Every attribute
is registered in `@@config_attributes` (default vs. startup value) and echoed to stdout at boot with
passwords masked. Validation (`:minimum`, `:maximum`, `:integer`, `accept_empty`) happens here, so adding
a config option means adding one `set_and_log_attrib_from_env` line plus a comment block in
`config/run_config.yml`.

In `RAILS_ENV=test` the config layer rewrites `DB_USER` to `test_<db_user>` to protect
development/production schemas, and supplies fixed test passwords.

## Architecture

Event flow: DB trigger → `EVENT_LOGS` table → worker thread → Kafka topic.

- **Trigger generation** — `DbTrigger` is a thin dispatcher (`method_missing` + `METHODS_TO_DELEGATE`)
  onto `DbTriggerGeneratorOracle` / `DbTriggerGeneratorSqlite`, both extending `DbTriggerGeneratorBase`.
  Trigger names are built by `build_trigger_name` from schema/table IDs *and* name checksums so they stay
  unique across export/reimport. Config (`Schema`, `Table`, `Column`, `Condition`, `ColumnExpression`)
  is what the generator compiles into trigger PL/SQL.
- **Transfer** — `ThreadHandling` is a singleton pool manager; `SystemValidationJob` calls
  `ensure_processing` every `SYSTEM_VALIDATION_JOB_CYCLE` seconds to grow/shrink the pool to
  `INITIAL_WORKER_THREADS`. Each `TransferThread` reads a batch from `EVENT_LOGS` (bounded by
  `MAX_TRANSACTION_SIZE`, with a self-tuning ID-distance window), produces to Kafka inside a Kafka
  transaction, then deletes the rows. Failures land in `EVENT_LOG_FINAL_ERRORS` after
  `ERROR_MAX_RETRIES`.
- **Kafka** — `KafkaBase.create` picks `KafkaJava` (real java client, `KAFKA_CLIENT_LIBRARY=java`) or
  `KafkaMock` (`=mock`, used by part of CI). `KafkaBase::Producer` holds the library-independent logic,
  including auto-enlarging a topic's `max.message.bytes` on MessageSizeTooLarge.
- **Initial load** — `TableInitialization` (singleton) queues per-table full-content transfers issued at
  first trigger creation, capped by `MAX_SIMULTANEOUS_TABLE_INITIALIZATIONS`, executed in
  `TableInitializationThread`s.
- **Housekeeping / statistics** — `Housekeeping` (singleton, driven by `SystemValidationJob`) drops old
  Oracle partitions of `EVENT_LOGS`; `HourlyJob` runs `HousekeepingFinalErrors`, `DailyJob` runs
  `CompressStatistics`. `StatisticCounter` / `StatisticCounterConcentrator` accumulate per-thread
  counters into `Statistics`.
- **Jobs** — `InitializationJob` runs once at boot, kicked off from `config.ru` (not from an initializer,
  deliberately: initialization must complete before classes are used). It validates Kafka config, checks
  DB rights and version, runs `db:seed` + `db:migrate` in-process (skippable with
  `SUPPRESS_MIGRATION_AT_STARTUP`), and warms up AR classes. `Heartbeat` detects a second instance
  running against the same schema. Every recurring job re-schedules *itself* with
  `set(wait: ...).perform_later` as its first statement (and skips that in `test`).
- **API/auth** — API-only Rails; `ApplicationController` authorizes every request via JWT
  (`app/lib/json_web_token.rb`) and stashes the current user / client IP in **thread locals**
  (`Thread.current[:current_user]`), which background code reads. Routes are declared explicitly in
  `config/routes.rb`. The Vue SPA is served as static assets built into the image; `run-movex-cdc.sh`
  rewrites the `REPLACE_PUBLIC_PATH_BEFORE` base path at container start (hence the fixed `js/`+`css/`
  output dirs in `vite.config.js`).

### DB abstraction

Two dispatch mechanisms, both `method_missing`-based on `config.db_type`: `Database` → `DatabaseOracle` /
`DatabaseSqlite` (connection handling, `exec_unprepared`, version info), and `DbTrigger` → the generator
classes. When adding a DB-specific method, add its symbol to the respective `METHODS_TO_DELEGATE` list or
the delegation silently falls through to `super`.

Oracle-only concerns appear throughout: partitioning of `EVENT_LOGS` (`MovexCdc::Application.partitioning?`),
`INI_TRANS` tuning from `MAX_SIMULTANEOUS_TRANSACTIONS`, TNS resolution via `TNS_ADMIN`, `AS OF SCN` reads.

## Testing

- Minitest, `test/{models,controllers,jobs,integration}`. `test/test_helper.rb` is large and central:
  `GlobalFixtures.initialize_testdata` builds the test data **once per suite run**, and
  `use_transactional_tests = false` (Oracle raises ORA-01466 on `AS OF SCN` right after DDL, so rollback
  via savepoints is not usable). Tests are **not** parallelized — that was disabled for DB consistency.
- Two schema roles: the *user* schema (tables without triggers) and the *victim* schema
  (`DB_VICTIM_USER`, tables that get triggers and are actually changed). `victim_schema_prefix` yields
  `"<user>."` on Oracle and `""` on SQLite.
- `db:test:load`, `db:test:purge` and `db:schema:dump` are deliberately **removed** in
  `lib/tasks/adjust_default_tasks.rake`: the test schema is built by migrations, and `schema.rb` would
  miss views/procedures/etc. Never reintroduce a schema-dump-based test setup.
- CI runs the same suite across a matrix: SQLITE×(java, mock) and Oracle (several versions + autonomous)
  ×(java, mock). A change that only works for one DB type will fail the pipeline. On Oracle, CI also
  verifies `db:migrate VERSION=0` (full rollback) followed by a forward migration — migrations must have
  working `down`/reversible definitions.

## Conventions

- Logging uses the block form with an explicit progname:
  `Rails.logger.debug('ClassName.method_name'){ "message" }`. The custom `CDCLogFormatter` prints
  timestamp, level, thread id and progname; keep the progname accurate since threads are the main
  debugging axis.
- Exceptions go through `ExceptionHelper.log_exception(e, 'Class.method', additional_msg: ...)` /
  `warn_with_backtrace` rather than bare `raise`-and-forget.
- Comments are trailing and column-aligned in much of the code base; several classes are singletons via
  `self.get_instance` with `@@instance`. Explicit `require` of app classes appears at the top of
  thread-related files to avoid "Circular dependency detected while autoloading constant" when several
  threads start at once — keep those requires when editing those files.
- User-visible release notes go in `CHANGELOG.md`.
