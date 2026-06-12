# Polaris (ALCF) — login-node helpers. Sourced everywhere but no-ops unless
# the eagle filesystem exists, mirroring the 40-fasrc.sh guard pattern.
if [[ -d /lus/eagle ]]; then

  # tl = hop to login-01 (where the main tmux with Claude agents lives).
  # ~/.ssh/config multiplexes polaris-login-* (ControlPersist 12h), so only
  # the first hop after a master expires asks for a MobilePASS+ OTP.
  alias tl='ssh polaris-login-01'

fi
