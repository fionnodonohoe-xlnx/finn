#!/bin/bash
# Copyright (c) 2020-2022, Xilinx, Inc.
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

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# green echo
gecho () {
  echo -e "${GREEN}$1${NC}"
}

# red echo
recho () {
  echo -e "${RED}$1${NC}"
}

if [ -z "$FINN_XILINX_PATH" ];then
  recho "Please set the FINN_XILINX_PATH environment variable to the path to your Xilinx tools installation directory (e.g. /opt/Xilinx)."
  recho "FINN functionality depending on Vivado, Vitis or HLS will not be available."
fi

if [ -z "$FINN_XILINX_VERSION" ];then
  recho "Please set the FINN_XILINX_VERSION to the version of the Xilinx tools to use (e.g. 2020.1)"
  recho "FINN functionality depending on Vivado, Vitis or HLS will not be available."
fi

if [ -z "$PLATFORM_REPO_PATHS" ];then
  recho "Please set PLATFORM_REPO_PATHS pointing to Vitis platform files (DSAs)."
  recho "This is required to be able to use Alveo PCIe cards."
fi

if [ -z "$SPACK_PATH" ];then
  recho "Please set SPACK_PATH pointing to spack setup script."
  recho "This is required to be able to set workspace environment."
  exit 1
fi

# Absolute path to this script, e.g. /home/user/bin/foo.sh
SCRIPT=$(readlink -f "$0")
# Absolute path this script is in, thus /home/user/bin
SCRIPTPATH=$(dirname "$SCRIPT")
VENV_NAME="finn_venv"
SPACK_ENV_NAME="finn_env"
REQUIREMENTS="$SCRIPTPATH/requirements_full.txt"
REQUIREMENTS_TEMPLATE="$SCRIPTPATH/requirements_template.txt"
REQUIREMENTS_TMP="$SCRIPTPATH/requirements_tmp.txt"

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
env_list=$(spack env list)
if [[ $env_list != *"$SPACK_ENV_NAME"* ]]; then
  spack env create $SPACK_ENV_NAME spack.yaml
fi
spack env activate $SPACK_ENV_NAME
spack install

# Create/Activate Python VENV
if [ ! -f "$VENV_PATH/bin/activate" ]; then
  python -m venv $VENV_PATH
fi
source "$VENV_PATH/bin/activate"

# Check if requirements have already been installed, install if not
pip freeze > $REQUIREMENTS_TMP
diff $REQUIREMENTS $REQUIREMENTS_TMP &>/dev/null
if [ $? -eq 1 ]; then
  pip install -r $REQUIREMENTS
fi
rm $REQUIREMENTS_TMP

if [ "$1" = "quicktest" ]; then
  gecho "Running test suite (non-Vivado, non-slow tests)"
  FINN_CMD="docker/quicktest.sh"
elif [ "$1" = "build_custom" ]; then
  BUILD_CUSTOM_DIR=$(readlink -f "$2")
  FLOW_NAME=${3:-build}
  gecho "Running build_custom: $BUILD_CUSTOM_DIR/$FLOW_NAME.py"
  FINN_CMD="python -mpdb -cc -cq $FLOW_NAME.py"
else
  gecho "Spack and Python Virtual environments installed"
  gecho "Nothing more to do"
  exit 0
fi

# ensure build dir exists locally
mkdir -p $FINN_BUILD_DIR

# Ensure git-based deps are checked out at correct commit
if [ "$FINN_SKIP_DEP_REPOS" = "0" ]; then
  ./fetch-repos.sh
fi

if [ -n "$BUILD_CUSTOM_DIR" ]; then
  cd $BUILD_CUSTOM_DIR
fi

if [ -n "$FINN_XILINX_PATH" ]; then
  VITIS_PATH="$FINN_XILINX_PATH/Vitis/$FINN_XILINX_VERSION/"
  if [ -f "$VITIS_PATH/settings64.sh" ]; then
    source "$VITIS_PATH/settings64.sh"
    gecho "Found Vitis at $VITIS_PATH"
  else
    yecho "Unable to find $VITIS_PATH/settings64.sh"
    yecho "Functionality dependent on Vitis HLS will not be available."
    yecho "Please note that FINN needs at least version 2020.2 for Vitis HLS support."
    yecho "If you need Vitis HLS, ensure FINN_XILINX_PATH is set correctly."
  fi
fi

FINN_EXEC+="$FINN_CMD"
$FINN_EXEC