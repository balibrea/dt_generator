#!/bin/bash

#  make_dt.sh
#
#  Copyright 2025 Yosel Balibrea Lastre <yosel@auger.org.ar>
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
#  MA 02110-1301, USA.
#
#

#
# Based in: https://xilinx-wiki.atlassian.net/wiki/spaces/A/pages/18842279/Build+Device+Tree+Blob
#

# Check if XSA file is provided
if [ ! -f "$1" ]; then
    echo "invalid XSA file"
    echo "Usage: $0 <path_to_xsa_file> <output_path"
    exit 1
fi

# Check output folder
if [ ! -d "$2" ]; then
    echo "invalid output path"
    echo "Usage: $0 <path_to_xsa_file> <output_path"
    exit 1
fi

CPU="ps7_cortexa9_0"
XSA_FILE="$(realpath "$1")"
OUTPUT_DIR="$(realpath "$2")"

# Resolve script directory so we can find system-bsp.dtsi alongside this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default Vivado and Vitis paths
VIVADO_VERSION="2022.2"
VIVADO_PATH=/media/balibrea/WH/Development/FPGA/VITIS/Vivado/$VIVADO_VERSION
VITIS_PATH=/media/balibrea/WH/Development/FPGA/VITIS/Vitis/$VIVADO_VERSION

# Default source paths
LINUX_SRC=/media/balibrea/WH/Development/FPGA/Projects/MinizedLinux/linux-xlnx
UBOOT_SRC=/media/balibrea/WH/Development/FPGA/Projects/MinizedLinux/u-boot-xlnx

# Set environment paths
export PATH=$VIVADO_PATH/bin:$PATH
export PATH=$VITIS_PATH/bin:$PATH
export PATH=$UBOOT_SRC/tools:$PATH
export PATH=$LINUX_SRC/scripts/dtc:$PATH

#Cross compiler
export CROSS_COMPILE=arm-linux-gnueabihf-
export ARCH=arm

# Vivado Settings
if [ -f "$VIVADO_PATH/settings64.sh" ]; then
    source $VIVADO_PATH/settings64.sh
else
    echo "Warning: Vivado settings file not found at $VIVADO_PATH/settings64.sh"
    exit 1
fi

# Create the output directory
mkdir -p "$OUTPUT_DIR"

# Clone device-tree-xlnx only if not already present
DT_REPO="$OUTPUT_DIR/device-tree-xlnx"
if [ ! -d "$DT_REPO" ]; then
    git clone https://github.com/Xilinx/device-tree-xlnx "$DT_REPO"
    cd "$DT_REPO"
    git checkout xilinx_v2022.2
    cd "$OUTPUT_DIR"
else
    echo "Using existing device-tree-xlnx at $DT_REPO"
fi

# Run XSCT commands
xsct << EOF

hsi open_hw_design $XSA_FILE
hsi set_repo_path $DT_REPO

set procs [hsi get_cells -hier -filter {IP_TYPE==PROCESSOR}]
puts "List of processors found in XSA is \$procs"

hsi create_sw_design device-tree -os device_tree -proc $CPU

hsi generate_target -dir $OUTPUT_DIR/dts

hsi close_hw_design [hsi current_hw_design]
exit

EOF


echo "Device tree generated in $OUTPUT_DIR/dts"

# Copy custom board file so the compiler can find it
cp "$SCRIPT_DIR/system-bsp.dtsi" "$OUTPUT_DIR/dts/system-bsp.dtsi"

# Inject system-bsp.dtsi include into generated system-top.dts (XSCT doesn't add it)
if ! grep -q 'system-bsp.dtsi' "$OUTPUT_DIR/dts/system-top.dts"; then
    sed -i 's|#include "pcw.dtsi"|#include "pcw.dtsi"\n#include "system-bsp.dtsi"|' "$OUTPUT_DIR/dts/system-top.dts"
fi

# Comment out auto-generated aliases block — serial, spi and bluetooth aliases
# are owned by system-bsp.dtsi; duplicates here would cause conflicts.
sed -i '/^\s*aliases\s*{/,/^\s*};/s/^/\/\/ /' "$OUTPUT_DIR/dts/system-top.dts"

# Compile device tree
cd "$OUTPUT_DIR/dts"
cpp -nostdinc -I include -I arch -undef -x assembler-with-cpp system-top.dts system-top.dts.preprocessed
dtc -I dts -O dtb -i . -o system.dtb -@ ./system-top.dts.preprocessed

echo "<---------------- Test dt generated --------------------->"

dtc -I dtb -O dts -o "$OUTPUT_DIR/system.dts" system.dtb

#createdts -hw /home/balibrea/Documents/FPGA/MINIZED/hdl/Projects/minized_petalinux/MINIZED_2018_3/minized_petalinux_wrapper.xsa -platform-name my_devicetree -out ./dt_output
