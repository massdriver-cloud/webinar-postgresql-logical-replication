# Upgrading or Migrating PostgreSQL with Minimal Downtime

## Setup

Before we get started migrating, we'll use [docker compose (or the container tool of your choosing)](https://docs.docker.com/desktop/) to get an example application up and running to migrate.

Run the following command:

```shell
docker compose up
```

This may take a few minutes. It will create a PostgreSQL 12 instance, a Spree E-Commerce instance, a job to populate the PG 12 database with products, and an idle PostgreSQL 15 instance.

**Note**: This webinar/tutorial connects to the source and destination multiple times and includes the docker command each time for doing so. I recommend opening two shells and keeping PG 12 and 15 side by side to simplify following along.

The Spree application may restart a few times while the data is getting populated.

Once the application is up visit [http://localhost:4000/admin](http://localhost:4000/admin) and log in with:

Username: `test@example.com`

Password: `password!`

This is the data in this storefront is what we will be migrating to PostgreSQL 15.

## Upgrading / Migrating

With logical replication there are two options for getting your existing data into the destination database:

* Using `copy_data = true` with the replication subscription
* Using `copy_data = false` and performing pg_dump/pg_restore

TODO: cover pros/cons

To perform logical replication we'll need to make sure the WAL level (`wal_level`) is set to `logical`.

The Write-Ahead Log (WAL) in PostgreSQL is a transaction log that records changes to the database in a sequential manner. It serves as a reliable mechanism to ensure data durability, high availability, and crash recovery by allowing the replay of logged changes to reconstruct the database to a consistent state in the event of system failures.

Let's set the WAL level and restart the postgres instances:

```shell
docker cp postgresql.conf postgres12:/var/lib/postgresql/data/postgresql.conf
docker compose restart postgres12

docker cp postgresql.conf postgres15:/var/lib/postgresql/data/postgresql.conf
docker compose restart postgres15
```

**Note:** This webinar keeps the config pretty simple. You may want also want to create a custom role for replication.

### Using logical replication with `copy_data = true`

Logical replication only works on DML (data manipulation language). It will not replication DDL (schema changes), so we must get the schema onto the destination database first.

```shell
# Connect to PG12
docker compose exec postgres12 bash

# Dump the 'store' database to tar format (-F t)
pg_dump -U pg12_user --schema-only -F t store > store-dump.tar
exit
```

Copy the tar from PG 12 to PG 15
```shell
# Copy dump to local filesystem
docker cp postgres12:/store-dump.tar .

# Copy dump to PG15
docker cp ./store-dump.tar postgres15:/store-dump.tar
```

```shell
# Connect to PG15
docker compose exec postgres15 bash

# Restore the Databaseshow rep
pg_restore -d pg15_db /store-dump.tar --no-owner --role=pg15_user -C -U pg15_user
exit
```

**Note:** `pg_dump` and `pg_restore` have a lot of options. We advise reading up on the user manual when preparing your dump/restore strategy.

Let's break down the `pg_dump` and `pg_restore` commands.

`pg_dump`:

* `-U` user
* `-F` file format: tar
* `--schema-only` only copy schema
* `"store"` final argument is the database schema to dumb

`pg_restore`:

* `-d` database - here we picked "pg15_db" as we knew that database existed. You must pick an existing database. The dump has the name of the schema we actually plan to restore.
* `-C` create schema - this will cause `pg_restore` to create the schema referenced in the dump before restoring
* `-U` user
* `--no-owner` - remove the `pg12_user` as the owner of the database objects
* `--role` - set the new owner of the objects created

#### Setup Replication

In the publish-subscribe model of logical replication in PostgreSQL, a database creates and publishes a stream of changes as a publication. Other databases, acting as subscribers, can subscribe to these publications and receive a copy of the changes to keep their data synchronized, providing a flexible and selective means of replicating specific data changes between databases.

##### Create the publication on PG 12

```shell
docker compose exec postgres12 bash
psql -U pg12_user -d store
```

```sql
CREATE PUBLICATION pub_pg1215_migration FOR ALL TABLES;
```

##### Create the subscription on PG 15

```shell
docker compose exec postgres15 bash
psql -U pg15_user -d store
```

```sql
CREATE SUBSCRIPTION sub_pg1215_migration 
  CONNECTION 'dbname=store host=postgres12 user=pg12_user password=pg12_password' 
  PUBLICATION pub_pg1215_migration;
```
#### Confirm Data is Replicating

```shell
docker compose exec postgres12 bash
psql -U pg12_user -d store
```

```sql
select count(*) from spree_products;
-- ~> 116 rows
```

```shell
docker compose exec postgres15 bash
psql -U pg15_user -d store
```

```sql
select count(*) from spree_products;
-- ~> # of rows from above
```

So that feels good, but lets see what Postgres thinks.

Connect to PG 12 source database:

```shell
docker compose exec postgres12 bash
```

Check the replication status:

```sql
select * from  pg_stat_replication;
```

```
-[ RECORD 1 ]----+------------------------------
pid              | 59
usesysid         | 10
usename          | pg12_user
application_name | sub_pg1215_migration
client_addr      | 172.25.0.4
client_hostname  |
client_port      | 45238
backend_start    | 2023-08-08 16:13:09.264021+00
backend_xmin     |
state            | streaming
sent_lsn         | 0/243FA00 <-- Log sequence numbers (LSN) are all in sync
write_lsn        | 0/243FA00
flush_lsn        | 0/243FA00
replay_lsn       | 0/243FA00
write_lag        |
flush_lag        |
replay_lag       |
sync_priority    | 0
sync_state       | async
reply_time       | 2023-08-08 16:39:05.514689+00
```

Let's check the LSN received on the PG 15 instance.

```shell
docker compose exec postgres12 bash
```

```sql
select * from  pg_stat_subscription;
```

```
-[ RECORD 1 ]---------+------------------------------
subid                 | 17694
subname               | sub_pg1215_migration
pid                   | 51
relid                 |
received_lsn          | 0/243FA00
last_msg_send_time    | 2023-08-08 16:47:17.351882+00
last_msg_receipt_time | 2023-08-08 16:47:17.352277+00
latest_end_lsn        | 0/243FA00
latest_end_time       | 2023-08-08 16:47:17.351882+00
```

Looks like they are in sync!

If you are migrating using `copy_data = true` its time to [failover](#failover).

## Failover

