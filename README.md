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
