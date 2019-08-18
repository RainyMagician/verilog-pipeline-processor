#!/bin/bash

cd ../sim
vcs -f ../scripts/source.f -full64 +v2k -R -debug_pp -l vcs.log
./simv
