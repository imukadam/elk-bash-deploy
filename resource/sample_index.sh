#/bin/bash

sudo service logstash stop
sleep 10
curl -o /etc/logstash/conf.d/kibana_logstash.conf https://raw.githubusercontent.com/sky-uk/elk-bash-deploy/master/resource/kibana_logstash.conf
sudo service logstash start
