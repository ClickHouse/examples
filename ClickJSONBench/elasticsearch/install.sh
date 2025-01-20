#!/bin/bash 

# Install elasticsearch
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
sudo apt-get install apt-transport-https
echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-8.x.list
sudo apt-get update && sudo apt-get install elasticsearch

# # Install filebeat
curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-8.17.0-amd64.deb
sudo dpkg -i filebeat-8.17.0-amd64.deb

# # Overwrite configuration files
sudo cp config/elasticsearch.yml /etc/elasticsearch/elasticsearch.yml
sudo cp config/jvm.options /etc/elasticsearch/jvm.options

# # Start elasticsearch
sudo systemctl start elasticsearch.service

# Reset and export elastic password
export ELASTIC_PASSWORD=$(sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -s -a -b -u elastic)

# Save elastic password in local file
echo "ELASTIC_PASSWORD=$ELASTIC_PASSWORD" > .elastic_password

# Generate api key for filebeat
curl -s -k -X POST "https://localhost:9200/_security/api_key" -u "elastic:${ELASTIC_PASSWORD}" -H 'Content-Type: application/json' -d '
{
  "name": "filebeat",
  "role_descriptors": {
    "filebeat_writer": { 
      "cluster": ["monitor", "read_ilm", "read_pipeline"],
      "index": [
        {
          "names": ["bluesky-*"],
          "privileges": ["view_index_metadata", "create_doc", "auto_configure"]
        }
      ]
    }
  }
}' | jq -r '"\(.id):\(.api_key)"' > .filebeat_api_key



