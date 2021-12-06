# MOVEX Change Data Capture: track changes in relational databases and transfer them to Kafka

This product captures data change events (Insert/Update/Delete) in relational databases by database triggers and immediately transfers the data changes to a Kafka event hub.

The full documentation of this product you may find here:
- HTML: https://otto-group-solution-provider.gitlab.io/movex-cdc/movex-cdc.html
- PDF: https://otto-group-solution-provider.gitlab.io/movex-cdc/movex-cdc.pdf

## Usage
MOVEX Change Data Capture is offered as a single compact Docker image.

## Support
If you have bug reports or questions please file an issue inside the product or mail to Peter.Ramm@ottogroup.com.

## Roadmap
The tool has been developed independently of a particular database system.
First implementations have been for SQLite and Oracle with focus on productive usage for Oracle databases.
Further implementations are planned for PostgreSQL and MS SQL-Server.

## License
This product can be used under the terms and conditions of GPL 3.

## Project status
It is already used in production with Oracle databases.
Further development takes place.
