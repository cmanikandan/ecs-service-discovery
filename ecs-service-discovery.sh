#!/usr/bin/env sh

declare CLUSTER

__help() {
    cat << __END
ECS Service Discovery for Amazon Web Services
Usage: ecs-service-discovery.sh [options] cluster...

Options:
  -d             Perform a dry-run without making any changes.
  -f <filter>    Filter service names using a grep-compatible regex.
  -p <prefix>    Prefix to put in front of the service name in Route 53.
  -s <suffix>    Suffix to append to the service name in Route 53.
  -z <zone>      Route 53 zone to update.
  -h             Print this help message and exit.

If no Route 53 zone is specified using -z, the cluster name is being used.

For bug reports and improvements, please visit:
 <https://github.com/wrzlbrmft/ecs-service-discovery>
__END
}

# main

declare DRY_RUN
declare FILTER
declare PREFIX
declare SUFFIX
declare ZONE

while getopts :df:hp:s:z: OPT; do
    case "${OPT}" in
        h)
            __help
            exit 0
            ;;

        d)
            DRY_RUN="1"
            ;;

        f)
            FILTER="${OPTARG}"
            ;;

        p)
            PREFIX="${OPTARG}"
            ;;

        s)
            SUFFIX="${OPTARG}"
            ;;

        z)
            ZONE="${OPTARG}"
            ;;

        :)
            printf "fatal error: " >&2
            case "${OPTARG}" in
                f)
                    printf "missing filter" >&2
                    ;;

                p)
                    printf "missing prefix" >&2
                    ;;

                s)
                    printf "missing suffix" >&2
                    ;;

                z)
                    printf "missing zone" >&2
                    ;;
            esac
            printf "\n" >&2
            exit 1
            ;;

        \?)
            printf "fatal error: invalid option ('-%s')\n" "${OPTARG}" >&2
            # __help
            exit 1
            ;;
    esac
done
shift "$((OPTIND-1))"

if [ -z "$*" ]; then
    printf "fatal error: no ecs cluster\n" >&2
    exit 1
fi

for CLUSTER in "$@"; do
    printf "%s\n" "${CLUSTER}"
done

exit 0
