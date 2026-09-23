# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# defaults
SIM ?= icarus
FST ?= -fst # Use more efficient FST format
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(CURDIR)/../src
PROJECT_SOURCES = chimaera_input_frontend.v chimaera_uart_program.v chimaera_i2c_program.v chimaera_spi_program.v chimaera_port_b_program.v chimaera_execution_engine.v chimaera_reaction_cell.v chimaera_config_spi.v chimaera_program_loader.v chimaera_host_interface.v chimaera_generic_execution_engine.v chimaera_program_runtime.v project.v

.PHONY: phase5
phase5:
	iverilog -g2012 -s program_loader_tb -o /tmp/chimaera-program-loader.vvp $(SRC_DIR)/chimaera_program_loader.v program_loader_tb.v
	vvp /tmp/chimaera-program-loader.vvp
	iverilog -g2012 -s config_spi_tb -o /tmp/chimaera-config-spi.vvp $(SRC_DIR)/chimaera_config_spi.v config_spi_tb.v
	vvp /tmp/chimaera-config-spi.vvp
	iverilog -g2012 -s host_interface_tb -o /tmp/chimaera-host-interface.vvp $(SRC_DIR)/chimaera_config_spi.v $(SRC_DIR)/chimaera_program_loader.v $(SRC_DIR)/chimaera_host_interface.v host_interface_tb.v
	vvp /tmp/chimaera-host-interface.vvp
	iverilog -g2012 -s program_runtime_tb -o /tmp/chimaera-program-runtime.vvp $(SRC_DIR)/chimaera_reaction_cell.v $(SRC_DIR)/chimaera_generic_execution_engine.v $(SRC_DIR)/chimaera_program_runtime.v program_runtime_tb.v
	vvp /tmp/chimaera-program-runtime.vvp
	iverilog -g2012 -s phase5_loader_top_tb -o /tmp/chimaera-phase5-top.vvp $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES)) phase5_loader_top_tb.v
	vvp /tmp/chimaera-phase5-top.vvp

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
VERILOG_SOURCES += $(CURDIR)/gate_level_netlist.v

endif

# Allow sharing configuration between design and testbench via `include`:
COMPILE_ARGS 		+= -I$(SRC_DIR)

# Include the testbench sources:
VERILOG_SOURCES += $(CURDIR)/tb.v
TOPLEVEL = tb

# List test modules to run, separated by commas and without the .py suffix:
COCOTB_TEST_MODULES = test

# include cocotb's make rules to take care of the simulator setup
ifeq ($(filter phase5,$(MAKECMDGOALS)),)
include $(shell cocotb-config --makefiles)/Makefile.sim
endif
