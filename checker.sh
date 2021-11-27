#!/usr/bin/env bash

# Copyright 2021 Google LLC

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     https://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


echo "Active configuration: "
gcloud config list


function clean () {
    this=$1
    temp="${this%\"}"
    that="${temp#\"}"
    echo "$that"
}

DEPLOY_PROJECT_ID=$( clean "$DEPLOY_PROJECT_ID" )
DEPLOY_BUCKET_NAME=$( clean "$DEPLOY_BUCKET_NAME" )
DEPLOY_TEST_DATASET=$( clean "$DEPLOY_TEST_DATASET" )
DEPLOY_TEST_TABLE=$( clean "$DEPLOY_TEST_TABLE" )
DEPLOY_TEST_FILENAME=$( clean "$DEPLOY_TEST_FILENAME" )
DEPLOY_TEST_DATASET_LOCATION=$( clean "$DEPLOY_TEST_DATASET_LOCATION" )


echo "Received parameters:"
echo "DEPLOY to PROJECT: $DEPLOY_PROJECT_ID"
echo "DEPLOY BUCKET NAME: $DEPLOY_BUCKET_NAME"
echo "DEPLOY TEST DATASET: $DEPLOY_TEST_DATASET"
echo "DEPLOY TEST TABLE: $DEPLOY_TEST_TABLE"
echo "DEPLOY TEST FILENAME: $DEPLOY_TEST_FILENAME"
echo "DEPLOY TEST DATASET LOCATION: $DEPLOY_TEST_DATASET_LOCATION"

declare -i SUCCESS
SUCCESS=0

#validate bucket exists
VALIDATE_BUCKET=$( gsutil ls | grep "gs://$DEPLOY_BUCKET_NAME" )
if [[ -z  "$VALIDATE_BUCKET" ]]; then
    echo "Error -- gs://$DEPLOY_BUCKET_NAME not found or accessible"
    SUCCESS=1
else
    # validate we can write objects
    echo "OK -- Can list bucket gs://$DEPLOY_BUCKET_NAME"
    touch "$DEPLOY_TEST_FILENAME"
    echo "This is a test file, safe to delete. $(date)" > "$DEPLOY_TEST_FILENAME"
    gsutil cp "./$DEPLOY_TEST_FILENAME" "gs://$DEPLOY_BUCKET_NAME"

    VALIDATE_FILE=$( gsutil ls "gs://$DEPLOY_BUCKET_NAME/$DEPLOY_TEST_FILENAME" ) 
    if [[ -z "$VALIDATE_FILE" ]]; then
        echo "Error -- Could not create a file in bucket gs://$DEPLOY_BUCKET_NAME . Please ensure SA has correct permisions."
        SUCCESS=1
    else 
        echo "OK -- Can create objects in gs://$DEPLOY_BUCKET_NAME"
        gsutil rm "gs://${DEPLOY_BUCKET_NAME}/$DEPLOY_TEST_FILENAME"

        if [ $? -ne 0 ]; then
        echo "Failed to clean up test file gs://$DEPLOY_BUCKET_NAME/$DEPLOY_TEST_FILENAME , please manually remove it"
        fi 
    fi
fi

# Validate we can create dataset
bq --location "$DEPLOY_TEST_DATASET_LOCATION" mk \
    --dataset \
    "${DEPLOY_PROJECT_ID}:${DEPLOY_TEST_DATASET}"

if [ $? -ne 0 ]; then
    echo "Error -- Failed to create dataset $DEPLOY_TEST_DATASET in project $DEPLOY_PROJECT_ID"
    SUCCESS=1
else
    echo "OK -- Created dataset $DEPLOY_TEST_DATASET in project $DEPLOY_PROJECT_ID"

    # validate we can create a table
    bq mk \
        --table \
        "${DEPLOY_PROJECT_ID}:${DEPLOY_TEST_DATASET}.${DEPLOY_TEST_TABLE}" \
        TEST,STRING

    if [ $? -ne 0 ]; then
        echo "Error -- Failed to create table $DEPLOY_TEST_TABLE in dataset $DEPLOY_PROJECT_ID:$DEPLOY_TEST_DATASET"
        SUCCESS=1
    else
        echo "OK -- Created table $DEPLOY_TEST_TABLE in dataset ${DEPLOY_PROJECT_ID}:${DEPLOY_TEST_DATASET}"

        # can we write to the dataset
        echo '{ "TEST": "deploymet test"}' | bq insert "${DEPLOY_PROJECT_ID}:${DEPLOY_TEST_DATASET}.${DEPLOY_TEST_TABLE}"
        if [ $? -ne 0 ]; then
            echo "Error -- Failed to write record in ${DEPLOY_PROJECT_ID}:${DEPLOY_TEST_DATASET}.${DEPLOY_TEST_TABLE}"
            SUCCESS=1
        else
            echo "OK -- Wrote a test entry to ${DEPLOY_PROJECT_ID}:${DEPLOY_TEST_DATASET}.${DEPLOY_TEST_TABLE}"
        fi

        bq rm -f -t "${DEPLOY_PROJECT_ID}:${DEPLOY_TEST_DATASET}.${DEPLOY_TEST_TABLE}"
        if [ $? -ne 0 ]; then
            echo "Failed to clean up table ${DEPLOY_PROJECT_ID}:${DEPLOY_TEST_DATASET}.${DEPLOY_TEST_TABLE} -- please remove it manually"
        fi
    fi

    bq rm -f -r -d "${DEPLOY_PROJECT_ID}:${DEPLOY_TEST_DATASET}"
    if [ $? -ne 0 ]; then
        echo "Failed to clean up dataset ${DEPLOY_PROJECT_ID}:${DEPLOY_TEST_DATASET} -- please remove it manually"
    fi
fi


if [ $SUCCESS -eq 0 ]; then
    echo "OK -- Validations terminated successfully, you may proceed with deployment"
    exit 0
else
    echo "ERROR -- Terminated with failures, please check the logs above for necessary corrections and try again"
    exit 1
fi