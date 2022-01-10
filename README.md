# MOVEX Change Data Capture: track changes in relational databases and transfer them to Kafka

This product captures data change events (Insert/Update/Delete) in relational databases by database triggers and immediately transfers the data changes to a Kafka event hub.

The full documentation of this product you may find as [HTML](https://otto-group-solution-provider.gitlab.io/movex-cdc/movex-cdc.html) or [PDF](https://otto-group-solution-provider.gitlab.io/movex-cdc/movex-cdc.pdf) document.

## Supported database systems
- <b>Oracle</b> First productive usage for Enterprise Edition with Partitioning Option (Rel. 12.1. ++ )
- <b>SQLite</b> The aditional implementation for SQLite ensures that the product remains database independent.


## Usage / Release history / Downloads
MOVEX Change Data Capture is offered as a single compact Docker image.

* The latest build of the master branch is available by:<br/>
`docker pull registry.gitlab.com/otto-group-solution-provider/movex-cdc:master`
* Production-ready releases are provided as separate Git branches with branch name 'prod_x.xx'.
* The most recent production-ready release branch is prod_1.06:<br/>
  `docker pull registry.gitlab.com/otto-group-solution-provider/movex-cdc:prod_1.06`

## Quick start demo
Establish change data capture on Oracle DB including event transfer to Kafka within 10 minutes!<br/>
[This guide](https://otto-group-solution-provider.gitlab.io/movex-cdc/movex-cdc_demo.html) shows you how to quickly get up and running.

## Support
If you have bug reports or questions please file an issue at GitLab or mail to movex-cdc@osp.de.

## Roadmap
The tool has been developed independently of a particular database system.
First implementations have been for SQLite and Oracle with focus on productive usage for Oracle Enterprise Edition with Partitioning Option.
<br/>
Further planned implementations are:
- Production readyness for Oracle Standard Edition / EE without Partitiong Option
- Adaptation for PostgreSQL and MS SQL Server, but only if in the result the application becomes easier than with the existing solution [Debezium](https://debezium.io)

## License
This product can be used under the terms and conditions of [GPL 3](https://gitlab.com/otto-group-solution-provider/movex-cdc/-/blob/master/LICENSE).

## Project status
Production usage with Oracle databases started in 2020.
Further development takes place.
