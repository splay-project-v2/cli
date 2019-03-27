FROM python:3.7.2-slim
LABEL Description="Splay - RPC Client - App able to launch lua script to get/push information to the controller"

RUN mkdir -p /usr/splay/src
RUN mkdir -p /usr/splay/algorithms

WORKDIR /usr/splay/

ADD ./src ./src
ADD ./algorithms ./algorithms
ADD ./requirements.txt ./

RUN pip install -r requirements.txt

WORKDIR /usr/splay/src

CMD tail -f /dev/null
