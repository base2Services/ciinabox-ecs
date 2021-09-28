FROM ruby:2.5-alpine

LABEL org.opencontainers.image.source = https://github.com/base2Services/ciinabox-ecs

ARG CFNDSL_SPEC_VERSION=${CFNDSL_SPEC_VERSION:-9.0.0}
ARG CIINABOX_ECS_VERSION='*'

COPY . /src

WORKDIR /src
RUN gem build ciinabox-ecs.gemspec && \
    gem install ciinabox-ecs-${CIINABOX_ECS_VERSION}.gem && \
    rm -rf /src

RUN adduser -u 1000 -D ciinabox && \
    apk add --update python3 py3-pip git openssh-client bash make gcc python3-dev musl-dev && \
    ln $(which pip3) /bin/pip && \
    pip install awscli

WORKDIR /work

USER ciinabox

RUN cfndsl -u ${CFNDSL_SPEC_VERSION}

# required for any calls via aws sdk
ENV AWS_REGION us-east-1

CMD 'ciinabox-ecs'