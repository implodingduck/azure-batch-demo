import logging

import azure.functions as func
from azure.batch import BatchServiceClient
from azure.batch.batch_auth import SharedKeyCredentials
import azure.batch.models as batchmodels
import os
import uuid

def main(myblob: func.InputStream):
    logging.info(f"Python blob trigger function processed blob \n"
                 f"Name: {myblob.name}\n"
                 f"Blob Size: {myblob.length} bytes")
    BATCH_ACCOUNT_NAME = os.environ.get('BATCH_ACCOUNT_NAME')
    BATCH_ACCOUNT_ENDPOINT = os.environ.get('BATCH_ACCOUNT_ENDPOINT')
    BATCH_ACCOUNT_KEY = os.environ.get('BATCH_ACCOUNT_KEY')
    pool_id = os.environ.get('BATCH_POOL_ID')
    credentials = SharedKeyCredentials(BATCH_ACCOUNT_NAME,
        BATCH_ACCOUNT_KEY)

    batch_client = BatchServiceClient(
        credentials,
        batch_url=BATCH_ACCOUNT_ENDPOINT)

    job_id = uuid.uuid4()
    job = batchmodels.JobAddParameter(
        id=job_id,
        pool_info=batchmodels.PoolInformation(pool_id=pool_id))

    batch_client.job.add(job)
    
    tasks = list()
    
    # TOKEN=$(curl 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fstorage.azure.com%2F' -H Metadata:true | jq -r .access_token)
    # curl https://<STORAGE ACCOUNT>.blob.core.windows.net/<CONTAINER NAME>/<FILE NAME> -H "x-ms-version: 2017-11-09" -H "Authorization: Bearer <ACCESS TOKEN>"
    
    filename = f"{myblob.name.replace('input/', '').replace('.csv', '')}.csv"
    command = f"/bin/bash -c \"curl -O https://raw.githubusercontent.com/implodingduck/azure-batch-demo/main/advanced-task.sh && chmod +x advanced-task.sh && ./advanced-task.sh {filename} \""
    task = batchmodels.TaskAddParameter(
            id=uuid.uuid4(),
            command_line=command
        )
    tasks.append(task)

    batch_client.task.add_collection(job_id, tasks)
