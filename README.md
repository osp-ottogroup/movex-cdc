# MOVEX Change Data Capture: track changes in relational databases and transfer them to Kafka

This product captures data change events (Insert/Update/Delete) in relational databases by database triggers and immediately transfers the data changes to a Kafka event hub.

The full documentation of this product you may find here:
- HTML: https://otto-group-solution-provider.gitlab.io/movex-cdc/movex-cdc.html
- PDF: https://otto-group-solution-provider.gitlab.io/movex-cdc/movex-cdc.pdf

## Supported database systems
- <b>Oracle</b> First productive usage for Enterprise Edition with Partitioning Option (Rel. 12.1. ++ )
- <b>SQLite</b> The aditional implementation for SQLite ensures that the product remains database independent.


## Usage
MOVEX Change Data Capture is offered as a single compact Docker image.

The latest build of master branch is available by:<br/>
`docker pull registry.gitlab.com/otto-group-solution-provider/movex-cdc:master`

Production ready releases are tagged like 'prod_x.xx' and can be pulled by:<br/>
`docker pull registry.gitlab.com/otto-group-solution-provider/movex-cdc:prod_x.xx`

A quick start demo you may find here: https://otto-group-solution-provider.gitlab.io/movex-cdc/movex-cdc_demo.html

## Support
If you have bug reports or questions please file an issue inside the product or mail to movex-cdc@osp.de.

## Roadmap
The tool has been developed independently of a particular database system.
First implementations have been for SQLite and Oracle with focus on productive usage for Oracle Enterprise Edition with Partitioning Option.
<br/>
Further planned implementations are:
- Production readyness for Oracle Standard Edition / EE without Partitiong Option
- PostgreSQL
- MS SQL-Server

## License
This product can be used under the terms and conditions of [GPL 3](https://gitlab.com/otto-group-solution-provider/movex-cdc/-/blob/master/LICENSE).

## Project status
It is already used in production with Oracle databases.
Further development takes place.

## Release history of Docker images
* Last nightly build based on master branch: 
  `docker pull registry.gitlab.com/otto-group-solution-provider/movex-cdc:master`
