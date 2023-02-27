#!/bin/bash
# Copyright (C) 2023, Advanced Micro Devices, Inc.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
#
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
#
# * Neither the name of FINN nor the names of its
#   contributors may be used to endorse or promote products derived from
#   this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

env_flag=0
if [ -z "$FINN_XILINX_PATH" ];then
  echo "Please set the FINN_XILINX_PATH environment variable to the path to your Xilinx tools installation directory (e.g. /opt/Xilinx)."
  echo "FINN functionality depending on Vivado, Vitis or HLS will not be available."
  env_flag=1
fi

if [ -z "$FINN_XILINX_VERSION" ];then
  echo "Please set the FINN_XILINX_VERSION to the version of the Xilinx tools to use (e.g. 2020.1)"
  echo "FINN functionality depending on Vivado, Vitis or HLS will not be available."
  env_flag=1
fi

if [ -z "$PLATFORM_REPO_PATHS" ];then
  echo "Please set PLATFORM_REPO_PATHS pointing to Vitis platform files (DSAs)."
  echo "This is required to be able to use Alveo PCIe cards."
  env_flag=1
fi

if [ -z "$SPACK_PATH" ];then
  echo "Please set SPACK_PATH pointing to spack setup script."
  echo "This is required to be able to set workspace environment."
  env_flag=1
fi

if [ $env_flag = 1 ]; then
  echo "Correctly set Env Variables as described above"
  return $env_flag
fi

# Absolute path to this script, e.g. /home/user/bin/foo.sh
SCRIPT=$(readlink -f "$0")
# Absolute path this script is in, thus /home/user/bin
SCRIPTPATH=$(dirname "$SCRIPT")
VENV_NAME="finn_venv"
SPACK_ENV_NAME="finn_env"
REQUIREMENTS="$SCRIPTPATH/requirements_full.txt"
REQUIREMENTS_TEMPLATE="$SCRIPTPATH/requirements_template.txt"

# Set paths for local python requirements
cat $REQUIREMENTS_TEMPLATE | sed "s|\$SCRIPTPATH|${SCRIPTPATH}|gi" > $REQUIREMENTS

# the settings below will be taken from environment variables if available,
# otherwise the defaults below will be used
: ${FINN_SKIP_DEP_REPOS="0"}
: ${FINN_ROOT=$SCRIPTPATH}
: ${FINN_BUILD_DIR="$FINN_ROOT/../tmp"}
: ${VENV_PATH=$(realpath "$SCRIPTPATH/../$VENV_NAME")}

export FINN_ROOT=$FINN_ROOT
export FINN_BUILD_DIR=$FINN_BUILD_DIR

# Activate Spack environment
source $SPACK_PATH
spack compiler find --scope site
spack -e ${SCRIPTPATH} concretize --fresh --quiet
spack -e ${SCRIPTPATH} install
spack env activate ${SCRIPTPATH}
# dump the packages and their versions to cmd line
spack find -xp

# Create/Activate Python VENV
if [ ! -f "$VENV_PATH/bin/activate" ]; then
  python -m venv $VENV_PATH
fi
source "$VENV_PATH/bin/activate"

# Check if requirements have already been installed, install if not
pip install -r $REQUIREMENTS

# ensure build dir exists locally
mkdir -p $FINN_BUILD_DIR

# Ensure git-based deps are checked out at correct commit
if [ "$FINN_SKIP_DEP_REPOS" = "0" ]; then
  ./fetch-repos.sh
fi

if [ -n "$FINN_XILINX_PATH" ]; then
  VITIS_PATH="$FINN_XILINX_PATH/Vitis/$FINN_XILINX_VERSION/"
  if [ -f "$VITIS_PATH/settings64.sh" ]; then
    source "$VITIS_PATH/settings64.sh"
    echo "Found Vitis at $VITIS_PATH"
  else
    echo "Unable to find $VITIS_PATH/settings64.sh"
    echo "Functionality dependent on Vitis HLS will not be available."
    echo "Please note that FINN needs at least version 2020.2 for Vitis HLS support."
    echo "If you need Vitis HLS, ensure FINN_XILINX_PATH is set correctly."
  fi
fi
