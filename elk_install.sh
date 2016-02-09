#/bin/bash

ES_DATA_DIR='/es/data'
ES_LOGS='/es/logs'

# CPU Cores avalible to logstash (Total CPUs - 1)
LS_CORES=$(expr $(lscpu|grep '^CPU(s):'|sed -r "s/^CPU\(s\):\s+([0-9]{,})/\1/") - 1)
TOTAL_MEM=$(free -m | head -n2 | tail -1 | sed -r "s/Mem:\s+([0-9]{,})\s+.*/\1/")
KIBANA_URL='https://download.elastic.co/kibana/kibana/kibana-4.3.0-linux-x64.tar.gz'

main() {
    dependencies
    if [ $RET_CODE -eq 0 ]; then
        elasticsearch
    else
        echo "$(date): Error installing java (line: $LINENO)"
        exit 1
    fi
    if [ $RET_CODE -eq 0 ]; then
        logstash
    else
        echo "$(date): Error installing elasticsearch (line: $LINENO)"
        exit 1
    fi
    if [ $RET_CODE -eq 0 ]; then
        kibana
    else
        echo "$(date): Error installing logstash (line: $LINENO)"
        exit 1
    fi
    if [ $RET_CODE -eq 0 ]; then
        nginx
    else
        echo "$(date): Error installing kibana (line: $LINENO)"
        exit 1
    fi

}

dependencies(){
    sleep 1
    echo "$(date): Installing java (line: $LINENO)"
    sudo add-apt-repository -y ppa:webupd8team/java
    sudo apt-get update 2>&1 > /dev/null
    echo "debconf shared/accepted-oracle-license-v1-1 select true" |sudo debconf-set-selections
    echo "debconf shared/accepted-oracle-license-v1-1 seen true" | sudo debconf-set-selections
    sudo apt-get -y install oracle-java8-installer 
    java -version 2>&1 > /dev/null
    RET_CODE=$?
    if [ $RET_CODE -eq 0 ]; then
        echo "$(date): $(java -version 2>&1 | head -n2 | tail -1) (line: $LINENO)"
    fi
}

elasticsearch(){
    sleep 1
    echo "$(date): Installing elasticsearch (line: $LINENO)"
    sudo wget -qO - https://packages.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
    echo "deb http://packages.elastic.co/elasticsearch/2.x/debian stable main" | sudo tee -a /etc/apt/sources.list.d/elasticsearch-2.x.list
    sudo apt-get update 2>&1 > /dev/null
    sudo apt-get -y install elasticsearch
    sudo update-rc.d elasticsearch defaults 95 10
    echo "$(date): Setting up ES data dirs ($LINENO)"
    if [ ! -d "$ES_DATA_DIR" ]; then
        sudo mkdir -p "$ES_DATA_DIR"
    fi
    if [ ! -d "$ES_LOGS" ]; then
        sudo mkdir -p "$ES_LOGS"
    fi
    chown -R elasticsearch.elasticsearch "$ES_DATA_DIR"
    chown -R elasticsearch.elasticsearch "$ES_LOGS"
    if [ -f /etc/elasticsearch/elasticsearch.yml ]; then
        cat /etc/elasticsearch/elasticsearch.yml | sed -r "s/^#\s+(path.data:)\s+(\/.*$)/\1 $(echo "$ES_DATA_DIR" | sed -r "s/\//\\\\\//g")/" > /etc/elasticsearch/elasticsearch.yml
        cat /etc/elasticsearch/elasticsearch.yml | sed -r "s/^#\s+(path.logs:)\s+(\/.*$)/\1 $(echo "$ES_LOGS" | sed -r "s/\//\\\\\//g")/" > /etc/elasticsearch/elasticsearch.yml
    else
        echo "$(date): Could not find /etc/elasticsearch/elasticsearch.yml file (line: $LINENO)"
        exit 1
    fi
    # Set ES heap size to 50% of total memeory
    ES_HEAP_MEM="$(expr $(expr $TOTAL_MEM / 100) \* 50)"
    if [ $ES_HEAP_MEM -gt 30000 ]; then
        # Set it below the 30.5GB limit (https://www.elastic.co/guide/en/elasticsearch/guide/current/heap-sizing.html#compressed_oops)
        ES_HEAP_MEM="30000m"
    else
        ES_HEAP_MEM="${ES_HEAP_MEM}m"
    fi
    cat /etc/init.d/elasticsearch | sed -r "s/^#(ES_HEAP_SIZE=)(.*)$/\1\"$ES_HEAP_MEM\"/" > /etc/init.d/elasticsearch_temp
    mv /etc/init.d/elasticsearch_temp /etc/init.d/elasticsearch
    chmod 755 /etc/init.d/elasticsearch
    sudo /etc/init.d/elasticsearch restart
    echo "$(date): Waiting on elasticsearch to start... (line: $LINENO)"
    sleep 10
    curl -X GET 'http://localhost:9200'
    RET_CODE=$?
}

logstash(){
    sleep 1
    echo "$(date): Installing logstash (line: $LINENO)"
    echo "deb http://packages.elastic.co/logstash/2.1/debian stable main" | sudo tee -a /etc/apt/sources.list
    sudo apt-get update 2>&1 > /dev/null
    sudo apt-get -y install logstash
    
    if [ -f /etc/default/logstash ]; then
        if [ $LS_CORES -lt 1 ]; then
            unset LS_CORES
        fi
        if [ ! -z $LS_CORES ]; then
            cat /etc/default/logstash | sed -r "s/^#(LS_OPTS=)\"(.*)\"$/\1\"-w $LS_CORES\"/" > /etc/default/logstash
        else
            echo "$(date): $LS_CORES not set. Leaving as is (line: $LINENO)"
        fi
        # Set mem use to 25% of total memory
        LS_HEAP_MEM="$(expr $(expr $TOTAL_MEM / 100) \* 25)m"
        cat /etc/default/logstash | sed -r "s/^#(LS_HEAP_SIZE=)\"(.*)\"$/\1\"$LS_HEAP_MEM\"/" > /etc/default/logstash
    else
        echo "$(date): Could not find /etc/default/logstash file (line: $LINENO)"
        exit 1
    fi
    sudo update-rc.d logstash defaults 96 10
}

kibana(){
    sleep 1
    echo "$(date): Installing kibana (line: $LINENO)"
    sudo groupadd kibana
    sudo useradd -g kibana kibana
    TAR_FILE="$(basename "$KIBANA_URL")"
    curl -o "/tmp/$TAR_FILE" "$KIBANA_URL"
    
    sudo tar xf "/tmp/$TAR_FILE" -C /opt/
    # bind to local host
    cat "/opt/${TAR_FILE%.tar.gz}/config/kibana.yml" | sed -r "s/^# (server.host: ).*/\1\"localhost\"/" > "/opt/${TAR_FILE%.tar.gz}/config/kibana.yml"
    chown -R kibana.kibana "/opt/${TAR_FILE%.tar.gz}"

    ln -s "/opt/${TAR_FILE%.tar.gz}" /opt/kibana

    # Set up Kibana init script
    curl -o /etc/init.d/kibana https://raw.githubusercontent.com/sky-uk/elk-bash-deploy/master/resource/kibana-4.x-init.sh
    sudo chmod +x /etc/init.d/kibana
    sudo update-rc.d kibana defaults 97 10
    curl -o /etc/default/kibana https://raw.githubusercontent.com/sky-uk/elk-bash-deploy/master/resource/kibana-4.x-default
    sudo service kibana start
}

nginx(){
    sleep 1
    echo "$(date): Installing kibana (line: $LINENO)"
    sudo apt-get -y install nginx apache2-utils
    curl -o /etc/nginx/sites-available/default https://raw.githubusercontent.com/sky-uk/elk-bash-deploy/master/resource/nginx_default
    sudo /etc/init.d/nginx restart
}

main
