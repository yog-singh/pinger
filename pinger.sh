DB_NAME=pinger.db
CURRENT_DIR=$(pwd)

# Usage info
show_help() {
cat << EOF
Usage: ${0##*/} [-n NAME] [-i INTERVAL]
EOF

}

check_if_db_exists () {
  if [ ! -f $CURRENT_DIR/$DB_NAME ]
  then
    sqlite3 $CURRENT_DIR/$DB_NAME "CREATE TABLE pinger_resources (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, url TEXT NOT NULL, interval INTEGER NOT NULL, last_checked_at TIMESTAMP);"
    sqlite3 $CURRENT_DIR/$DB_NAME "CREATE TABLE resource_responses (id INTEGER PRIMARY KEY AUTOINCREMENT, resource BIGINT NOT NULL, latency FLOAT, status_code INTEGER, created_on TIMESTAMP);"
  fi
}

store_records_to_file () {
    sqlite3 $CURRENT_DIR/$DB_NAME ".mode csv" ".output $CURRENT_DIR/temp.csv" "select * from pinger_resources where ((CAST(strftime('%s', CURRENT_TIMESTAMP) as integer) - CAST(strftime('%s', last_checked_at) as integer))/60) >= interval;"
    echo "Read records to check ping..."
}

remove_records_file () {
    rm $CURRENT_DIR/temp.csv
}

check_pinger () {
  store_records_to_file
  cat $CURRENT_DIR/temp.csv | while read -r line ;
  do
    resource_name=$(echo $line | awk -F ',' '{print $2}')
    echo "Checking ping for $resource_name..."
    resource_id=$(echo $line | awk -F ',' '{print $1}')
    read_url=$(echo $line | awk -F ',' '{print $3}')
    response=$(curl --write-out '%{http_code}|%{time_total}' --silent --output /dev/null $read_url)
    current_time=$(date +"%Y-%m-%dT%H:%M:%S")
    status_code=$(echo $response | awk -F '|' '{print $1}')
    latency=$(echo $response | awk -F '|' '{print $2}')
    echo "Resource: $resource_name, Status Code: $status_code, Latency: $latency"
    sqlite3 $CURRENT_DIR/$DB_NAME "insert into resource_responses(resource, latency, status_code, created_on) values($resource_id, $latency, $status_code, CURRENT_TIMESTAMP);"
    sqlite3 $CURRENT_DIR/$DB_NAME "update pinger_resources set last_checked_at = CURRENT_TIMESTAMP where id = $resource_id;"
  done
  temp_file_lines=$(cat $CURRENT_DIR/temp.csv | wc -l)
  if [ $temp_file_lines = 0 ] ; then
    echo "No resource to check..."
  fi
  remove_records_file
}

add_new_pinger_entry () {
    sqlite3 $CURRENT_DIR/$DB_NAME "insert into pinger_resources(name, url, interval) values('$name', '$url', $interval);"
    echo "Added entry in Pinger for $name - $url in interval of $interval minutes"
}

is_new_entry=false
check_if_db_exists

while [ $# -gt 0 ]; do
  key="$1"

  case $key in
    -u|--url)
        url="$2"
        is_new_entry=true
        shift # past argument
        shift # past value
        ;;
    -i|--interval)
        interval="$2"
        shift # past argument
        shift # past value
        ;;
    -n|--name)
        name="$2"
        shift # past argument
        shift # past value
        ;;
    -r|--run)
        check_pinger
        shift # past argument
        ;;
    --help)
	    show_help
	    exit 1
	    ;;
    \?)
        echo "Error: Invalid option"
        exit
        ;;
  esac
done

if [ $is_new_entry = true ] ; then
    add_new_pinger_entry
fi
