#!/system/bin/sh
MODDIR=${0%/*}

# Start local WebUI server for browser access
pkill -f webui_server 2>/dev/null
if [ -f "$MODDIR/webui_server" ]; then
    chmod 755 "$MODDIR/webui_server"
    sh -c "exec $MODDIR/webui_server $MODDIR/webroot </dev/null >/data/local/tmp/server.log 2>&1 &"
fi

sleep 10
settings put global low_power 0
