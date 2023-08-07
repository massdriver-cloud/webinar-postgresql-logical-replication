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
