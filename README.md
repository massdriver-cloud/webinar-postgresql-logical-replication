# Upgrading or Migrating PostgreSQL with Minimal Downtime

## Setup

Before we get started migrating, we'll use [docker compose (or the container tool of your choosing)](https://docs.docker.com/desktop/) to get an example e-commerce application (Spree) up and running to migrate.

Run the following command:

```shell
docker compose up
```

TODO: replace job w/ a docker run cmd.
TODO: suggest opening  multiple tabs and clean up the docker compose connect stuff... 1. docker up, 2. local system 3. pg12, 4. pg15

This may take a few minutes. It will create a PostgreSQL 12 instance, a Spree E-Commerce instance, a job to populate the PG 12 database with products, and an idle PostgreSQL 15 instance.

**Note**: This webinar/tutorial connects to the source and destination multiple times and includes the docker command each time for doing so. I recommend opening two shells and keeping PG 12 and 15 side by side to simplify following along.

The Spree application may restart a few times while the data is getting populated.

Once the application is up visit [http://localhost:4000/admin](http://localhost:4000/admin) and log in with:

Username: `test@example.com`

Password: `password!`

This is the data in this storefront is what we will be migrating to PostgreSQL 15.

## Upgrading / Migrating Postgres with Logical Replication

With logical replication there are two options for getting your existing data into the destination database:

* Using `copy_data = true` with the replication subscription
* Using `copy_data = false` and performing pg_dump/pg_restore


**Using `copy_data = true` with the replication subscription:**

Pros:
* Ease of Use: Setting up a subscription with copy_data set to true is straightforward. PostgreSQL handles data replication automatically.
* Minimal Lag: Since data changes are replicated as they occur, the data lag between the source and target databases is minimized.

Cons:

* Network Overhead: Continuous replication generates network traffic, which might lead to increased network utilization and potential latency when replicating large datasets.
* Resource Consumption: Real-time replication can consume significant server resources on both databases, affecting their performance.

**Using `copy_data = false` and performing pg_dump/pg_restore:**

Pros:
* Controlled Replication: You have control over when the replication process occurs. This can help you manage the impact on server resources.
* Reduced Network Traffic: As replication is not continuous, there's less ongoing network traffic compared to real-time replication.

Cons:
* Complexity: Manual dump and restore processes involve more steps and potential for errors, especially with large datasets.
* Data Lag: Data replication is not immediate, resulting in data lag between the source and target databases.


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

### Logical replication with `copy_data = true`

This is a much simpler approach and is recommended for small datasets, migrations on the same subnet, or when resource consumption is not a concern.

We will:
1. Dump and restore the schema to the destination database
2. Create a replication publication
3. Create a replication subscription

Logical replication only works on DML (data manipulation language). It will not replication DDL (schema changes), so we must get the schema onto the destination database first.

```shell
# Connect to PG12
docker compose exec postgres12 bash

# Dump the 'store' database to tar format (-F t)
pg_dump -U pg12_user --schema-only -F t store > store-dump.tar
exit
```

Copy the tar from PG 12 to PG 15:
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

So that feels good. Add some products in the UI and rerun the PG15 query above to see the records getting replicated.

Now let's see what Postgres thinks.

Connect to PG 12 source database:

```shell
docker compose exec postgres12 bash
```

Check the replication status:

```sql
select * from  pg_stat_replication;
```

Check the values of the log sequence numbers (LSN)
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
sent_lsn         | 0/243FA00 <-- These are what you are looking for
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
docker compose exec postgres15 bash
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
received_lsn          | 0/243FA00 <-- This are what you are looking for
last_msg_send_time    | 2023-08-08 16:47:17.351882+00
last_msg_receipt_time | 2023-08-08 16:47:17.352277+00
latest_end_lsn        | 0/243FA00
latest_end_time       | 2023-08-08 16:47:17.351882+00
```

Looks like they are in sync! The difference between `last_msg_send_time` and `last_msg_receipt_time` can give you an idea of lag given both instances time are in sync.

If you are migrating using `copy_data = true` its time to [failover](#failover).

### Logical replication with `copy_data = false` + pg_dump/pg_restore

If you performed the previous logical replication step, you'll need to reset PG 15 and remove the publisher on PG 12.

**Reset PG 15:**

```shell
docker compose exec postgres15 bash
psql -U pg15_user -d store
```
```sql
DROP SUBSCRIPTION sub_pg1215_migration;
\c pg15_db;
DROP DATABASE store;
```

**Drop the publication:**

```shell
docker compose exec postgres12 bash
psql -U pg12_user -d store
```

```sql
DROP PUBLICATION pub_pg1215_migration;
SELECT pg_drop_replication_slot('sub_pg1215_migration'); -- this may fail if the subscriber already dropped the slot
```

This is the recommended approach for large data sets especially migrating or upgrading different networks. It can be time and resource consuming to replicate 100GB between something like Heroku and AWS RDS. This requires additional steps and downtime to prepare.

We will:

1. stop app **DOWNTIME** dont want records written between database dump and repl slot
1. Take a dump of PG 12
2. Create publication & replication slot on PG 12
3. start app
3. Restore snapshot to pg 15
4. Create paused subscription on PG 15
4. add records, check diff between dbs
5. enable stream (should get added records)

Stop the Spree API:
```shell
docker compose stop spree_api
```

Connect to PG12 and run pg_dump:

```shell
docker compose exec postgres12 bash
pg_dump -U pg12_user -F t store > store-dump.tar

psql -U pg12_user -d store
```

Create a publication on PG 12:

```sql
CREATE PUBLICATION pub_pg1215_migration FOR ALL TABLES;
SELECT pg_create_logical_replication_slot('sub_pg1215_migration', 'pgoutput');
```

Restart the Spree API:

```shell
docker compose start spree_api
```

Copy dump to PG 15 container:

```shell
# Copy schema dump to local filesystem
docker cp postgres12:/store-dump.tar .

# Copy schema dump to PG15
docker cp ./store-dump.tar postgres15:/store-dump.tar
```

Connect to PG 15 and restore:

```shell
docker compose exec postgres15 bash
pg_restore -d pg15_db /store-dump.tar --no-owner --role=pg15_user -C -U pg15_user;

psql -U pg15_user -d store;
```

Create a subscription on PG 15:

```sql
CREATE SUBSCRIPTION sub_pg1215_migration 
  CONNECTION 'dbname=store host=postgres12 user=pg12_user password=pg12_password' 
  PUBLICATION pub_pg1215_migration WITH (copy_data = false, create_slot=false, enabled=false, slot_name=sub_pg1215_migration);
```

At this point the snapshot is loaded on PG 15, but replication has not started. 

**Add and edit some records in the Spree admin dashboard to simulate users and see replication happen.**

On the PG 15 instance enable the subscription

```sql
ALTER SUBSCRIPTION sub_pg1215_migration ENABLE;
```

You should now be able to run queries on PG 12 and PG 15 and get the same results, for example: `SELECT COUNT(*) from spree_products;`

Now let's see what Postgres thinks.

Connect to PG 12 source database:

```shell
docker compose exec postgres12 bash
```

Check the replication status:

```sql
select * from  pg_stat_replication;
```

Check the values of the log sequence numbers (LSN)
```
-[ RECORD 1 ]----+------------------------------
pid              | 1235
usesysid         | 10
usename          | pg12_user
application_name | sub_pg1215_migration
client_addr      | 172.25.0.3
client_hostname  |
client_port      | 52094
backend_start    | 2023-08-09 03:59:52.950325+00
backend_xmin     |
state            | streaming
sent_lsn         | 0/25A97D0 <-- These are what you are looking for
write_lsn        | 0/25A97D0
flush_lsn        | 0/25A97D0
replay_lsn       | 0/25A97D0
write_lag        |
flush_lag        |
replay_lag       |
sync_priority    | 0
sync_state       | async
reply_time       | 2023-08-09 04:10:15.565649+00
```

Let's check the LSN received on the PG 15 instance.

```shell
docker compose exec postgres15 bash
```

```sql
select * from  pg_stat_subscription;
```

```
-[ RECORD 1 ]---------+------------------------------
subid                 | 26874
subname               | sub_pg1215_migration
pid                   | 1781
relid                 |
received_lsn          | 0/25A97D0 <-- This is what you are looking for
last_msg_send_time    | 2023-08-09 04:10:25.602431+00
last_msg_receipt_time | 2023-08-09 04:10:25.602842+00
latest_end_lsn        | 0/25A97D0
latest_end_time       | 2023-08-09 04:10:25.602431+00
```

Looks like they're in sync! Its time to "failover" to PG 15.

## Failover

**DOWNTIME**

**Important!**

Sequence data is not copied during logical replication. This can be seen by running the following command on both databases:

```sql
SELECT sequencename, last_value
FROM pg_sequences
ORDER BY last_value DESC NULLS LAST;
```

* Pause App
* check repl & sub status ... drop subscripton
  **Note:** Another great tool for monitoring replication is [PGMetrics](https://pgmetrics.io/docs/index.html).
* update sequences
  `psql -h $old_instance -XAtqc "SELECT $$select setval('$$ || quote_ident(schemaname)||$$.$$|| quote_ident(sequencename) || $$', $$ || last_value || $$); $$ AS sql FROM pg_sequences" store | psql -h $new_instance store`
* change dns/auth for app
* start!
* verify data
