docker compose up

create & migrate happen in entry point ...

do we want to override w/ server and seed it exclusivley w/ a bash command to make it obvi?

    #     command = ["bundle"]
    #     args    = ["exec", "rails", "server"]



http://localhost:3000/admin

TAKE A BACKUP FIRST
DO WE NEED TO DITCH THE UI THING IS IT JUST EXTRA SHIT TO BE CONFUSED BY?
ssh into container

replication container poll status and print keep it running

bundle exec rails db:create
bundle exec rails db:migrate
bundle exec rake db:seed
bundle exec rake spree_sample:load


###

Why logical replication, tradeoffs vs DMS, bucardo, etc
gold status check replication
gold master queries - on you rown, is there a tool

diagrams to illustrate
Failover
Checking status
Dump to start (seems silly for a small data set but good practice)
Gold master checks for PostgreSQL

Bonus round ... VPCS in bound or out bound
