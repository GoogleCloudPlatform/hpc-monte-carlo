# Copyright 2018 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Makefile
#
# basic commandlines stored that execute the various pieces of the demonstration

show:
	cat README.md

createimages: condor-master condor-compute condor-submit
	@echo "createimages - done"

condor-master condor-compute condor-submit:
	@if [ -z "$$(gcloud compute images list --quiet --filter='name~^$@' --format=text)" ]; then \
	   echo "" ;\
	   echo "- building $@" ;\
	   echo ""; \
	   gcloud compute  instances create  $@-template \
	     --zone=us-east1-b \
	     --machine-type=n1-standard-1 \
	     --image=debian-9-stretch-v20210122 \
	     --image-project=debian-cloud \
	     --boot-disk-size=10GB \
	     --metadata-from-file startup-script=startup-scripts/$@.sh ; \
	   sleep 300 ;\
	   gcloud compute instances stop --zone=us-east1-b $@-template ;\
	   gcloud compute images create $@  \
	     --source-disk $@-template   \
	     --source-disk-zone us-east1-b   \
	     --family htcondor-debian ;\
	   gcloud compute instances delete --quiet --zone=us-east1-b $@-template ;\
	else \
	   echo "$@ image already exists"; \
	fi


deleteimages:
	-gcloud compute images delete --quiet condor-master
	-gcloud compute images delete --quiet condor-compute
	-gcloud compute images delete --quiet condor-submit

download:
ifeq ($(apikey),)
	@echo "Please Register at https://www.quandl.com/sign-up-modal and when you get an API key, rerun this command"
	@echo "with the apikey defined:"
	@echo "  make download apikey=\"<add your quandl key here>\""
else 
	@echo "using apikey=${apikey} to download datafile"
	@wget -O - "https://www.quandl.com/api/v3/datatables/WIKI/PRICES?qopts.export=true&api_key=${apikey}&date.gt=2018-01-01" | python -c "import sys, json; print json.load(sys.stdin)['datatable_bulk_download']['file']['link']" > link.file
	@wget -i link.file -O WIKI_PRICES_2018-01-01.zip
	@unzip WIKI_PRICES_2018-01-01.zip
	@mv WIKI_PRICES*.csv data/WIKI_PRICES_2018-01-01.csv
	-@rm WIKI_PRICES_2018-01-01.zip
endif

upload: data/WIKI_PRICES_2018-01-01.csv htcondor/run_htcondor.sh
ifeq ($(bucketname),)
	@echo "to upload the datafile (make sure you first run make download to pull the data from quandl.  then rerun this command"
	@echo "adding the gcs bucketname to create and push the data to."
	@echo "  make upload bucketname=<some bucket name>"
else 
	@echo "using ${bucketname}"
	-gsutil mb gs://${bucketname}
	gsutil cp data/WIKI_PRICES_2018-01-01.csv gs://${bucketname}/data/
	gsutil cp data/companies.csv gs://${bucketname}/data/
	gsutil cp model/* gs://${bucketname}/model/
	gsutil cp htcondor/* gs://${bucketname}/htcondor/
endif

htcondor/run_htcondor.sh:
	cp htcondor/run_montecarlo.sh.orig htcondor/run_montecarlo.sh
ifneq ($(bucketname),)
	sed -i 's/YOURBUCKETNAME/${bucketname}/g' htcondor/run_montecarlo.sh 
endif

createcluster:
	@echo "creating a condor cluster using deployment manager scripts"
	gcloud deployment-manager deployments create condor-cluster --config deploymentmanager/condor-cluster.yaml
	
destroycluster:
	@echo "destroying the condor cluster"
	gcloud deployment-manager deployments delete condor-cluster

ssh:
ifeq ($(bucketname),)
	@echo "set the bucketname in order to copy some of the data and model files to the submit host"
	@echo "  make sshtocluster bucketname=<some bucket name>"
	gcloud compute ssh condor-submit
else
	@echo "using ${bucketname}"
	@echo "before sshing to the submit host, let me copy some of the files there to make"
	@echo "it easier for you."
	@echo "  - copying the model"
	gcloud compute ssh condor-submit --command "gsutil cp gs://${bucketname}/model/* ."
	@echo "  - copying the datafiles"
	gcloud compute ssh condor-submit --command "gsutil cp gs://${bucketname}/data/* ./"
	@echo "  - copying the condor submit files templates"
	gcloud compute ssh condor-submit --command "gsutil cp gs://${bucketname}/htcondor/* ."
	@echo "now just sshing"
	gcloud compute ssh condor-submit
endif

bq: 
ifeq ($(bucketname),)
	@echo "to upload result file to bigquery, rerun this command but add the bucketname"
	@echo "  make bq bucketname=<some bucket name>"
else
	@echo "loading data from gs://${bucketname}/output/*.csv to bigquery table varBQTable"
	-bq mk montecarlo_outputs
	bq load --autodetect --source_format=CSV ${GOOGLE_CLOUD_PROJECT}:montecarlo_outputs.vartable gs://${bucketname}/output/*.csv 
	cat bq-aggregate.sql | bq query --destination_table montecarlo_outputs.portfolio > /dev/null
	@echo "\n"
	@echo "done..."
endif

rmbq:
	@echo "deleting dataset from bq: ${GOOGLE_CLOUD_PROJECT}:montecarlo_outputs"
	bq rm -rf ${GOOGLE_CLOUD_PROJECT}:montecarlo_outputs
	@echo "\n"
	@echo "done..."


clean:
	rm link.file WIKI_PRICES*.zip WIKI_PRICES*.csv 
