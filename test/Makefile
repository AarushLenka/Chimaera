# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# defaults
SIM ?= icarus
FST ?= -fst # Use more efficient FST format
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../src
PROJECT_SOURCES = chimaera_input_frontend.v chimaera_uart_program.v chimaera_i2c_program.v chimaera_spi_program.v chimaera_port_b_program.v chimaera_execution_engine.v chimaera_reaction_cell.v project.v

ifneq ($(GATES),yes)

# RTL simulation:
SIM_BUILD				= sim_build/rtl
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))

else

# Gate level simulation:
SIM_BUILD				= sim_build/gl
COMPILE_ARGS    += -DGL_TEST
COMPILE_ARGS    += -DFUNCTIONAL
COMPILE_ARGS    += -DSIM

PDK_STDCELL_DIR = $(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/verilog
PDK_STDCELL_UDP = $(PDK_STDCELL_DIR)/sg13cmos5l_udp.v
PDK_STDCELL_MODEL = $(PDK_STDCELL_DIR)/sg13cmos5l_stdcell.v

ifeq ($(wildcard $(PDK_STDCELL_UDP)),)
$(error Missing IHP standard-cell UDP model: $(PDK_STDCELL_UDP))
endif
ifeq ($(wildcard $(PDK_STDCELL_MODEL)),)
$(error Missing IHP standard-cell model: $(PDK_STDCELL_MODEL))
endif

VERILOG_SOURCES += $(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_io/verilog/sg13cmos5l_io.v
# The standard-cell model instantiates primitives defined by the UDP model.
VERILOG_SOURCES += $(PDK_STDCELL_UDP)
VERILOG_SOURCES += $(PDK_STDCELL_MODEL)

# this gets copied in by the GDS action workflow
VERILOG_SOURCES += $(PWD)/gate_level_netlist.v

endif

# Allow sharing configuration between design and testbench via `include`:
COMPILE_ARGS 		+= -I$(SRC_DIR)

# Include the testbench sources:
VERILOG_SOURCES += $(PWD)/tb.v
TOPLEVEL = tb

# List test modules to run, separated by commas and without the .py suffix:
COCOTB_TEST_MODULES = test

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim
