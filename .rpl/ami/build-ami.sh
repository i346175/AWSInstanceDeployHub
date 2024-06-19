#!/bin/bash

set -euo pipefail

# Docker image provided and maintained by Image Factory team
REPOSITORY=689349591474.dkr.ecr.us-west-2.amazonaws.com/image-factory/image-bakery:stable

echo "Logging in to Amazon ECR"
aws ecr get-login-password | docker login --username AWS --password-stdin $REPOSITORY
docker pull $REPOSITORY

# Undoing codebuild's symlink of .git folder. Image factory needs this folder to create AMI. (This will NOT work on local because CodeBuild creates a symlink for .git)
gitdir_location=$(cat .git) && gitdir_destination=${gitdir_location:8}
rm -rf $CODEBUILD_SRC_DIR/.git && mkdir $CODEBUILD_SRC_DIR/.git
mv $gitdir_destination/* $CODEBUILD_SRC_DIR/.git/

# Running a docker container to create AMI 
docker run -e AWS_DEFAULT_REGION -e AWS_CONTAINER_CREDENTIALS_RELATIVE_URI -t -v "$(pwd)":/image-factory/code $REPOSITORY /bin/bash -c "sudo chown -R image-factory:image-factory /image-factory/code; pushd code; build-local.sh $1" 2>&1 | sudo tee output.txt

# Extracting AMI ID from the container. AMI ID will be used in Supply Chain AMI Promote command.
export AMI_ID=$(awk '/us-west-2:/{print $NF;exit;}' output.txt)
echo $AMI_ID > ami-id.txt