# Build ffmpeg with CUDA support from source.
FROM nvcr.io/nvidia/cuda:12.0.1-cudnn8-devel-ubuntu20.04 as builder
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install --no-install-recommends -y \
        automake \
        autoconf \
        build-essential \
        git \
        libc6-dev \
        libssl-dev \
        libtool \
        libx264-dev \
        libxcb1-dev \
        libxau-dev \
        libxdmcp-dev \
        pkg-config \
        yasm && \
    apt-get clean

# --- Build ffmpeg with CUDA support from source ---
RUN git clone --depth 1 --branch n12.0.16.0 https://git.videolan.org/git/ffmpeg/nv-codec-headers.git && \
    cd nv-codec-headers && \
    make install && \
    cd .. && \
    git clone https://git.ffmpeg.org/ffmpeg.git --depth 1 ffmpeg/ && \
    cd ffmpeg && \
    ./configure \
        --enable-nonfree \
        --enable-cuda-nvcc \
        --enable-libnpp \
        --enable-openssl \
        --disable-doc \
        --disable-ffplay \
        --enable-libx264 \
        --enable-gpl \
        --extra-cflags=-I/usr/local/cuda/include \
        --extra-ldflags=-L/usr/local/cuda/lib64 && \
    make -j 8 && \
    make install

# Start over from the docker image with cuda 12.0
FROM nvcr.io/nvidia/cuda:12.0.1-cudnn8-runtime-ubuntu20.04
COPY --from=builder /usr/local/bin/ffmpeg /usr/local/bin/ffmpeg
ARG DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && \
    apt-get install --no-install-recommends -y \
        libc6 \
        libmagic1 \
        libgl1 \
        libglib2.0-0 \
        libx264-155 \
        libxau6 \
        libxcb1 \
        libxdmcp6 \
        openssl \
        wget && \
    apt-get clean

# Install Miniconda
RUN wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda.sh && \
    bash ~/miniconda.sh -b -p $HOME/miniconda && \
    rm ~/miniconda.sh && \
    $HOME/miniconda/bin/conda init && \
    $HOME/miniconda/bin/conda config --set always_yes yes --set changeps1 no && \
    $HOME/miniconda/bin/conda update -q conda && \
    ln -s $HOME/miniconda/bin/conda /usr/local/bin/conda

# Set environment variables for user
ARG NB_USER=jovyan
ARG NB_UID=1000
ENV USER=${NB_USER} \
    NB_UID=${NB_UID} \
    HOME=/home/${NB_USER}

RUN adduser --disabled-password \
    --gecos "Default user" \
    --uid ${NB_UID} \
    ${NB_USER}

# Switch to the new user
USER ${NB_USER}

# Add Conda to PATH after the user is set
ENV PATH="$HOME/miniconda/bin:$PATH"

# Create a working directory
WORKDIR /usr/src/app

COPY . ./kso

# Install python and git
RUN apt-get update && \
    apt-get install --no-install-recommends -y \
        python3.8 \
        python3-pip \
        python3-dev \
        build-essential \
        git \
        vim && \
    apt-get clean && \
    python3 -m pip --no-cache-dir install --upgrade pip && \
    python3 -m pip --no-cache-dir install numpy && \
    python3 -m pip --no-cache-dir install \
        -r /usr/src/app/kso/requirements.txt && \
    python3 -m pip uninstall -y opencv-python opencv-contrib-python && \
    conda install -v -c conda-forge opencv && \
    cp \
        /usr/src/app/kso/src/autobackend.py \
        /usr/local/lib/python3.8/dist-packages/ultralytics/nn/autobackend.py && \
    apt-get remove --autoremove -y python3-dev build-essential

# Set environment variables
ENV WANDB_DIR=/mimer/NOBACKUP/groups/snic2021-6-9/ \
    WANDB_CACHE_DIR=/mimer/NOBACKUP/groups/snic2021-6-9/ \
    WANDB_DATA_DIR=/mimer/NOBACKUP/groups/snic2021-6-9/ \
    DATA_DIR=/tmp \
    ARTIFACT_DIR=/tmp \
    PYTHONPATH=$PYTHONPATH:/usr/src/app/kso
