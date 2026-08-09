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

**This runs after `nixos-rebuild switch`, not before.** Two of the prerequisites below are
things the rebuild itself produces: `qcfractal-manage` reaches `PATH` only with the server
module, and `qcfractal-init-db.service` creates the schema during the switch. There is nothing
to bootstrap until both have happened, and the worker crash-loops in the window between the
switch and this procedure.

Both procedures below assume:

- `services.qcfractal.enable = true` on the server host, and it has **started at least once** —
  `qcfractal-init-db.service` generates `secrets.env` and `qcf_config.yaml` under `stateDir` and
  stamps the database, and nothing can be done before they exist. It is `wantedBy
  multi-user.target`, so the switch starts it for you; `systemctl status qcfractal-init-db` says
  whether it succeeded.
- `services.qcfractalCompute.server.passwordFile` is set on the worker host to a path outside
  the Nix store, **in a directory that already exists**. Declare the directory rather than
  creating it by hand — it is not itself a secret, so nothing keeps it out of the configuration:

  ```nix
  systemd.tmpfiles.rules = [
    "d /var/lib/secrets 0751 root root - -"
  ];
  ```

  `0751` lets a service user traverse in without being able to list what is there; each file
  inside carries its own `0400`. `systemd-tmpfiles-setup.service` runs in `sysinit.target`, so
  the directory exists well before either unit starts.

  The module deliberately does **not** create `dirOf passwordFile` for you. That path is just as
  likely to be a sops-nix or agenix mount point, and those own their directory's mode and
  ownership themselves — creating it first would fight them.
- `qcfractal-manage` is on the server host's `PATH`. The server module installs it whenever
  `services.qcfractal.enable` is true.

Substitute your own values for `worker` (your `server.username`), `qcfractalcompute` (your
`services.qcfractalCompute.user`) and the password-file path throughout. The account name has
to match `server.username` **exactly**: creating `worker` while the module logs in as
`worker-meyeri` fails the same way a wrong password does, with a `401` and no mention of which
of the two is wrong.

## One host running both server and worker

Do not display the password at any point — pipe it. The server generates it, and nobody, you
included, ever needs to see it:

```sh
set -o pipefail

username=worker                                      # your server.username
pw_file=/var/lib/secrets/qcfractal-worker-password   # your server.passwordFile
svc_user=qcfractalcompute                            # your services.qcfractalCompute.user

out=$(sudo qcfractal-manage user add "$username" --role compute)

pw=$(printf '%s\n' "$out" | sed -n '/utogenerated password for/{n;n;p;}')
[ -n "$pw" ] || { printf '%s\n' 'no password in the CLI output:' "$out" >&2; exit 1; }

sudo install -m 0400 -o "$svc_user" -g "$svc_user" /dev/null "$pw_file"
printf '%s\n' "$pw" | sudo tee "$pw_file" > /dev/null
unset pw out

sudo systemctl restart qcfractalcompute.service
```

The output is captured in a shell variable rather than a temp file, so the password never
touches the disk anywhere but `$pw_file` — and there is no cleanup to get wrong. `sudo cmd >
file` would be the obvious alternative and is worse twice over: the redirect runs as *you*, not
as root (shellcheck flags this as SC2024), and it leaves the password in a file that a `trap`
has to remember to remove.

`install` creates `$pw_file` empty with the right owner and mode, then `tee` fills it — root
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
- in the directory declared under "Before you start", which the rebuild has already created.

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
| `401`, invalid credentials | the file's contents do not match the account's password, **or** the account was created under a different name than `server.username` |
| the file read fails at start | mode/ownership, or a parent directory that is missing or that the service user cannot traverse |
| the account does not exist | `user add` was never run, or was run against a different server |
| `Connection refused` | the server is not up, or `server.fractalUri` is wrong |

The server's own journal names the account it rejected — `Authentication failed for user
<name>` — so start there and check that name against `sudo qcfractal-manage user list`. If the
name is absent from that list, the password is a red herring; you created the account under
some other name, most likely by pasting the block above without substituting `username`.

Otherwise check the file's contents against a fresh reset before assuming anything subtler. A
stray newline in the middle, a `KEY=value` wrapper, or an editor's added trailing whitespace
are the common ones — only *trailing* newlines are stripped.

A worker that has been crash-looping will have tripped systemd's start limit, and `systemctl
restart` then refuses with `start request repeated too quickly`. Clear it with `sudo systemctl
reset-failed qcfractalcompute.service` before starting again.

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
