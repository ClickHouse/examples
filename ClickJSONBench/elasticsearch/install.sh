# Install elasticsearch
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
sudo apt-get install apt-transport-https
echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-8.x.list
sudo apt-get update && sudo apt-get install elasticsearch

# Install filebeat
curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-8.17.0-amd64.deb
sudo dpkg -i filebeat-8.17.0-amd64.deb

# Start elasticsearch
sudo systemctl start elasticsearch.service

