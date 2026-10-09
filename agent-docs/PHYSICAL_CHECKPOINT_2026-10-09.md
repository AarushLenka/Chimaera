# Physical rollback checkpoint — 2026-10-09

Hausen requested a source and physical checkpoint before further repair. The
source/configuration/repair-script SHA-256 values still match
`repair-input-hashes.json` from the physical experiment. Production source and
the repair script are unchanged from `6f629c4`; this checkpoint commits the
existing evidence documentation and physical-audit helper as well.

## Preserved routed results

All values below come from detailed routing and fresh RCX at the unchanged
20 ns clock and 6x4 footprint. These are local screens, not hosted signoff.

| Run | Corner | Setup worst slack (ns) | Setup TNS (ns) | Setup violations | Hold worst slack (ns) | Hold TNS (ns) | Hold violations | Slew violations | Cap violations |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| extracted-repair-v2 | FF | 10.853827 | 0 | 0 | -0.036307 | -0.049251 | 2 | 0 | 5 |
| extracted-repair-v2 | TT | 7.625293 | 0 | 0 | 0.184567 | 0 | 0 | 0 | 5 |
| extracted-repair-v2 | SS | 0.273237 | 0 | 0 | 0.580389 | 0 | 0 | 22 | 5 |
| extracted-closure-v3-all | FF | 10.681221 | 0 | 0 | 0.097774 | 0 | 0 | 0 | 4 |
| extracted-closure-v3-all | TT | 7.555031 | 0 | 0 | 0.305771 | 0 | 0 | 0 | 3 |
| extracted-closure-v3-all | SS | -0.038121 | -0.038121 | 1 | 0.624618 | 0 | 0 | 15 | 3 |

WNS is negative-only: it is zero for every passing setup/hold corner above.
The only negative WNS values are v2 FF hold (-0.036307 ns) and v3 SS setup
(-0.038121 ns). V2 has the better SS setup margin, while v3 has clean hold.
Both candidates are preserved so a later experiment can roll back to either.

V2 standard-cell area/utilization is 696071 um2 / 77.1341%; v3 is 697169 um2 /
77.2557%. Both have zero routing DRC, antenna and critical disconnected-pin
counts. Full Magic/KLayout DRC and LVS are incomplete. V3 was stopped during
`Magic.StreamOut` after extraction showed residual setup/electrical failures;
there is no completed final GDS or full-signoff claim for this run.

V3's remaining SS setup path is `_54412_/Q -> _54832_/D`, from
`loaded_runtime.active_control_0[32]` through branch lookahead, descriptor
selection/read and the action-value cone. Four drivers account for the 15 SS
slew violations: `_29761_`, `_28470_`, `_44312_`, `_44329_`. The capacitance
violations affect `fanout16749`, `fanout16756`, `fanout4177`, and, at FF only,
`_27769_`. No new repair has been applied after this route.

## Durable local archive

Git preserves source and documentation; routed binary views are saved in this
ignored archive on the workspace filesystem:

```text
.physical-checkpoints/2026-10-09-pre-residual-repair/physical-evidence.tar.zst
SHA256 9617c1956906323d6e2c43e05294982cddbd1bce1ba453612cd285e33c9f9a3f
```

The archive contains the complete `chimaera-ss-fix.JiNkH8` evidence directory
and `chimaera-pdk-local` PDK directory, including both routed candidates,
ODB/DEF/netlist/SDC/SPEF views, corner reports, configurations, matched timing
libraries, repair inputs, source snapshots and hashes. It also retains the
earlier branch-lookahead baseline and provisional repair reports. The read-only
`probe-v3.tcl` is included; it only inspects the existing layout. Archive contents
were compared against the originals with `tar --diff`, with no differences.

This archive is local, is not committed or pushed, and does not depend on
`/tmp` surviving a reboot. Copy it separately when transferring the checkpoint.
The Docker tool image is
`ghcr.io/librelane/librelane@sha256:f91b21d75f79871f9ccf37451020b5d2f7b3236881a997ff709c561e8280a30f`;
OpenROAD reports revision `dcf36133a369abc8f3c5e5738cd4d82e4903c0e0`.

Verify and restore into a fresh directory, preserving the originals:

```sh
rtk proxy sha256sum .physical-checkpoints/2026-10-09-pre-residual-repair/physical-evidence.tar.zst
checkpoint_restore_dir="$(rtk proxy mktemp -d /tmp/chimaera-checkpoint.XXXXXX)"
rtk proxy tar -I zstd -xf .physical-checkpoints/2026-10-09-pre-residual-repair/physical-evidence.tar.zst -C "$checkpoint_restore_dir"
```

Mount the restored evidence directory as `/evidence` and PDK directory as
`/pdk` when using the saved container configurations. Resume new experiments
with new run tags and output prefixes. The stage state below provides the
exact v3 routed input; the v2 run also has normal `final/` views.

```text
V2 metrics: runs/extracted-repair-v2/final/metrics.json
V3 state:   runs/extracted-closure-v3-all/17-openroad-stapostpnr/state_out.json
```

| View | V2 SHA-256 | V3 SHA-256 |
| --- | --- | --- |
| ODB | ec36675291f05b48cb77da9b894f495ede2b56feb2276ce5ce6abe4938f437c3 | 80136aee7b8c701a52fdf85f92e04e807a295650fc562c83b0bd0e2134d6c21e |
| Netlist | 7633a5656a187ac5b521fafb7133213967ebc29707a9fced261bfcf02456e640 | 5fa83b0c7f8cae5de4c41d647cb1ef2f2e12d85350f1872f9e30d1a908079afb |
| SDC | 82e73e6a0af5e995b41848d0a7a93adc45cbe044c3d65bd6d7ce90929d053b85 | 82e73e6a0af5e995b41848d0a7a93adc45cbe044c3d65bd6d7ce90929d053b85 |
| SPEF | cf5065f182916c13437f8be90befddc6bef3efa8aa0812271008f748ba2c7cd1 | b09a85282d2ca05b5f3f235f271efcd1623b4da399e192ae107ed7d8bd2b42fe |

The exact view paths are recorded in the archived stage state JSON files.
Phase 7 remains open until all timing/electrical and required physical gates
pass, followed by the separate exact-commit hosted-build verification.
