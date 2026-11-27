# jvuln

One POSIX `sh` script: inventory the packages of a FreeBSD host **and all its
jails**, check them against the FreeBSD vulnerability database (vuxml, via
`pkg audit`), and write **one static HTML page**.

No daemon, no web server, no open port: you decide where the page is written
and who can read it.

## What the page shows

- **Summary**: per target (host, each jail): release, number of packages,
  number of vulnerable packages.
- **Per target**: vulnerable packages with CVE and a link to the vuxml advisory,
  plus the full inventory (name, version, origin).
- **Cross-view by package**: one row per package, with the versions installed
  and where. A package present in several versions is highlighted (a jail is
  behind).

## Install

    install -m 755 jvuln.sh /usr/local/sbin/jvuln
    install -m 644 jvuln.conf.sample /usr/local/etc/jvuln.conf   # optional
    jvuln                                  # run as root
    # daily, in root's crontab:
    30 5 * * * /usr/local/sbin/jvuln >> /var/log/jvuln.log 2>&1

Options: `-c config` to use another config file, `-o file.html` to write to an
exact file (no dated name, no symlink). See `jvuln.conf.sample` for everything else (language, jail filters,
page title, file mode...).

## How it works

- The vulnerability database is downloaded **once**, on the host
  (`pkg audit -F`), and reused for every jail: jails need no network access.
- Each jail is read from the host with `pkg -r <jail root>`; nothing is
  executed inside the jails, stopped Bastille jails included.
- Jails are discovered through the Bastille layout if present, otherwise through
  `jls` (running jails only). Directories without a pkg database (Linux jails,
  empty jails) are skipped.

## Where the page goes

`OUT_DIR` (default `/var/db/jvuln`) is the directory the page is written to,
`OUT_NAME` its name as a `date(1)` format (default `jvuln-%Y%m%d.html`, one
file per day). `jvuln-latest.html` is a symlink to the newest page.

Because jvuln only writes a file, access control is yours: point `OUT_DIR` at
a directory that only the right people (or a single jail) can read. Example:
to make the page readable only from inside a Bastille jail, set `OUT_DIR` to
a directory inside that jail's filesystem and open it with `file://`.

Old pages are not removed; add a `find ... -mtime +30 -delete` to your cron
if you want to prune them.

## Limits

Only `pkg`-managed software is covered. The base system and kernel are not
audited (the release is displayed, update with `freebsd-update`), nor is
software installed outside pkg (jars, binaries downloaded by hand...).
The database is only as fresh as the last successful `pkg audit -F`; the page
states its date.

## License

BSD 2-clause.
