FROM ruby:4.0.10-slim-trixie

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git libpq-dev libsqlite3-dev libyaml-dev pkg-config \
    && rm -rf /var/lib/apt/lists/*
RUN gem install bundler --version 4.1.0 --no-document

WORKDIR /gem
COPY Gemfile Gemfile.lock tailnet_mcp.gemspec ./
COPY lib/tailnet_mcp/version.rb lib/tailnet_mcp/
RUN bundle install --jobs 4
