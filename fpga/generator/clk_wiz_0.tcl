##################################################################
# CHECK VIVADO VERSION
##################################################################

set scripts_vivado_version 2025.2
set current_vivado_version [version -short]

if { [string first $scripts_vivado_version $current_vivado_version] == -1 } {
  catch {common::send_msg_id "IPS_TCL-100" "ERROR" "This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Please run the script in Vivado <$scripts_vivado_version> then open the design in Vivado <$current_vivado_version>. Upgrade the design by running \"Tools => Report => Report IP Status...\", then run write_ip_tcl to create an updated script."}
  return 1
}

##################################################################
# START
##################################################################

# To test this script, run the following commands from Vivado Tcl console:
# source clk_wiz_0.tcl
# If there is no project opened, this script will create a
# project, but make sure you do not have an existing project
# in the current working folder.

set list_projs [get_projects -quiet]
if { $list_projs eq "" } {
  create_project clk_wiz_0 . -force -part $::env(XILINX_PART)
  set_property BOARD_PART digilentinc.com:arty-a7-100:part0:1.1 [current_project]
  set_property target_language Verilog [current_project]
  set_property simulator_language Mixed [current_project]
}

##################################################################
# CHECK IPs
##################################################################

set bCheckIPs 1
set bCheckIPsPassed 1
if { $bCheckIPs == 1 } {
  set list_check_ips { xilinx.com:ip:clk_wiz:6.0 }
  set list_ips_missing ""
  common::send_msg_id "IPS_TCL-1001" "INFO" "Checking if the following IPs exist in the project's IP catalog: $list_check_ips ."

  foreach ip_vlnv $list_check_ips {
  set ip_obj [get_ipdefs -all $ip_vlnv]
  if { $ip_obj eq "" } {
    lappend list_ips_missing $ip_vlnv
    }
  }

  if { $list_ips_missing ne "" } {
    catch {common::send_msg_id "IPS_TCL-105" "ERROR" "The following IPs are not found in the IP Catalog:\n  $list_ips_missing\n\nResolution: Please add the repository containing the IP(s) to the project." }
    set bCheckIPsPassed 0
  }
}

if { $bCheckIPsPassed != 1 } {
  common::send_msg_id "IPS_TCL-102" "WARNING" "Will not continue with creation of design due to the error(s) above."
  return 1
}

##################################################################
# CREATE IP clk_wiz_0
##################################################################

set clk_wiz_0 [create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clk_wiz_0]

# User Parameters
set_property -dict [list \
CONFIG.PRIM_IN_FREQ {20.000} \
  CONFIG.CLKIN1_JITTER_PS {500.0} \
  CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {148.5} \
  CONFIG.MMCM_DIVCLK_DIVIDE {1} \
  CONFIG.MMCM_CLKFBOUT_MULT_F {44.550} \
  CONFIG.MMCM_CLKOUT0_DIVIDE_F {6.000} \
  CONFIG.CLKOUT1_JITTER {198.608} \
  CONFIG.CLKOUT1_PHASE_ERROR {161.439} \
] [get_ips clk_wiz_0]

##################################################################
# GENERATE TARGETS AND SYNTHESIS
##################################################################

# 1. Obtener la ruta del archivo XCI que se acaba de crear
set ip_xci [get_files -all -of_objects [get_ips clk_wiz_0] *.xci]

# 2. Generar los targets (esto crea las subcarpetas dentro de IP/)
generate_target {instantiation_template} $ip_xci
generate_target all $ip_xci

# 3. Crear y lanzar la síntesis de la IP (Out-of-Context)
# Esto genera el archivo .dcp que el Makefile necesita para no fallar
create_ip_run $ip_xci
launch_run -jobs 8 clk_wiz_0_synth_1
wait_on_run clk_wiz_0_synth_1

##################################################################
