# Containment probe

Checks what a lab VM's network can reach. Results are in `docs/decisions/0010-lab-network-isolation.md`. Run it again after changing the QEMU arguments or updating QEMU.

- `probe.sh` runs inside a Linux lab VM and prints `REACHED` or `blocked` for each attempt.
- `run-probe.ps1` runs on the Windows host. It opens listeners on loopback only, runs the probe through a runner script (`-Runner`, which must accept `-Script`, `-Vm` and `-Lab`: start the lab, run the script in the guest as root, end the lab), then says which listeners were really reached. The runner is not part of the repository.
- `isolated-probe.toml` is a test-only lab with `network = "isolated"`.

Run it twice: with an ordinary Linux lab (the control: it should reach things) and with `isolated-probe.toml`. An isolated "blocked" means nothing unless the same line says "reached" in the control. The output can contain your LAN address; remove it before saving or sharing.
