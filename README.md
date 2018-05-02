# ecs-service-discovery

A handy shell script, that automatically discovers the services running on an
AWS ECS cluster, and creates/updates corresponding `A` records in a Route 53
zone. The record names are based on the services and will point to the IP
addresses under which the services are currently available.

## Background

End of March 2018, Amazon Web Services introduced
[Service Discovery for Amazon ECS](https://aws.amazon.com/about-aws/whats-new/2018/03/introducing-service-discovery-for-amazon-ecs).
Unfortunately, this new service is currently only available in specific regions.
This script is a workaround for all regions, where this service is not available
yet.

Whenever you (re-)deploy a service on an ECS cluster, simply run this script to
update your DNS automatically. This can also be done as part of a Jenkins
pipeline (which is why I wrote this script and how I am using it).

Hope you find it helpful!

## Requirements

* bash
* [AWS Command Line Interface](https://aws.amazon.com/cli/) installed and configured
* The user of `aws` needs to have the following policies attached:
  * `ecs:ListServices`
  * `ecs:ListTasks`
  * `ecs:DescribeTasks`
  * `ecs:DescribeServices`
  * `route53:ListHostedZones`
  * `route53:ChangeResourceRecordSets`
  * `route53:GetChange`
* `aws` needs to be added to your `PATH`

## Usage

To discover the services running on an ECS cluster named `my-cluster`, simply
run:

```
ecs-service-discovery.sh my-cluster
```

By default, the script expects the Route 53 zone to be named after the ECS
cluster. If the `A` records should be created/updated in a zone called
`testing`, use the `-z` option: 

```
ecs-service-discovery.sh -z testing my-cluster
```

If you have two services running, `frontend` and `backend`, this will
create/update two `A` records: `frontend.testing` and `backend.testing`.

You can also add a prefix (`-p`) and/or a suffix (`-s`) to the service names:

```
ecs-service-discovery.sh -p latest- -s -service -z testing my-cluster 
```

This will create/update `latest-frontend-service.testing` and `latest-backend-service.testing`.

You can also filter for the services to be considered, using the `-f` option:

```
ecs-service-discovery.sh -f '-ui$' my-cluster
``` 

This will only consider services ending with `-ui` (regex support).

For a dry-run, use the `-d` option.

To see all available options, use `-h`:

```
  -d             Perform a dry-run without making any changes.
  -f <filter>    Filter service names using a bash-compatible regex.
  -p <prefix>    Prefix to put in front of the service name in Route 53.
  -s <suffix>    Suffix to append to the service name in Route 53.
  -t <ttl>       TTL in seconds for the A records in Route 53 (default: 5).
  -w             Do NOT wait for the change batch to be synced.
  -z <zone>      Route 53 zone to update.
  -h             Print this help message and exit.
```

## License

This software is distributed under the terms of the
[GNU General Public License v3](https://www.gnu.org/licenses/gpl-3.0.en.html).
