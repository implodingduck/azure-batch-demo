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

    command = "/bin/bash -c \"python3 --version && git clone https://github.com/implodingduck/batch-multi-sum.git && cd batch-multi-sum && python3 run.py -g ./values.csv && cat computed/values.csv\""
    task = batchmodels.TaskAddParameter(
            id=uuid.uuid4(),
            command_line=command,
            resource_files=[myblob]
        )

    batch_client.task.add_collection(job_id, [task])
