# Upgrading or Migrating PostgreSQL with Minimal Downtime

## Step 1 - Setup

Before we get started migrating, let's use [docker compose (or the container tool of your choosing)](https://docs.docker.com/desktop/) to get an example application up and running to migrate.

Run the following command:

```shell
git co step1
docker compose up
```

This may take a few minutes. It will create a PostgreSQL 12 instance, a Spree E-Commerce instance, and a job to populate the database with products.

The Spree application may restart a few times while the data is getting populated.

Once the application is up visit: `http://localhost:4000/admin` and log in with:

Username: `test@example.com`

Password: `password!`

This is the dataset we will be restoring to PostgreSQL 15.

## Step 2 - PostgreSQL 15

Next, let's add a PostgreSQL 15 instance that we will migrate to.

```shell
git co step2
docker compose up
```

**Note:** We are using port `5433` for the PostgreSQL instance to avoid port collisions.

The Spree application is still using PostgreSQL 12. Browse the admin dashboard to confirm.

You can connect to the PG 15 database:

```shell
# Get a shell
docker compose exec postgres15 bash

# Connect using psql
psql -U pg15_user -d pg15_db
```

You should see a version like: `psql (15.3 (Debian 15.3-1.pgdg120+1))`

## Step 3 - Dump and Restore PG12 to PG15

This step is optional in production workloads. We recommend it for large databases as it can significantly decrease the time it takes to get the source (PG12) and destination (PG15) databases in sync.

```shell
# Connect to PG12
docker compose exec postgres12 bash

# Dump the 'store' database to tar format (-F t)
pg_dump -U pg12_user -F t store > store-dump.tar

# Copy dump to local filesystem
docker cp postgres12:/store-dump.tar .

# Copy dump to PG15
docker cp ./store-dump.tar postgres15:/store-dump.tar

# Connec to PG15
docker compose exec postgres15 bash

# Restore the Database
pg_restore -d pg15_db /store-dump.tar --no-owner --role=pg15_user -C -U pg15_user
```

**Note:** `pg_dump` and `pg_restore` have a lot of options. We advise reading up on the user manual when preparing your dump/restore strategy.

Let's break down the `pg_dump`` and `pg_restore` commands.

### `pg_dump`

* `-U` user
* `-F` file format: tar
* `"store"` final argument is the database schema to dumb

### `pg_restore`

* `-d` database - here we picked "pg15_db" as we knew that database existed. You must pick an existing database. The dump has the name of the schema we actually plan to restore.
* `-C` create schema - this will cause `pg_restore` to create the schema referenced in the dump before restoring
* `-U` user
* `--no-owner` - remove the `pg12_user` as the owner of the database objects
* `--role` - set the new owner of the objects created

### Confirm DB was restored

```shell
docker compose exec postgres12 bash
psql -U pg12_user -d pg12_db

pg12_db=# \c store
store=# select count(*) from spree_products;
# ~> 116 rows
```

```shell
docker compose exec postgres15 bash
psql -U pg15_user -d pg15_db

pg15_db=# \c store
store=# select count(*) from spree_products;
# ~> # of rows from above
```
