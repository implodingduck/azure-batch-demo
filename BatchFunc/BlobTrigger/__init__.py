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
    BATCH_JOB_ID = os.environ.get('BATCH_JOB_ID')
    TRIGGER_STORAGE_ACCOUNT_NAME = os.environ.get('TRIGGER_STORAGE_ACCOUNT_NAME')
    pool_id = os.environ.get('BATCH_POOL_ID')
    credentials = SharedKeyCredentials(BATCH_ACCOUNT_NAME,
        BATCH_ACCOUNT_KEY)

    batch_client = BatchServiceClient(
        credentials,
        batch_url=BATCH_ACCOUNT_ENDPOINT)
    
    tasks = list()
    
    filename = f"{myblob.name.replace('input/', '').replace('.csv', '')}.csv"
    command = f"/bin/bash -c \"curl -O https://raw.githubusercontent.com/implodingduck/azure-batch-demo/main/advanced-task.sh && chmod +x advanced-task.sh && ./advanced-task.sh {filename} {TRIGGER_STORAGE_ACCOUNT_NAME}\""
    task = batchmodels.TaskAddParameter(
            id=uuid.uuid4(),
            command_line=command
        )
    tasks.append(task)

    batch_client.task.add_collection(BATCH_JOB_ID, tasks)
