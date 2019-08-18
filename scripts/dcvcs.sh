#!/bin/bash

cd ..
dc_shell -f scripts/synth.tcl -output_log_file compile.log
cd sim
vcs -f ../scripts/source_mapped.f -full64 +v2k +neg_tchk -R -debug_pp +define+SDF_ANNOTATE -l vcs.log
./simv
