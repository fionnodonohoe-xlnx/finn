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

# yellow echo
yecho () {
  echo -e "${YELLOW}$1${NC}"
}

env_flag=0
if [ -z "$FINN_XILINX_PATH" ];then
  recho "Please set the FINN_XILINX_PATH environment variable to the path to your Xilinx tools installation directory (e.g. /opt/Xilinx)."
  recho "FINN functionality depending on Vivado, Vitis or HLS will not be available."
  env_flag=1
fi

if [ -z "$FINN_XILINX_VERSION" ];then
  recho "Please set the FINN_XILINX_VERSION to the version of the Xilinx tools to use (e.g. 2020.1)"
  recho "FINN functionality depending on Vivado, Vitis or HLS will not be available."
  env_flag=1
fi

if [ -z "$PLATFORM_REPO_PATHS" ];then
  recho "Please set PLATFORM_REPO_PATHS pointing to Vitis platform files (DSAs)."
  recho "This is required to be able to use Alveo PCIe cards."
  env_flag=1
fi

if [ -z "$XILINX_XRT" ];then
  recho "Please set XILINX_XRT pointing to the XRT setup script."
  recho "This is required to be able to use Alveo PCIe cards."
  env_flag=1
fi

if [ -z "$SPACK_PATH" ];then
  recho "Please set SPACK_PATH pointing to spack setup script."
  recho "This is required to be able to set workspace environment."
  env_flag=1
fi

if [ $env_flag = 1 ]; then
  return $env_flag
  exit $env_flag
fi

# Absolute path to this script, e.g. /home/user/bin/foo.sh
SCRIPT=$(readlink -f "$0")
# Absolute path this script is in, thus /home/user/bin
SCRIPTPATH=$(dirname "$SCRIPT")

# the settings below will be taken from environment variables if available,
# otherwise the defaults below will be used
: ${SPACK_ENV_NAME="finn_env"}
: ${PY_VENV_NAME="finn_py_venv"}
: ${PY_VENV_PATH=$(realpath "$SCRIPTPATH/$PY_VENV_NAME")}
: ${FINN_SKIP_DEP_REPOS="0"}
: ${FINN_ROOT=$SCRIPTPATH}
: ${FINN_BUILD_DIR=$FINN_HOST_BUILD_DIR}
: ${FINN_SKIP_DEP_REPOS="0"}
: ${OHMYXILINX="${SCRIPTPATH}/deps/oh-my-xilinx"}

export FINN_ROOT=$FINN_ROOT
export FINN_BUILD_DIR=$FINN_BUILD_DIR

# Set paths for local python requirements
REQUIREMENTS="$SCRIPTPATH/requirements_full.txt"
REQUIREMENTS_TEMPLATE="$SCRIPTPATH/requirements_template.txt"
cat $REQUIREMENTS_TEMPLATE | sed "s|\$SCRIPTPATH|${SCRIPTPATH}|gi" > $REQUIREMENTS

setup_spack () {
  # Activate Spack environment
  source $SPACK_PATH
  spack compiler find --scope site
  spack -e ${SCRIPTPATH} concretize --fresh --quiet
  spack -e ${SCRIPTPATH} install
  spack env activate ${SCRIPTPATH}
  # dump the packages and their versions to cmd line
  spack find -xp
}

setup_py_env () {
  # Create/Activate Python VENV
  if [ ! -f "$PY_VENV_PATH/bin/activate" ]; then
    python -m venv $PY_VENV_PATH
  fi
  source "$PY_VENV_PATH/bin/activate"

  # Check if requirements have already been installed, install if not
  echo "INSTALL REQUIREMENTS"
  pip install -r $REQUIREMENTS
  echo $?
  echo "INSTALL REQUIREMENTS - DONE"
  if [ $? -ne 0 ]; then
      echo "$(basename $BASH_SOURCE): Python package installation failed"
      exit 1
  fi
}

delete_virtual_envs () {
  py_venv_path=$1
  yecho "Deleting spack.lock"
  rm spack.lock
  yecho "Deleting $py_venv_path"
  rm -rf $py_venv_path
}

source_xilinx_env () {
  VIVADO_PATH="$FINN_XILINX_PATH/Vivado/$FINN_XILINX_VERSION"
  VITIS_PATH="$FINN_XILINX_PATH/Vitis/$FINN_XILINX_VERSION"
  HLS_PATH="$FINN_XILINX_PATH/Vitis_HLS/$FINN_XILINX_VERSION"

  export VIVADO_PATH=$VIVADO_PATH
  export VITIS_PATH=$VITIS_PATH
  export HLS_PATH=$HLS_PATH

  gecho "VIVADO_PATH: $VIVADO_PATH"
  gecho "VITIS_PATH: $VITIS_PATH"
  gecho "HLS_PATH: $HLS_PATH"

  if [ -f "$VITIS_PATH/settings64.sh" ];then
    # source Vitis env.vars
    source $VITIS_PATH/settings64.sh
    gecho "Found Vitis at $VITIS_PATH"
    if [ -f "$XILINX_XRT/setup.sh" ];then
      # source XRT
      source $XILINX_XRT/setup.sh
      gecho "Found XRT at $XILINX_XRT"
    else
      recho "XRT not found on $XILINX_XRT, did the installation fail?"
    fi
  else
    yecho "Unable to find $VITIS_PATH/settings64.sh"
    yecho "Functionality dependent on Vitis will not be available."
    yecho "Please note that FINN needs at least version 2020.2 for Vitis HLS support."
    yecho "If you need Vitis, ensure VITIS_PATH is set correctly and mounted into the Docker container."
    if [ -f "$VIVADO_PATH/settings64.sh" ];then
      # source Vivado env.vars
      export XILINX_VIVADO=$VIVADO_PATH
      source $VIVADO_PATH/settings64.sh
      gecho "Found Vivado at $VIVADO_PATH"
    else
      yecho "Unable to find $VIVADO_PATH/settings64.sh"
      yecho "Functionality dependent on Vivado will not be available."
      yecho "If you need Vivado, ensure VIVADO_PATH is set correctly and mounted into the Docker container."
    fi
  fi

  if [ -f "$HLS_PATH/settings64.sh" ];then
    # source Vitis HLS env.vars
    source $HLS_PATH/settings64.sh
    gecho "Found Vitis HLS at $HLS_PATH"
  else
    yecho "Unable to find $HLS_PATH/settings64.sh"
    yecho "Functionality dependent on Vitis HLS will not be available."
    yecho "Please note that FINN needs at least version 2020.2 for Vitis HLS support."
    yecho "If you need Vitis HLS, ensure HLS_PATH is set correctly and mounted into the Docker container."
  fi

  # Need g++ from Vitis HLS - can't rely on host OS g++
  PATH=$HLS_LNX_TOOLS_PATH:$PATH
}

if [ "$1" = "clean" ]; then
  echo "Cleaning Spack and Python virtual environments"
  delete_virtual_envs $PY_VENV_PATH
  exit 0
fi

if [ -z "$FINN_ROOT" ];then
  recho "Please set environment variable FINN_ROOT before running this script"
  exit 1
fi

# Ensure git-based deps are checked out at correct commit
if [ "$FINN_SKIP_DEP_REPOS" = "0" ]; then
  ./fetch-repos.sh
fi

# Create/source virtual environments & Xilinx tools
setup_spack
setup_py_env
source_xilinx_env

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
  gecho "Running container with passed arguments"
  FINN_CMD="$@"
fi

if [ -n "$BUILD_CUSTOM_DIR" ]; then
  cd $BUILD_CUSTOM_DIR
fi

FINN_EXEC+="$FINN_CMD"

recho "EXUECUTE: $FINN_EXEC"

$FINN_EXEC