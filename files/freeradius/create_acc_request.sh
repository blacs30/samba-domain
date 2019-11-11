#!/usr/bin/env bash
#set -x
#set -e
AUTH_REQUEST_FILE=/var/log/freeradius/radacct/reply-detail
ACCT_TEMP_FILE=/var/log/freeradius/radacct/reply_detail.tmp
ACCT_TEMP_FILE_NEW=/var/log/freeradius/radacct/reply_detail_new.tmp
ACCT_REQUEST_FILE=/var/log/freeradius/radacct/detail
ACCT_REQUEST_FILE_WORK=/var/log/freeradius/radacct/detail.work

if [ -f $AUTH_REQUEST_FILE ]; then
    cp $AUTH_REQUEST_FILE $ACCT_TEMP_FILE
    rm $AUTH_REQUEST_FILE
fi

if [ -f $ACCT_TEMP_FILE ]; then
    sed -i.bak '/Access-Accept/d' $ACCT_TEMP_FILE
    sed -i.bak '/MS-MPPE/d' $ACCT_TEMP_FILE
    sed -i.bak '/EAP-MSK/d' $ACCT_TEMP_FILE
    sed -i.bak '/EAP-EMSK/d' $ACCT_TEMP_FILE
    sed -i.bak '/EAP-Session/d' $ACCT_TEMP_FILE
    sed -i.bak '/EAP-Message/d' $ACCT_TEMP_FILE
    sed -i.bak '/Message-Authenticator/d' $ACCT_TEMP_FILE

    [ "$?" = "0" ] && rm -f $ACCT_TEMP_FILE.bak
else
    exit
fi

started=0
delete=0
while read -r line
do
    case $(echo $line | cut -d ' ' -f 1) in
        Mon|Tue|Wed|Thu|Fri|Sat|Sun)
            started=1
            delete=0
            block=("${line}")
            continue
            ;;
    esac
    if [[ $line = *"User-Name"* ]] && [ $started -eq 1 ]; then
        delete=1
    elif [ $delete -ne 1 ]; then
        block=("${block[@]}" "${line}")
    fi

    if [ $delete -ne 1 ] && [[ $line = *"Timestamp"* ]]; then
        array_items=${#block[@]}
        if [ $array_items -gt 3 ]; then
            first_run=1
            for ix in ${!block[@]}
            do
                if [ $first_run -eq 1 ]; then
                    printf "%s\n" "${block[$ix]}"
                    printf "%s\n" "${block[$ix]}" >> $ACCT_TEMP_FILE_NEW
                    first_run=0
                else
                    printf "\t%s\n" "${block[$ix]}"
                    printf "\t%s\n" "${block[$ix]}" >> $ACCT_TEMP_FILE_NEW
                fi
            done
            printf "\n" >> $ACCT_TEMP_FILE_NEW
        fi
    fi

    started=0
done < "$ACCT_TEMP_FILE"

if [ "$?" = "0" ]; then
  test -f $ACCT_TEMP_FILE_NEW \
  && chmod 777 $ACCT_TEMP_FILE_NEW \
  && mv $ACCT_TEMP_FILE_NEW $ACCT_REQUEST_FILE
  test -f $ACCT_TEMP_FILE && rm $ACCT_TEMP_FILE
else
  test -f $ACCT_TEMP_FILE && rm $ACCT_TEMP_FILE
  test -f $ACCT_TEMP_FILE_NEW && rm $ACCT_TEMP_FILE_NEW
fi
