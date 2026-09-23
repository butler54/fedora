# Fixture: broken-image

Deliberately non-compliant build context for proving the hardening gate fails closed.

Tripwires:
- `PasswordAuthentication yes` in `files/etc/ssh/sshd_config.d/50-hardened.conf`
  (violates H010)

Expected: `hardening-verify.sh --phase image` FAILs with H010=FAIL and pipeline
fixture-mode exits 4 before any registry push or VM release.
