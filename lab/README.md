# Sauron training lab

A self-contained Sauron with a fictitious organisation (`lab.example`),
two accounts and a set of everyday DNS/DHCP tasks that are checked
automatically. Participants run it on their own workstation and work in the
browser; the task list with the current state is in the web UI.

The tasks come from the most frequent changes in real DNS zone repositories:
new hosts, aliases, address changes, renames, removals, TXT records for
verification and ACME, CAA, TTL changes before a migration, new zones with
mail records (MX, SPF, DKIM, DMARC), delegations, networks and DHCP
reservations.

- tasks for participants: [tasks.en.md](tasks.en.md), [tasks.cs.md](tasks.cs.md)
  (the same text is shown on the *Hosts → Lab tasks* page)
- all data is fictitious, addresses come from the documentation ranges
  (RFC 5737, RFC 3849)

## Running the lab

Requirements: Docker with the Compose plugin.

```sh
docker compose -p sauron-lab -f docker-compose.yml -f docker-compose.lab.yml up -d --build
```

Open <http://localhost:8081/cgi-bin/sauron.cgi> (another port:
`SAURON_LAB_PORT=8090 docker compose ...`) and log in:

| Account | Password | Role |
|---|---|---|
| `user` | `user` | ordinary user (RW on `lab.example`, three networks, CNAME and DHCP flags) |
| `admin` | `admin` | superuser |

The first start initializes the database and loads the lab data, which takes
about half a minute. The lab runs next to the development stack
(`docker compose up`), it has its own project name, port and database.

## Checking the tasks

- web UI: *Hosts → Lab tasks* (English/Czech switch on the page)
- command line:

  ```sh
  C="docker compose -p sauron-lab -f docker-compose.yml -f docker-compose.lab.yml"
  $C exec sauron /usr/local/sauron/lab/lab-check            # all tasks
  $C exec sauron /usr/local/sauron/lab/lab-check --task=U1  # one task
  $C exec sauron /usr/local/sauron/lab/lab-check --lang=cs --role=admin
  ```

`lab-check` generates the zones and `dhcpd.conf` into a temporary directory
the same way `sauron` does for the DNS/DHCP servers (with `--keep-pending`,
so the *PENDING* markers in the web UI stay), parses them and compares them
with the expected records. A few tasks also look into the database (ticket
number in the host record, networks, privileges). So the result counts, not
the way it was reached. Exit status 0 means all tasks are done; `--json` and
`--tap` give machine readable output.

## Shell in the container

Some tasks (privileges) are done on the command line, as in production:

```sh
$C exec sauron bash
/usr/local/sauron/moduser user               # privileges of the user
/usr/local/sauron/modgroup lab-users --help
```

## Reset

```sh
$C down -v && $C up -d
```

`down -v` removes the database volume; the next start loads fresh lab data.

## For trainers

- `lab/solve` is the reference solution: it completes all tasks through the
  back-end functions the web UI uses (`--task=ID` for one task). Do not run
  it in a participant's lab.
- `t/33-lab.t` (part of `make test-e2e`) loads the lab data, checks that no
  task is done, runs `solve` and checks that all tasks are done. A change in
  Sauron that breaks a task therefore fails the CI.

### Files

| File | Purpose |
|---|---|
| `data/seed.sql`, `data/lab.example.zone` | server, networks and the forward zone |
| `seed.sh` | loads the data, creates reverse zones, the group `lab-users` and the user `user`; run by `docker/entrypoint.sh` when `SAURON_SEED=lab` |
| `tasks.pl` | task definitions: id, role, titles, check |
| `tasks.en.md`, `tasks.cs.md` | assignments, one `## <ID> <title>` section per task |
| `lab-check` | checks the tasks |
| `solve` | reference solution |
| `../plugins/lab.{conf,pm}` | the *Lab tasks* page (`SAURON_PLUGINS=lab`) |
| `../docker-compose.lab.yml` | Compose overlay of the lab |

### Adding a task

1. Add the task to `tasks.pl` (check with the helpers from `lab-check`:
   `expect_rr`, `expect_only_rr`, `expect_no_name`, `expect_ptr`,
   `expect_ttl`, `host_by_name`, `dhcp_host_block`, `fail`, ...).
2. Add a section `## <ID> <title>` to both `tasks.en.md` and `tasks.cs.md`.
3. Add the solution to `solve` and its id to `@order`.
4. Run `make test-e2e`.

Use values that cannot appear in the lab data by accident, and check the
result, not the way it was reached.
