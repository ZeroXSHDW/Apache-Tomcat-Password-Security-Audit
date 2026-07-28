# Security Policy

## Supported use

This repository provides **audit and remediation scripts** for Apache Tomcat password / credential-handler configuration. Treat all scripts as privileged tooling: they may read or modify `server.xml` and `tomcat-users.xml`, and patching paths can restart Tomcat.

## Reporting a vulnerability

If you believe you have found a security issue in these scripts (for example, unsafe file handling, command injection, or credential leakage):

1. Prefer a private disclosure to the repository owner via GitHub Security Advisories (or email the maintainer listed on the GitHub profile).
2. Do **not** open a public issue that includes production credentials, hostnames of sensitive systems, or exploit PoCs against live hosts.
3. Include: affected script path, Tomcat version(s), OS, and steps to reproduce in a lab.

## Safe operation

- Run audit scripts first; only run patch scripts after reviewing backups.
- Use lab / non-production Tomcat instances for the testing framework under `tests/`.
- Do not commit real `tomcat-users.xml` files or plaintext passwords into this repository.
- Prefer least-privilege accounts for remote WinRM audits; rotate credentials used for remoting.

## Scope

Out of scope: vulnerabilities in Apache Tomcat itself, Java, or third-party installers — report those upstream.
