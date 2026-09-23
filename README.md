![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# Tiny Tapeout Verilog Project Template

- [Read the documentation for project](docs/info.md)

## What is Tiny Tapeout?

Tiny Tapeout is an educational project that aims to make it easier and cheaper than ever to get your digital and analog designs manufactured on a real chip.

To learn more and get started, visit https://tinytapeout.com.

## Set up your Verilog project

1. Add your Verilog files to the `src` folder.
2. Edit the [info.yaml](info.yaml) and update information about your project, paying special attention to the `source_files` and `top_module` properties. If you are upgrading an existing Tiny Tapeout project, check out our [online info.yaml migration tool](https://tinytapeout.github.io/tt-yaml-upgrade-tool/).
3. Edit [docs/info.md](docs/info.md) and add a description of your project.
4. Adapt the testbench to your design. See [test/README.md](test/README.md) for more information.

The GitHub action will automatically build the ASIC files using [LibreLane](https://www.zerotoasiccourse.com/terminology/librelane/).

## Enable GitHub actions to build the results page

- [Enabling GitHub Pages](https://tinytapeout.com/faq/#my-github-action-is-failing-on-the-pages-part)

## Resources

- [FAQ](https://tinytapeout.com/faq/)
- [Digital design lessons](https://tinytapeout.com/digital_design/)
- [Learn how semiconductors work](https://tinytapeout.com/siliwiz/)
- [Join the community](https://tinytapeout.com/discord)
- [Build your design locally](https://www.tinytapeout.com/guides/local-hardening/)

## What next?

- [Submit your design to the next shuttle](https://app.tinytapeout.com/).
- Edit [this README](README.md) and explain your design, how it works, and how to test it.
- Share your project on your social network of choice:
  - LinkedIn [#tinytapeout](https://www.linkedin.com/search/results/content/?keywords=%23tinytapeout) [@TinyTapeout](https://www.linkedin.com/company/100708654/)
  - Mastodon [#tinytapeout](https://chaos.social/tags/tinytapeout) [@matthewvenn](https://chaos.social/@matthewvenn)
  - X (formerly Twitter) [#tinytapeout](https://twitter.com/hashtag/tinytapeout) [@tinytapeout](https://twitter.com/tinytapeout)
  - Bluesky [@tinytapeout.com](https://bsky.app/profile/tinytapeout.com)

## Phase 5 DSL compiler checkpoint

The dependency-free host compiler can parse a protocol, resolve physical-time
durations, run the initial proof checks, emit a deterministic host object and
manifest, and execute the result in a cycle-step reference model. Compile the
checked-in sample with:

```sh
python3 -m chimaera examples/phase5/pulse_ack.chi \
  --clock-hz 50000000 \
  --bind 'pulse_ack.request=uio[0]' \
  --bind 'pulse_ack.response=uio[1]'
```

This emits `.chobj`, `.manifest.json`, `.states.dot`, `.wave.txt`, and
`.random_test.py` artifacts. The example includes a Phase 6 contract, so its
manifest remains `chip_loadable: false` until contract hardware lowering exists.

The protocol-only example exercises the accepted 32 × 128-bit chip backend:

```sh
python3 -m chimaera examples/phase5/loader_pulse.chi \
  --clock-hz 50000000 \
  --bind 'loader_pulse.request=uio[0]' \
  --bind 'loader_pulse.response=uio[1]'
```

It additionally emits an 84-byte `.loader.bin`: 21 MSB-first 32-bit frames for
two descriptors, pin modes, CRC-checked commit, and resume. The checked-in RTL
accepts this stream on `ui_in[2]` (active-low CS), `ui_in[3]` (SCLK below
12.5 MHz), and `ui_in[4]` (MOSI), with MISO on `uo_out[0]` while selected.

Run the host-toolchain checks without third-party Python packages:

```sh
python3 -m unittest discover -s phase5_tests -v
```
