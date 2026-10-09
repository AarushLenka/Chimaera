#!/usr/bin/env python3
"""Target the measured v2 electrical loads with an incremental OpenDB ECO.

Run inside the matched LibreLane 3.0.14 image using the Odbpy reader's CLI.
Input must be the pre-filler route after the two endpoint hold repairs.
Existing cells are locked; fresh detailed routing and RCX/STA are mandatory.
"""

import os
import sys

# OpenROAD's embedded Python does not import the LibreLane Python package.
# Pass the matched image's scripts/odbpy directory explicitly.
sys.path.insert(0, os.environ["CHIMAERA_ODB_SCRIPT_DIR"])
from reader import click_odb, click, odb  # noqa: E402
import grt as GRT  # noqa: E402


# Coordinates are microns from the saved v2 DEF, not synthesized estimates.
# None means all input receivers of the specified output.
TARGETS = (
    ("input_frontend.loaded_bank/_053_", "sg13cmos5l_nor2b_1", "Y", None, (779.04, 551.88)),
    ("_43346_", "sg13cmos5l_nor2_1", "Y", None, (812.64, 601.02)),
    ("_44307_", "sg13cmos5l_o21ai_1", "Y", None, (729.60, 521.64)),
    ("_28917_", "sg13cmos5l_nor3_1", "Y", None, (345.60, 415.80)),
    ("_28470_", "sg13cmos5l_nand3_1", "Y", None, (994.08, 332.64)),
    ("_28466_", "sg13cmos5l_a22oi_1", "Y", None, (1006.56, 343.98)),
    ("fanout3247", "sg13cmos5l_buf_1", "X",
     ("fanout3207/A", "fanout3195/A", "ANTENNA_88/A", "ANTENNA_87/A", "ANTENNA_86/A", "ANTENNA_85/A"), (600, 445)),
    ("fanout4193", "sg13cmos5l_buf_1", "X",
     ("_31439_/A1", "_31405_/A1", "_31371_/A1", "_31337_/A1", "_31303_/A1", "_31269_/A1", "_31234_/A1"), (970, 490)),
    ("fanout3880", "sg13cmos5l_buf_1", "X",
     ("_43881_/B2", "_43590_/A1", "_43366_/A1", "_43162_/A1", "_42207_/B2"), (1020, 605)),
    ("fanout4129", "sg13cmos5l_buf_1", "X",
     ("_32005_/B", "_31901_/B", "_31850_/D"), (450, 275)),
    ("fanout3856", "sg13cmos5l_buf_1", "X",
     ("_43829_/A1", "_43678_/B2", "_43436_/A1", "_43231_/B2", "_42292_/B2"), (1000, 600)),
)


@click.command()
@click_odb
def cli(reader):
    block = reader.block
    master = reader.db.findMaster("sg13cmos5l_buf_4")
    if master is None:
        raise click.ClickException("matched BUF-4 master is absent")
    for name in ("eco_buffer_0", "eco_buffer_1"):
        inst = block.findInst(name)
        if inst is None or inst.getMaster().getName() != "sg13cmos5l_dlygate4sd3_1":
            raise click.ClickException("input must contain the two verified endpoint hold delays")

    # Resolve and validate every receiver before editing this isolated database.
    resolved = []
    for driver, expected, port, paths, location in TARGETS:
        inst = block.findInst(reader.escape_verilog_name(driver))
        if inst is None or inst.getMaster().getName() != expected or inst.isDoNotTouch():
            raise click.ClickException(f"mismatched or protected target {driver}")
        pin = inst.findITerm(port)
        if pin is None or not pin.isOutputSignal() or pin.getNet() is None:
            raise click.ClickException(f"invalid driver {driver}/{port}")
        net = pin.getNet()
        if paths is None:
            loads = [load for load in net.getITerms() if load.isInputSignal()]
        else:
            loads = []
            for path in paths:
                name, terminal = path.rsplit("/", 1)
                receiver = block.findInst(reader.escape_verilog_name(name))
                load = receiver.findITerm(terminal) if receiver else None
                if (load is None or not load.isInputSignal() or load.getNet() is None
                        or load.getNet().getName() != net.getName()):
                    raise click.ClickException(f"mismatched load {path} for {driver}")
                loads.append(load)
        if not loads or net.isDoNotTouch():
            raise click.ClickException(f"empty or protected net at {driver}")
        resolved.append((driver, net, loads, location))

    placements = [(inst, inst.getPlacementStatus(), inst.getLocation(), inst.getOrient())
                  for inst in block.getInsts()]
    for inst, _, _, _ in placements:
        inst.setPlacementStatus("LOCKED")
    router = reader.design.getGlobalRouter()
    reader._grt_setup(router)
    incremental = GRT.IncrementalGRoute(router, block)

    for index, (driver, net, loads, location) in enumerate(resolved, 2):
        name = f"eco_buffer_{index}"
        if block.findInst(name) or block.findNet(f"{name}_net"):
            raise click.ClickException(f"refusing to overwrite {name}")
        buffer = odb.dbInst.create(block, master, name)
        output = odb.dbNet.create(block, f"{name}_net")
        buffer.findITerm("A").connect(net)
        buffer.findITerm("X").connect(output)
        for load in loads:
            load.disconnect()
            load.connect(output)
        buffer.setOrient("R0")
        buffer.setLocation(*(block.micronsToDbu(float(value)) for value in location))
        buffer.setPlacementStatus("PLACED")
        router.addDirtyNet(net)
        router.addDirtyNet(output)
        print(f"ECO {name} driver={driver} loads={len(loads)} placement={location}")

    site = reader.rows[0].getSite()
    displacement = (
        int(reader.design.micronToDBU(reader.config["PL_MAX_DISPLACEMENT_X"]) / site.getWidth()),
        int(reader.design.micronToDBU(reader.config["PL_MAX_DISPLACEMENT_Y"]) / site.getHeight()),
    )
    reader.design.getOpendp().detailedPlacement(*displacement)
    incremental.updateRoutes(True)
    for inst, status, location, orient in placements:
        if inst.getLocation() != location or inst.getOrient() != orient:
            raise click.ClickException(f"existing placement changed: {inst.getName()}")
        inst.setPlacementStatus(status)
    print(f"ECO complete: {len(resolved)} identity buffers; {len(placements)} original placements retained")


if __name__ == "__main__":
    cli()
