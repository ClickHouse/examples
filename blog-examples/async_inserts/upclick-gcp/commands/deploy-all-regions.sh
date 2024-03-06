#!/usr/bin/env bash
# a quick bash script to deploy UpClick to several regions
declare -a GCP_REGIONS=( "asia-northeast1" "europe-west1" "us-east1" "us-west1" )
for gcp_region in "${GCP_REGIONS[@]}"
do 
    yarn deploy --region=$gcp_region
done
