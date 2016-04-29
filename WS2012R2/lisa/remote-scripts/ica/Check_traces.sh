#!/bin/bash
function CheckForError()
{   while true; do
        [[ -f "/var/log/syslog" ]] && logfile="/var/log/syslog" || logfile="/var/log/messages"
        a=$(grep -i "Call Trace" $logfile)
        if [[ -n $a ]]; then
            LogMsg "Warning: System get Call Trace in $logfile"
            echo "Warning: System get Call Trace in $logfile" >> ~/summary.log
            break
        fi

    done
}


CheckForError &

exit 0