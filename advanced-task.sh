#!/bin/bash
python3 --version
jq --version
FILENAME=$1
git clone https://github.com/implodingduck/batch-multi-sum.git
cd batch-multi-sum
TOKEN=$(curl "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fstorage.azure.com%2F" -H Metadata:true | jq -r .access_token)
curl -v -O -H "x-ms-version: 2020-10-02" -H "Authorization: Bearer $TOKEN" "https://satriggerjrt448d3.blob.core.windows.net/input/$FILENAME"
echo "$TOKEN and $FILENAME"
python3 run.py ./$FILENAME
cat computed/$FILENAME
FILESIZE=$(stat --printf="%s" computed/$FILENAME)
curl -v -X PUT -T ./computed/$FILENAME -H "x-ms-date: $(date -u)" -H "x-ms-blob-type: BlockBlob" -H "x-ms-version: 2020-10-02" -H "Content-Length: $FILESIZE" -H "Authorization: Bearer $TOKEN" "https://satriggerjrt448d3.blob.core.windows.net/output/$FILENAME"