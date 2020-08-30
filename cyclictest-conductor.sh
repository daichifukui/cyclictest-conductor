#!/bin/bash

set -e

DIR=cyclictest-logfile

if [ "$#" -lt 2 ];then
	echo "usage: $0 <guest options> <host options> [-nostress] [-minutes <minutes>]"
	echo "where options are one of 'none cpu io both'"
	false	
fi

if [ "$USER" != "root" ];then
	echo "run as root"
	false
fi

mkdir -p $DIR
rm -rf $DIR/logfile

exec 19> $DIR/logfile
export BASH_XTRACEFD=19

set -x

TIME="$(date +%m%d%H%M%S)"
GUEST="$1" # none cpu io both
HOST="$2" # none cpu io both
MINUTES=1 # default

shift;shift;
while :
do
	opt="${1}"
	case "${opt}" in
		"-nostress" 	) NOSTRESS="${opt}";;
		"-minutes"  	) prev_opt="${opt}";;
		[0-9]*		) case "${prev_opt}" in
					"-minutes"	) MINUTES="${opt}";;
				  esac
				  ;;
		*		) break
	esac
	shift
done

HISTFILE="$DIR/histo-$GUEST-$HOST-$TIME${NOSTRESS}.log"

minute="12000"
DURATION="$(echo ${MINUTES}*${minute}|bc -ql)" # given -i 5000, 12000 is 1 minute

if [ "${NOSTRESS}" != "-nostress" ];then
	stress-ng \
		--cpu $(nproc) \
		--io $(nproc) \
		--vm $(nproc) \
		--vm-bytes 256M \
		--fork $(nproc) \
		--sched-prio 98 \
		--quiet &

	STRESS_PID="$!"
fi

sleep 1

cyclictest \
	-i 5000 \
	-l ${DURATION} \
	--policy=fifo \
	--priority=99 \
	--affinity=0 \
	-h 1000 \
	--histfile=${HISTFILE}

set +x
exec 19>&- # Ref: https://serverfault.com/a/579078

# add command log
echo "# HOST COMMAND LOG" >> ${HISTFILE}
sed 's/^/\# /g' $DIR/logfile >> ${HISTFILE}

ln -sf ../${HISTFILE} $DIR/histo-$GUEST-$HOST${NOSTRESS}-latest.log

if [ "${NOSTRESS}" != "-nostress" ];then
	kill -SIGTERM ${STRESS_PID}
fi

set +e
