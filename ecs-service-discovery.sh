#!/usr/bin/env sh

declare CLUSTERS
declare CLUSTER
declare SERVICES
declare SERVICE
declare TASKS
declare TASK
declare IPS
declare IP

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

Requires the AWS CLI tool, being logged in and having the following policies:
  ecs:ListServices
  ecs:ListTasks
  ecs:DescribeTasks
  ecs:DescribeServices
  route53:ListHostedZones
  route53:ChangeResourceRecordSets
  route53:GetChange

For more information, improvements and bug reports, please visit:
 <https://github.com/wrzlbrmft/ecs-service-discovery>
__END
}

__list_services() {
    local CLUSTER="$1"
    local FILTER="$2"

    # TODO: apply filter
    local SERVICES="$(aws ecs list-services --cluster "${CLUSTER}" --query 'serviceArns[*]' --output text)"
    if [ "$?" -ne 0 ]; then
        printf "fatal error: unable to list services of cluster '%s'\n" "${CLUSTER}" >&2
        exit 1
    fi

    echo "${SERVICES}"
}

__list_tasks() {
    local CLUSTER="$1"
    local SERVICE="$2"

    local TASKS="$(aws ecs list-tasks --cluster "${CLUSTER}" --service-name "${SERVICE}" --query 'taskArns[*]' --output text)"
    if [ "$?" -ne 0 ]; then
        printf "fatal error: unable to list tasks of service '%s' of cluster '%s'\n" "${SERVICE}" "${CLUSTER}" >&2
        exit 1
    fi

    echo "${TASKS}"
}

__describe_task() {
    local CLUSTER="$1"
    local TASK="$2"

    local IPS="$(aws ecs describe-tasks --cluster "${CLUSTER}" --task "${TASK}" --query 'tasks[*].containers[?lastStatus==`RUNNING`].networkInterfaces[*].privateIpv4Address' --output text)"
    if [ "$?" -ne 0 ]; then
        printf "fatal error: unable to describe task '%s' of cluster '%s'\n" "${TASK}" "${CLUSTER}" >&2
        exit 1
    fi

    echo "${IPS}"
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

CLUSTERS="$*"
for CLUSTER in ${CLUSTERS}; do
    printf "cluster: %s\n" "${CLUSTER}"

    SERVICES="$(__list_services "${CLUSTER}" "${FILTER}")"
    for SERVICE in ${SERVICES}; do
        SERVICE="${SERVICE##*/}"
        printf "    service: %s\n" "${SERVICE}"

        TASKS="$(__list_tasks "${CLUSTER}" "${SERVICE}")"
        for TASK in ${TASKS}; do
            TASK="${TASK##*/}"
            printf "        task: %s\n" "${TASK}"

            IPS="$(__describe_task "${CLUSTER}" "${TASK}")"
            for IP in ${IPS}; do
                printf "            ip: %s\n" "${IP}"
            done
        done
    done
done

exit 0
