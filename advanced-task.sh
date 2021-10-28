#!/bin/bash
python3 --version
jq --version
which az
FILENAME=$1
STORAGEACCOUNTNAME=$2
git clone https://github.com/implodingduck/batch-multi-sum.git
cd batch-multi-sum
echo "lets login..."
az login --identity
echo "downloading file..."
az storage blob download --auth-mode login --account-name $STORAGEACCOUNTNAME --container-name input --file $FILENAME -n $FILENAME
cat $FILENAME
python3 run.py ./$FILENAME
cat computed/$FILENAME
echo "time to upload..."
az storage blob upload --auth-mode login --account-name $STORAGEACCOUNTNAME --container-name output --file ./computed/$FILENAME -n $FILENAME