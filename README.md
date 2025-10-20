<div style="display: block; text-align: center; font-size: xx-large"><img src="doc/images/one.o_small.svg" style="height: 1.1em;">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<span style="color: #5f696e;">M<span style="color: red;">O</span>VEX<span style="font-weight: normal;">| Change Data Capture</span></span></div>

# Track changes in relational databases and transfer them to Kafka 

This product captures data change events (Insert/Update/Delete) in relational databases by database triggers and immediately transfers the data changes to a Kafka event hub.

The full documentation of this product you may find here:
- HTML: https://osp-silver.gitlab.io/oss/movex-cdc/movex-cdc.html
- PDF: https://osp-silver.gitlab.io/oss/movex-cdc/movex-cdc.pdf

![](doc/images/event_flow.svg)

## Supported database systems
- <b>Oracle</b> Oracle databases with Release 12.1 and higher
- <b>SQLite</b> The aditional implementation for SQLite ensures that the product remains database independent.


## Usage
MOVEX Change Data Capture is offered as a comprehensive Docker image.<br>

## Quick start demo
Establish change data capture on Oracle DB including event transfer to Kafka within 10 minutes.<br/>
[Here you find the howto guide to quickly get up and running.](https://osp-silver.gitlab.io/oss/movex-cdc/movex-cdc_demo.html)

## Releases
Production-ready releases are tagged with release number and can be pulled from Docker hub by:<br/>
`docker pull ottogroupsolutionproviderosp/movex-cdc:1.7.0`

The current production-ready release is also tagged with `:latest` and can by pulled without a tag by:<br>
`docker pull ottogroupsolutionproviderosp/movex-cdc`

The latest build of the development master branch is available by:<br/>
`docker pull registry.gitlab.com/osp-silver/oss/movex-cdc:master`

## Release notes
[See CHANGELOG.md](CHANGELOG.md)

## License / Support
MOVEX Change Data Capture is a product of the Otto Group One.O Gmbh.<br/>
This product can be used under the terms and conditions of [GPL 3](https://gitlab.com/osp-silver/oss/movex-cdc/-/blob/master/LICENSE).<br/>
One.O is the IT service provider of the Otto Group, formery known as Otto Group Solution Provider (OSP) GmbH.<br/>
If you are interested in commercial support please reach out to [movex-cdc@osp.de](mailto:movex-cdc@osp.de).<br/>

## Roadmap
The tool has been developed independently of a particular database system.
First implementations have been for SQLite and Oracle with focus on productive usage for Oracle Enterprise Edition with Partitioning Option.
<br/>
Further planned implementations are:
- Production readyness for Oracle Standard Edition / EE without Partitiong Option
- Adaptation for PostgreSQL and MS SQL Server, but only if there will be significant advantages compared to the existing solution [Debezium](https://debezium.io)

## Project status
It is already used in production with Oracle databases.
Further development takes place.

## Further resources
- [Vieo recording of JUG Saxony meeting on this topic (German) ](https://vimeo.com/705639939)