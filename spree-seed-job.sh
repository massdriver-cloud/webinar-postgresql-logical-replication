#! /bin/sh

bundle exec rails db:create && \
  bundle exec rails db:migrate && \
  bundle exec rake db:seed && \
  bundle exec rake spree_sample:load
