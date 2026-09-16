FROM ruby:3.4-alpine

WORKDIR /app

RUN apk add --no-cache docker-cli docker-cli-compose ca-certificates \
    && apk add --no-cache --virtual .build-deps build-base

COPY Gemfile ./
RUN bundle config set without development \
    && bundle install \
    && apk del .build-deps

COPY app.rb config.ru ./
COPY lib ./lib
COPY web ./web

EXPOSE 8080
CMD ["bundle", "exec", "puma", "-b", "tcp://0.0.0.0:8080", "config.ru"]
