# Bootstrapping worker credentials

A QCFractal deployment is not finished when `nixos-rebuild` succeeds. With `enableSecurity`
(the default), a compute worker needs two things that cannot be expressed in Nix, and until
both exist `qcfractalcompute.service` crash-loops on a failed login:

- **an account.** QCFractal keeps users in PostgreSQL, so `services.qcfractalCompute.server.username`
  names something that does not exist yet. Nothing creates it for you.
- **a password on the worker.** It has to reach the worker without passing through the Nix
  store, which is world-readable.

This page is the procedure. It is a one-time step per worker; the compute VM tests rehearse the
same sequence, so it is also what those tests assert.

## Before you start

Both procedures below assume:

- `services.qcfractal.enable = true` on the server host, and it has **started at least once** —
  the first start generates `secrets.env` and `qcf_config.yaml` under `stateDir`, and nothing
  can be done before they exist.
- `services.qcfractalCompute.server.passwordFile` is set on the worker host to a path outside
  the Nix store, in a directory the service user can traverse.
- `qcfractal-manage` is on the server host's `PATH`. The server module installs it whenever
  `services.qcfractal.enable` is true.

Substitute your own values for `worker` (your `server.username`), `qcfractalcompute` (your
`services.qcfractalCompute.user`) and the password-file path throughout.

## One host running both server and worker

Do not display the password at any point — pipe it. The server generates it, and nobody, you
included, ever needs to see it:

```sh
set -o pipefail

pw_file=/var/lib/secrets/qcfractal-worker-password   # your server.passwordFile
svc_user=qcfractalcompute                            # your services.qcfractalCompute.user

out=$(mktemp)            # mktemp is 0600, and the CLI prints the password to stdout
trap 'rm -f "$out"' EXIT

sudo qcfractal-manage user add worker --role compute > "$out"

pw=$(sed -n '/utogenerated password for/{n;n;p;}' "$out")
[ -n "$pw" ] || { echo "no password in the CLI output; read $out" >&2; exit 1; }

sudo install -m 0400 -o "$svc_user" -g "$svc_user" /dev/null "$pw_file"
printf '%s\n' "$pw" | sudo tee "$pw_file" > /dev/null
unset pw

sudo systemctl restart qcfractalcompute.service
```

`install` creates the file empty with the right owner and mode, then `tee` fills it — root
writes through the `0400`. The trailing newline is fine: the unit reads the file with
`"$(< file)"`, and command substitution strips trailing newlines.

## Server and worker on different hosts

The same two steps, with a secret in transit between them. On the **server**:

```sh
sudo qcfractal-manage user add worker --role compute
```

It prints the generated password between two rules. Move that value to the worker host by
whatever means you already trust for secrets — a password manager, `age`, an existing
sops-nix/agenix pipeline. Do not paste it into a shell command on the worker, where it lands in
shell history; write it to the file with an editor, or have your secrets manager place the file
directly.

On the **worker**, the file must end up:

- containing the password and **nothing else** — not `KEY=value`, no quotes, no comments;
- mode `0400`, owned by `services.qcfractalCompute.user`;
- in a directory that user can traverse (`0751` root-owned is a reasonable parent).

Then `sudo systemctl restart qcfractalcompute.service`.

If you use sops-nix or agenix, point `server.passwordFile` at the secret's `path` and let the
secrets manager own mode and ownership; nothing above changes except who writes the file.

## Verifying

The worker crash-loops on bad credentials, so "still running a few seconds later" is the real
evidence:

```sh
systemctl is-active qcfractalcompute.service
sleep 10 && systemctl is-active qcfractalcompute.service
```

Confirm the file is readable *as the service user*, which is what actually reads it:

```sh
sudo -u qcfractalcompute cat /var/lib/secrets/qcfractal-worker-password > /dev/null && echo readable
```

And that the server agrees the account exists:

```sh
sudo qcfractal-manage user list
```

## Rotating, or recovering a lost password

Passwords are stored **hashed**, so a lost password file cannot be recovered — it can only be
replaced. Both cases are the same command:

```sh
sudo qcfractal-manage user modify worker --reset-password
```

It prints a new generated password in the same format, so the same piping applies. Write the
new value to the password file before restarting the worker, or it will crash-loop.

## When something is wrong

Every failure mode presents identically — the unit starts, fails to authenticate, restarts:

| Symptom in the journal | Usual cause |
|---|---|
| `401`, invalid credentials | the file's contents do not match the account's password |
| the file read fails at start | mode/ownership, or a directory the service user cannot traverse |
| the account does not exist | `user add` was never run, or was run against a different server |
| `Connection refused` | the server is not up, or `server.fractalUri` is wrong |

Check the file's contents against a fresh reset before assuming anything subtler. A stray
newline in the middle, a `KEY=value` wrapper, or an editor's added trailing whitespace are the
common ones — only *trailing* newlines are stripped.

## Why `qcfractal-manage` rather than `qcfractal-server`

`qcfractal-server` is both the daemon and the admin CLI, and running the CLI by hand needs the
environment the units build before launching the daemon. `FractalConfig` validates in **full**
before any subcommand touches the database, and three of its fields are deliberately absent
from the generated `qcf_config.yaml` because they are secrets: `api.secret_key`,
`api.jwt_secret_key` and `database.password`.

So a bare `qcfractal-server user add` fails on a validation error that mentions none of that.
What it needs is the signing keys sourced from `secrets.env`, a `database.password` (the empty
string when the local socket uses peer authentication, which ignores it but still requires a
string), `--config` pointing at the on-disk `qcf_config.yaml` rather than the one in the store,
and to run as `services.qcfractal.user`, since `stateDir` is `0750`.

`qcfractal-manage` is exactly that preamble, generated from the same module values the units
use. It forwards every argument, so anything `qcfractal-server` accepts works — `user list`,
`user info`, `backup`, `restore`. Run as root it drops to the service user on its own. The
definition sits next to `runtimeSecrets` in `nixos-modules/qcfractal-server.nix`, where the
reasoning about those fields already lived.

## Never choose the password yourself

`user add` and `user modify` both take an optional `--password`. **Omit it.** The server then
generates one, which is better in two ways: nobody invents a weak password, and the value never
appears in `argv`, where `ps` shows it to every user on the box for as long as the command runs.

Both print the same shape, which is what the `sed` above matches:

```
Autogenerated password for worker is below
--------------------------------------------------------------------------------
<password>
--------------------------------------------------------------------------------
```

## Roles

`--role compute` is the built-in role for workers. Do not give a worker `admin` — it needs to
claim and return tasks, nothing more. Create a separate account for submitting clients at the
same time, so ordinary use never involves the worker's credentials:

```sh
sudo qcfractal-manage user add me --role user
```
