#!/bin/bash

# Load MATLAB
module purge
module load ohpc
module load matlab/2025b

# Initialize Conda
source /apps/miniconda/25.9/etc/profile.d/conda.sh

# Activate Python environment
conda activate /user/jilian.xiong/.conda/envs/matlab_engine

# Add MATLAB libraries
export LD_LIBRARY_PATH=/apps/matlab/r2025b/bin/glnxa64:${LD_LIBRARY_PATH:-}

echo "MATLAB Engine environment activated!"
