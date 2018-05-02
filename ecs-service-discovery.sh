#!/usr/bin/env sh

__help() {
    cat << __END
ECS Service Discovery for Amazon Web Services
Usage: ecs-service-discovery.sh [options] cluster...

Options:
  -d             Perform a dry-run without making any changes.
  -f <filter>    Filter service names using a grep-compatible regex.
  -p <prefix>    Prefix to put in front of the service name in Route 53.
  -s <suffix>    Suffix to append to the service name in Route 53.
  -t <ttl>       TTL in seconds for the A records in Route 53 (default: 5).
  -w             Do NOT wait for the change batch to be synced.
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

    local SERVICES="$(aws ecs list-services --cluster "${CLUSTER}" --query 'serviceArns[*]' --output text)"
    if [ "$?" != "0" ]; then
        printf "fatal error: unable to list services of cluster '%s'\n" "${CLUSTER}" >&2
        exit 1
    fi

    printf "${SERVICES}"
}

__list_tasks() {
    local CLUSTER="$1"
    local SERVICE="$2"

    local TASKS="$(aws ecs list-tasks --cluster "${CLUSTER}" --service-name "${SERVICE}" --query 'taskArns[*]' --output text)"
    if [ "$?" != "0" ]; then
        printf "fatal error: unable to list tasks of service '%s' of cluster '%s'\n" "${SERVICE}" "${CLUSTER}" >&2
        exit 1
    fi

    printf "${TASKS}"
}

__describe_task() {
    local CLUSTER="$1"
    local TASK="$2"

    local IPS="$(aws ecs describe-tasks --cluster "${CLUSTER}" --task "${TASK}" --query 'tasks[*].containers[?lastStatus==`RUNNING`].networkInterfaces[*].privateIpv4Address' --output text)"
    if [ "$?" != "0" ]; then
        printf "fatal error: unable to describe task '%s' of cluster '%s'\n" "${TASK}" "${CLUSTER}" >&2
        exit 1
    fi

    printf "${IPS}"
}

__list_hosted_zones() {
    local ZONE="$1"

    local ZONE_ID="$(aws route53 list-hosted-zones --query 'HostedZones[?Name==`'${ZONE}'.`].Id' --output text)"
    if [ "$?" != "0" ]; then
        printf "fatal error: unable to list hosted zones ('%s')\n" "${ZONE}" >&2
        exit 1
    fi

    printf "${ZONE_ID}"
}

__change_resource_record_sets() {
    local ZONE_ID="$1"
    local CHANGE_BATCH="$2"

    local CHANGE_INFO="$(aws route53 change-resource-record-sets --hosted-zone-id "${ZONE_ID}" --change-batch "${CHANGE_BATCH}" --query 'ChangeInfo.Id' --output text)"
    if [ "$?" != "0" ]; then
        printf "fatal error: unable to change resource record sets for zone id '%s'\n" "${ZONE_ID}" >&2
        exit 1
    fi

    printf "${CHANGE_INFO}"
}

__wait_resource_record_sets_changed() {
    local CHANGE_INFO="$1"

    aws route53 wait resource-record-sets-changed --id "${CHANGE_INFO}"
    if [ "$?" != "0" ]; then
        printf "fatal error: unable to wait for resource record sets to be changed for change info '%s'\n" "${CHANGE_INFO}" >&2
        exit 1
    fi
}

__resource_record() {
    local IP="$1"

    local RESOURCE_RECORD='{ "Value": "__VALUE__" }'

    RESOURCE_RECORD="${RESOURCE_RECORD/__VALUE__/${IP}}"

    printf "${RESOURCE_RECORD}"
}

__change() {
    local SERVICE="$1"
    local RESOURCE_RECORDS="$2"
    local ZONE="$3"
    local TTL="$4"
    local PREFIX="$5"
    local SUFFIX="$6"

    local CHANGE='{ "Action": "UPSERT", "ResourceRecordSet": { "Name": "__NAME__", "Type": "A", "TTL": __TTL__, "ResourceRecords": [ __RESOURCE_RECORDS__ ] } }'

    if [ -n "${RESOURCE_RECORDS}" ]; then
        local NAME="__PREFIX____SERVICE____SUFFIX__.__ZONE__"

        NAME="${NAME/__SERVICE__/${SERVICE}}"
        NAME="${NAME/__ZONE__/${ZONE}}"
        NAME="${NAME/__PREFIX__/${PREFIX}}"
        NAME="${NAME/__SUFFIX__/${SUFFIX}}"

        CHANGE="${CHANGE/__NAME__/${NAME}}"
        CHANGE="${CHANGE/__RESOURCE_RECORDS__/${RESOURCE_RECORDS}}"
        CHANGE="${CHANGE/__TTL__/${TTL}}"
    else
        CHANGE=""
    fi

    printf "${CHANGE}"
}

__change_batch() {
    local CHANGES="$1"

    local CHANGE_BATCH='{ "Changes": [ __CHANGES__ ] }'

    if [ -n "${CHANGES}" ]; then
        CHANGE_BATCH="${CHANGE_BATCH/__CHANGES__/${CHANGES}}"
    else
        CHANGE_BATCH=""
    fi

    printf "${CHANGE_BATCH}"
}

# main

declare DRY_RUN
declare FILTER
declare PREFIX
declare SUFFIX
declare TTL
declare DO_NOT_WAIT
declare ZONE
declare ZONE_SPECIFIED

declare CLUSTERS
declare CLUSTER
declare SERVICES
declare SERVICE
declare TASKS
declare TASK
declare IPS
declare IP

declare CHANGES
declare RESOURCE_RECORDS
declare RESOURCE_RECORD
declare CHANGE
declare CHANGE_BATCH
declare ZONE_ID
declare CHANGE_INFO

while getopts :df:hp:s:t:z: OPT; do
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

        t)
            TTL="${OPTARG}"
            ;;

        w)
            DO_NOT_WAIT="1"
            ;;

        z)
            ZONE="${OPTARG}"
            ZONE_SPECIFIED="1"
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

                t)
                    printf "missing ttl" >&2
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

if [ -z "${TTL}" ]; then
    TTL=5
fi

printf "starting service discovery...\n"

CLUSTERS="$*"
for CLUSTER in ${CLUSTERS}; do
    printf "\ncluster: %s\n" "${CLUSTER}"

    if [ "${ZONE_SPECIFIED}" == "0" ]; then
        ZONE="${CLUSTER}"
    fi

    CHANGES=""

    SERVICES="$(__list_services "${CLUSTER}" "${FILTER}")"
    for SERVICE in ${SERVICES}; do
        SERVICE="${SERVICE##*/}"

        if [[ "$SERVICE" =~ $FILTER ]]; then
            printf "    service: %s\n" "${SERVICE}"

            RESOURCE_RECORDS=""

            TASKS="$(__list_tasks "${CLUSTER}" "${SERVICE}")"
            for TASK in ${TASKS}; do
                TASK="${TASK##*/}"
                printf "        task: %s\n" "${TASK}"

                IPS="$(__describe_task "${CLUSTER}" "${TASK}")"
                for IP in ${IPS}; do
                    printf "            ip: %s\n" "${IP}"

                    RESOURCE_RECORD="$(__resource_record "${IP}")"
                    RESOURCE_RECORDS="${RESOURCE_RECORDS},${RESOURCE_RECORD}"
                done
            done

            RESOURCE_RECORDS="${RESOURCE_RECORDS#,}"

            CHANGE="$(__change "${SERVICE}" "${RESOURCE_RECORDS}" "${ZONE}" "${TTL}" "${PREFIX}" "${SUFFIX}")"

            CHANGES="${CHANGES},${CHANGE}"
        fi
    done

    CHANGES="${CHANGES#,}"

    CHANGE_BATCH="$(__change_batch "${CHANGES}")"

    if [ -n "${CHANGE_BATCH}" ]; then
        printf "\nchange batch:\n\n%s\n\n" "${CHANGE_BATCH}"

        ZONE_ID="$(__list_hosted_zones "${ZONE}")"

        if [ -n "${ZONE_ID}" ]; then
            ZONE_ID="${ZONE_ID##*/}"
            printf "zone id: %s\n" "${ZONE_ID}"

            if [ "${DRY_RUN}" != "1" ]; then
                printf "sending change batch...\n"
                CHANGE_INFO="$(__change_resource_record_sets "${ZONE_ID}" "${CHANGE_BATCH}")"
                CHANGE_INFO="${CHANGE_INFO##*/}"
                printf "change info: %s\n" "${CHANGE_INFO}"

                if [ -z "${DO_NOT_WAIT}" ]; then
                    printf "waiting for the change batch to be synced...\n"
                    __wait_resource_record_sets_changed "${CHANGE_INFO}"
                    printf "done.\n"
                fi
            else
                printf "dry-run.\n"
            fi
        else
            printf "fatal error: zone not found ('%s')\n" "${ZONE}" >&2
            exit 1
        fi
    else
        printf "no changes required.\n"
    fi
done

printf "\nservice discovery completed.\n"

exit 0
